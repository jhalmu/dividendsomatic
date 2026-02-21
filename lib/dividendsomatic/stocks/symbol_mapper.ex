defmodule Dividendsomatic.Stocks.SymbolMapper do
  @moduledoc """
  Resolves ISIN identifiers to Finnhub-compatible ticker symbols.

  Uses a cascading lookup strategy:
  1. Check `symbol_mappings` table (cached result)
  2. Check `holdings` table (IBKR has isin + symbol + listing_exchange)
  3. Country-prefix heuristics (FI* → .HE, SE* → .ST, etc.)
  4. Auto-detect unmappable: BULL/BEAR/TRACKER in security_name
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.{Instrument, InstrumentAlias, Position}
  alias Dividendsomatic.Repo
  alias Dividendsomatic.Stocks

  # IB exchange → Finnhub symbol suffix mapping
  @exchange_suffix %{
    "HEX" => ".HE",
    "SFB" => ".ST",
    "OSE" => ".OL",
    "TSE" => ".TO",
    "TSEJ" => ".T",
    "SBF" => ".PA",
    "FWB" => ".F",
    "FWB2" => ".F",
    "IBIS" => ".DE",
    "LSE" => ".L",
    "SEHK" => ".HK",
    "NYSE" => "",
    "NASDAQ" => "",
    "ARCA" => "",
    "AMEX" => ""
  }

  # Patterns indicating leveraged/structured products that can't be priced
  @unmappable_patterns ~w(BULL BEAR TRACKER MINI TURBO WARRANT CERTIFIKAT)

  # Static ISIN → Finnhub symbol map for Nordic/European stocks
  # (Finnhub free tier ISIN lookup only works for US stocks)
  @known_isin_symbols %{
    # Helsinki (HEX) — .HE suffix
    "FI0009000459" => "HUH1V.HE",
    "FI0009000681" => "NOKIA.HE",
    "FI0009002158" => "UPONOR.HE",
    "FI0009002471" => "CTY1S.HE",
    "FI0009003727" => "WRT1V.HE",
    "FI0009004824" => "KEMIRA.HE",
    "FI0009005078" => "PON1V.HE",
    "FI0009005318" => "TYRES.HE",
    "FI0009006548" => "ATRAV.HE",
    "FI0009007264" => "BITTI.HE",
    "FI0009007983" => "DIGIA.HE",
    "FI0009009377" => "CAPMAN.HE",
    "FI0009009617" => "EQV1V.HE",
    "FI0009010854" => "LAT1V.HE",
    "FI0009013403" => "KNEBV.HE",
    "FI0009014344" => "OKDAV.HE",
    "FI0009014351" => "OKDBV.HE",
    "FI0009800098" => "AFAGR.HE",
    "FI0009800395" => "RAIVV.HE",
    "FI0009800643" => "YIT.HE",
    "FI0009900385" => "MARAS.HE",
    "FI0009902530" => "NDA-FI.HE",
    "FI4000008719" => "TIK1V.HE",
    "FI4000062195" => "TAALA.HE",
    "FI4000102678" => "NXTMH.HE",
    "FI4000123096" => "SAVOH.HE",
    "FI4000270350" => "TITAN.HE",
    "FI4000369947" => "CTY1S.HE",
    # Stockholm (SFB) — .ST suffix
    "SE0000120669" => "SSAB-B.ST",
    "SE0007185418" => "NOBINA.ST",
    "SE0007665823" => "RESURS.ST",
    # Oslo (OSE) — .OL suffix
    "NO0003054108" => "MOWI.OL",
    "NO0010735343" => "EPR.OL",
    # Bermuda / other
    "BMG162581083" => "BEP",
    # Irish ETFs (London listing)
    "IE00B4L5YX21" => "SJPA.L",
    "IE00BKM4GZ66" => "EIMI.L",
    # Stockholm (SFB) — .ST suffix (additional)
    "SE0005190238" => "TEL2-B.ST",
    "SE0011311554" => "DIVIO-B.ST",
    # Copenhagen (CSE) — .CO suffix
    "DK0010244425" => "MAERSK-A.CO",
    "DK0060534915" => "NOVO-B.CO",
    # Frankfurt (FWB) — .DE suffix
    "DE0005810055" => "DB1.DE",
    "DE000BFB0019" => "B4B.DE",
    "DE000A1X3YY0" => "BST.DE",
    # Madrid (BME) — .MC suffix
    "ES0173516115" => "REP.MC",
    "ES0178430E18" => "TEF.MC",
    # Paris (Euronext) — .PA suffix
    "FR0000133308" => "ORA.PA",
    "FR0013412293" => "PE500.PA",
    # London (LSE) — .L suffix
    "GB00BKFB1C65" => "MNG.L",
    "GB00BGXQNP29" => "PHNX.L",
    "JE00B4T3BW64" => "GLEN.L",
    # Hong Kong (SEHK) — .HK suffix
    "CNE100000Q43" => "1288.HK",
    "CNE1000002F5" => "1800.HK",
    "KYG1644A1004" => "1428.HK",
    # Toronto (TSX) — .TO suffix
    "CA13321L1085" => "CCJ.TO",
    "CA29250N1050" => "ENB.TO",
    "CA25537R1091" => "DFN.TO",
    "CA25537W1086" => "DF.TO",
    "CA25537Y1043" => "DGS.TO",
    "CA31660A1030" => "FSZ.TO",
    "CA37252B1022" => "MIC.TO",
    "CA65685J3010" => "FFN.TO",
    "CA7669101031" => "REI-UN.TO",
    "CA85210A1049" => "U-UN.TO",
    "CA91702V1013" => "UROY.TO",
    # Canadian stocks listed on US exchanges (no suffix)
    "CA0679011084" => "GOLD",
    "CA2926717083" => "UUUU",
    "CA60255C1095" => "MMED",
    "CA91688R1082" => "URG",
    # Bermuda (NYSE-listed, no suffix)
    "BMG657731060" => "NAT",
    "BMG7738W1064" => "SFL",
    # Marshall Islands (NYSE-listed shipping, no suffix)
    "MHY1968P1218" => "DAC",
    "MHY2065G1219" => "DHT",
    "MHY2685T1313" => "GNK",
    "MHY271836006" => "GSL",
    "MHY481251012" => "KNOP",
    "MHY622674098" => "NMM",
    "MHY8162K2046" => "SBLK",
    "MHY7542C1306" => "STNG",
    "MHY8564M1057" => "TGP",
    # Singapore (NYSE-listed)
    "SG9999019087" => "GRIN",
    "SG9999012629" => "KEN",
    # UK (NYSE-listed ADR)
    "GB00BLP5YB54" => "AY",
    # US stocks (Finnhub missed or delisted)
    "US23317H1023" => "SITC",
    "US6915431026" => "OXLC",
    "US72202D1063" => "PCI",
    "US76882G1647" => "RIV",
    "US91325V1089" => "UNIT",
    "US98417P1057" => "XIN",
    "US00165C1045" => "AMC",
    "US0357104092" => "NLY",
    "US0030091070" => "FAX",
    "US0030111035" => "IAF",
    "US11135B1008" => "BRMK",
    "US19249B1061" => "MIE",
    "US19249X1081" => "PTA",
    "US2263442087" => "CEQP",
    "US27829M1036" => "EXD",
    "US33731K1025" => "FEO",
    "US33739M1009" => "FPL",
    "US37954A2042" => "GMRE",
    "US38983D3008" => "AJX",
    "US40167B1008" => "GPM",
    "US48661E1082" => "KMF",
    "US55272X1028" => "MFA",
    "US63253R2013" => "KAP",
    "US67401P1084" => "OCSL",
    "US6475811070" => "EDU",
    "US79471V1052" => "SMM",
    "US82575P1075" => "SBSW",
    "US8793822086" => "TEF",
    "US8816242098" => "TEVA",
    "US90187B4086" => "TWO",
    "US92838U1088" => "NCZ",
    "US92838X1028" => "NCV",
    "US9810641087" => "WF"
  }

  # ISINs that are definitively unmappable (index funds, structured products, delisted ETNs)
  @unmappable_isins %{
    "DE000CV5RCK8" => "structured product (B SHRTNES AT CZB)",
    "SE0002756973" => "Nordnet internal index fund",
    "SE0005993078" => "Nordnet internal index fund",
    "SE0005993102" => "Nordnet internal index fund",
    "SE0005993110" => "Nordnet internal index fund",
    "SE0017077480" => "leveraged product (T LONG NQ100)",
    "US26923G1031" => "delisted ETF (InfraCap MLP)",
    "US6740012017" => "delisted (Oaktree Capital, merged into Brookfield)",
    "US90267B7652" => "delisted ETN (ETRACS 2x BDC)",
    "US90269A3023" => "delisted ETN (ETRACS 2x Mortgage REIT)",
    "US90270L8422" => "delisted ETN (UBS AG London notes)",
    "US90273A2078" => "delisted ETN (ETRACS 2x MLP)",
    # Preferred shares / rights (non-standard ISINs, no price data available)
    "US0423155078" => "delisted preferred (ARR old class)",
    "US0423156068" => "preferred share (ARR-C)",
    "US2263443077" => "preferred share (CEQP-P)",
    "US37957W2035" => "preferred share (GMRE-A)",
    "US78590A5056" => "preferred share (SACH-A)",
    "US6496048736" => "preferred share (NYMTM)",
    "US3765368846" => "preferred share (GOODO)",
    "US86164W1009" => "delisted fund (EDI, merged)",
    "US16934Q3074" => "preferred share (CIM-A)",
    "US16934Q4064" => "preferred share (CIM-B)",
    "US75968N3098" => "preferred share (RNR-F)",
    "US8794337878" => "preferred share (TDS-U)",
    "US8794337613" => "preferred share (TDS-V)",
    "MHY2745C1104" => "preferred share (GMLPP)",
    "MHY3262R1181" => "preferred share (HMLP-A)",
    "US0030571220" => "expired rights (ACP-RT)",
    "US48249T1227" => "expired rights (KIO-RT)",
    "US219RGT0243" => "expired rights (CLM.RTS)",
    "US219RGT0573" => "expired rights (CLM.RTS)",
    "US26924B30EX" => "expired rights (CLM subscription)",
    "US768BAS0482" => "expired rights (OPP subscription)",
    "US226PAY0161" => "corporate action (CEQP tender)",
    "US226CON0148" => "corporate action (CEQP consent)",
    "DE000KE2FEZ5" => "structured product (EUR/USD turbo)",
    "XS1526243446" => "structured ETC (natural gas)",
    "BMG9156K1018" => "delisted (2020 Bulkers, Oslo-listed)",
    "US1514611003" => "delisted fund (Center Coast Brookfield)",
    "US3682872078" => "delisted ADR (Gazprom, sanctions)",
    "CA03765K1049" => "delisted (Aphria, acquired by Tilray)",
    "CA1973091079" => "delisted (Columbia Care, acquired by Cresco Labs)",
    "CA04016E2024" => "micro-cap venture (Argentina Lithium)",
    "MU0456S00006" => "micro-cap (Alphamin Resources)"
  }

  @doc """
  Resolves an ISIN to a Finnhub symbol.

  Returns `{:ok, symbol}` if resolved, `{:unmappable, reason}` if the security
  can't be mapped, or `{:pending, isin}` if resolution failed.
  """
  def resolve(isin, security_name \\ nil) do
    case check_cache(isin) do
      {:ok, _} = cached -> cached
      {:unmappable, _} = cached -> cached
      {:miss, _} -> resolve_uncached(isin, security_name)
    end
  end

  defp resolve_uncached(isin, security_name) do
    result =
      with {:miss, _} <- check_holdings(isin),
           {:miss, _} <- check_known_isins(isin),
           {:miss, _} <- lookup_finnhub_isin(isin, security_name) do
        resolve_by_heuristics(isin, security_name)
      else
        {:ok, _} = found -> found
        {:unmappable, _} = unmap -> unmap
      end

    cache_result(isin, security_name, result)
    result
  end

  @doc """
  Resolves all unresolved ISINs from broker_transactions.

  Returns `{resolved, unmappable, pending}` counts.
  """
  def resolve_all do
    distinct_isins()
    |> Enum.reduce({0, 0, 0}, fn {isin, security_name}, {res, unmap, pend} ->
      case resolve(isin, security_name) do
        {:ok, _} -> {res + 1, unmap, pend}
        {:unmappable, _} -> {res, unmap + 1, pend}
        {:pending, _} -> {res, unmap, pend + 1}
      end
    end)
  end

  @doc """
  Re-resolves all instruments without a finnhub alias using Finnhub API lookup.

  Rate-limited to ~1 request/second. Returns `{resolved, unmappable, still_pending}` counts.
  """
  def resolve_pending do
    # Find instruments that have no finnhub/symbol_mapping alias
    resolved_isins =
      from(a in InstrumentAlias,
        join: i in Instrument,
        on: a.instrument_id == i.id,
        where: a.source in ["finnhub", "symbol_mapping"],
        select: i.isin
      )
      |> Repo.all()
      |> MapSet.new()

    pending =
      Instrument
      |> where([i], not is_nil(i.isin))
      |> order_by([i], asc: i.isin)
      |> Repo.all()
      |> Enum.reject(fn i -> MapSet.member?(resolved_isins, i.isin) end)

    Logger.info(
      "SymbolMapper: attempting to resolve #{length(pending)} pending ISINs via Finnhub"
    )

    Enum.reduce(pending, {0, 0, 0}, fn instrument, {res, unmap, pend} ->
      # Rate limit: 1 request per 1.1 seconds (safe margin for 60/min)
      Process.sleep(1_100)

      case resolve_fresh(instrument.isin, instrument.name) do
        {:ok, symbol} ->
          Logger.info("  ✓ #{instrument.isin} → #{symbol}")
          {res + 1, unmap, pend}

        {:unmappable, reason} ->
          Logger.info("  ✗ #{instrument.isin} — #{reason}")
          {res, unmap + 1, pend}

        {:pending, _} ->
          Logger.info("  ? #{instrument.isin} — still pending")
          {res, unmap, pend + 1}
      end
    end)
  end

  # Force fresh resolution (bypasses cache, updates it)
  defp resolve_fresh(isin, security_name) do
    result =
      with {:miss, _} <- check_holdings(isin),
           {:miss, _} <- check_known_isins(isin),
           {:miss, _} <- lookup_finnhub_isin(isin, security_name) do
        resolve_by_heuristics(isin, security_name)
      else
        {:ok, _} = found -> found
        {:unmappable, _} = unmap -> unmap
      end

    cache_result(isin, security_name, result)
    result
  end

  @doc """
  Returns all resolved symbol mappings as maps with :isin and :finnhub_symbol keys.
  """
  def list_resolved do
    from(a in InstrumentAlias,
      join: i in Instrument,
      on: a.instrument_id == i.id,
      where: a.source in ["finnhub", "symbol_mapping"],
      select: %{isin: i.isin, finnhub_symbol: a.symbol, exchange: a.exchange}
    )
    |> Repo.all()
  end

  @doc """
  Returns all symbol mappings (resolved aliases).
  """
  def list_all do
    list_resolved()
  end

  @doc """
  Returns the exchange suffix map for reference.
  """
  def exchange_suffix_map, do: @exchange_suffix

  # Step 1: Check cached result in instrument_aliases table
  defp check_cache(isin) do
    # Check known unmappable ISINs first
    case Map.get(@unmappable_isins, isin) do
      nil ->
        # Look for a finnhub/symbol_mapping alias via instrument
        result =
          from(a in InstrumentAlias,
            join: i in Instrument,
            on: a.instrument_id == i.id,
            where: i.isin == ^isin and a.source in ["finnhub", "symbol_mapping"],
            limit: 1,
            select: {a.symbol, a.exchange}
          )
          |> Repo.one()

        case result do
          nil -> {:miss, isin}
          {symbol, exchange} -> {:ok, qualify_symbol(symbol, exchange)}
        end

      reason ->
        {:unmappable, reason}
    end
  end

  # Reconstruct exchange-qualified symbol (e.g., "AKTIA" + "HE" → "AKTIA.HE")
  defp qualify_symbol(symbol, exchange) when is_binary(exchange) and exchange != "" do
    if String.contains?(symbol, ".") do
      symbol
    else
      "#{symbol}.#{exchange}"
    end
  end

  defp qualify_symbol(symbol, _exchange), do: symbol

  # Step 2: Check positions table for IBKR data (has isin + symbol + exchange)
  defp check_holdings(isin) do
    position =
      Position
      |> where([p], p.isin == ^isin and not is_nil(p.exchange))
      |> order_by([p], desc: p.date)
      |> limit(1)
      |> Repo.one()

    case position do
      %Position{symbol: symbol, exchange: exchange} when is_binary(symbol) ->
        finnhub_symbol = apply_exchange_suffix(symbol, exchange)
        {:ok, finnhub_symbol}

      _ ->
        {:miss, isin}
    end
  end

  # Step 2.5: Check static ISIN→symbol map and known unmappable ISINs
  defp check_known_isins(isin) do
    cond do
      symbol = Map.get(@known_isin_symbols, isin) -> {:ok, symbol}
      reason = Map.get(@unmappable_isins, isin) -> {:unmappable, reason}
      true -> {:miss, isin}
    end
  end

  # Step 3: Finnhub ISIN lookup via /stock/profile2?isin=
  defp lookup_finnhub_isin(isin, security_name) do
    if unmappable_product?(security_name) do
      {:unmappable, "leveraged/structured product: #{security_name}"}
    else
      case Stocks.lookup_symbol_by_isin(isin) do
        {:ok, %{symbol: symbol, exchange: exchange}} when is_binary(symbol) and symbol != "" ->
          finnhub_symbol = apply_exchange_suffix(symbol, exchange_to_key(exchange))
          Logger.info("SymbolMapper: resolved #{isin} → #{finnhub_symbol} via Finnhub")
          {:ok, finnhub_symbol}

        {:error, :not_found} ->
          {:miss, isin}

        {:error, :rate_limited} ->
          Logger.warning("SymbolMapper: rate limited on #{isin}, will retry later")
          {:miss, isin}

        {:error, reason} ->
          Logger.warning("SymbolMapper: Finnhub lookup failed for #{isin}: #{inspect(reason)}")
          {:miss, isin}
      end
    end
  end

  # Map Finnhub exchange names back to suffix keys
  @exchange_name_to_key %{
    "HELSINKI" => "HEX",
    "STOCKHOLM" => "SFB",
    "OSLO BORS" => "OSE",
    "TORONTO" => "TSE",
    "TOKYO" => "TSEJ",
    "PARIS" => "SBF",
    "FRANKFURT" => "FWB",
    "XETRA" => "IBIS",
    "LONDON" => "LSE",
    "HONG KONG" => "SEHK",
    "NEW YORK STOCK EXCHANGE, INC." => "NYSE",
    "NEW YORK STOCK EXCHANGE" => "NYSE",
    "NASDAQ NMS - GLOBAL MARKET" => "NASDAQ",
    "NASDAQ" => "NASDAQ",
    "NYSE ARCA" => "ARCA",
    "NYSE AMERICAN, LLC" => "AMEX"
  }

  defp exchange_to_key(nil), do: nil

  defp exchange_to_key(exchange) when is_binary(exchange) do
    upper = String.upcase(exchange)

    # Try exact match first, then prefix match
    Map.get(@exchange_name_to_key, upper) ||
      Enum.find_value(@exchange_name_to_key, fn {name, key} ->
        if String.starts_with?(upper, name), do: key
      end)
  end

  # Step 4: Heuristic resolution — detect unmappable products, otherwise pending
  defp resolve_by_heuristics(isin, security_name) do
    if unmappable_product?(security_name) do
      {:unmappable, "leveraged/structured product: #{security_name}"}
    else
      {:pending, isin}
    end
  end

  defp unmappable_product?(nil), do: false

  defp unmappable_product?(name) do
    upper = String.upcase(name)
    Enum.any?(@unmappable_patterns, &String.contains?(upper, &1))
  end

  defp apply_exchange_suffix(symbol, exchange) do
    suffix = Map.get(@exchange_suffix, exchange, "")
    symbol <> suffix
  end

  # Cache the resolution result in instrument_aliases (only for resolved symbols)
  defp cache_result(isin, _security_name, {:ok, symbol}) do
    case Repo.get_by(Instrument, isin: isin) do
      nil ->
        # No instrument for this ISIN, can't cache
        :ok

      instrument ->
        {base_symbol, exchange} = split_finnhub_symbol(symbol)

        existing =
          Repo.one(
            from(a in InstrumentAlias,
              where:
                a.instrument_id == ^instrument.id and a.source in ["finnhub", "symbol_mapping"],
              limit: 1
            )
          )

        alias_attrs = %{
          instrument_id: instrument.id,
          symbol: base_symbol,
          exchange: exchange,
          source: "finnhub"
        }

        case existing do
          nil ->
            %InstrumentAlias{}
            |> InstrumentAlias.changeset(alias_attrs)
            |> Repo.insert(on_conflict: :nothing)

          record ->
            record
            |> InstrumentAlias.changeset(alias_attrs)
            |> Repo.update()
        end
    end
  end

  defp cache_result(_isin, _security_name, _other), do: :ok

  # "KESKOB.HE" -> {"KESKOB", "HE"}, "AAPL" -> {"AAPL", nil}
  defp split_finnhub_symbol(symbol) do
    case String.split(symbol, ".") do
      [base, exchange] -> {base, exchange}
      _ -> {symbol, nil}
    end
  end

  # Get distinct ISINs with security names from trades + instruments
  defp distinct_isins do
    alias Dividendsomatic.Portfolio.{Instrument, Trade}

    Trade
    |> join(:inner, [t], i in Instrument, on: t.instrument_id == i.id)
    |> where([t, i], not is_nil(i.isin))
    |> group_by([t, i], [i.isin, i.name])
    |> select([t, i], {i.isin, max(i.name)})
    |> Repo.all()
  end
end
