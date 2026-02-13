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

  alias Dividendsomatic.Portfolio.Holding
  alias Dividendsomatic.Repo
  alias Dividendsomatic.Stocks
  alias Dividendsomatic.Stocks.SymbolMapping

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
    # US stocks (delisted/renamed — use last known or successor ticker)
    "US23317H1023" => "SITC",
    "US6915431026" => "OXLC",
    "US72202D1063" => "PCI",
    "US76882G1647" => "RIV",
    "US91325V1089" => "UNIT",
    "US98417P1057" => "XIN"
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
    "US90273A2078" => "delisted ETN (ETRACS 2x MLP)"
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
  Re-resolves all pending ISINs using Finnhub API lookup.

  Rate-limited to ~1 request/second. Returns `{resolved, unmappable, still_pending}` counts.
  """
  def resolve_pending do
    pending =
      SymbolMapping
      |> where([m], m.status == "pending")
      |> order_by([m], asc: m.isin)
      |> Repo.all()

    Logger.info("SymbolMapper: attempting to resolve #{length(pending)} pending ISINs via Finnhub")

    Enum.reduce(pending, {0, 0, 0}, fn mapping, {res, unmap, pend} ->
      # Rate limit: 1 request per 1.1 seconds (safe margin for 60/min)
      Process.sleep(1_100)

      case resolve_fresh(mapping.isin, mapping.security_name) do
        {:ok, symbol} ->
          Logger.info("  ✓ #{mapping.isin} → #{symbol}")
          {res + 1, unmap, pend}

        {:unmappable, reason} ->
          Logger.info("  ✗ #{mapping.isin} — #{reason}")
          {res, unmap + 1, pend}

        {:pending, _} ->
          Logger.info("  ? #{mapping.isin} — still pending")
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
  Returns all resolved symbol mappings.
  """
  def list_resolved do
    SymbolMapping
    |> where([m], m.status == "resolved")
    |> Repo.all()
  end

  @doc """
  Returns all symbol mappings.
  """
  def list_all do
    SymbolMapping
    |> order_by([m], asc: m.isin)
    |> Repo.all()
  end

  @doc """
  Returns the exchange suffix map for reference.
  """
  def exchange_suffix_map, do: @exchange_suffix

  # Step 1: Check cached result in symbol_mappings table
  defp check_cache(isin) do
    case Repo.get_by(SymbolMapping, isin: isin) do
      %SymbolMapping{status: "resolved", finnhub_symbol: symbol} ->
        {:ok, symbol}

      %SymbolMapping{status: "unmappable", notes: notes} ->
        {:unmappable, notes || "cached unmappable"}

      _ ->
        {:miss, isin}
    end
  end

  # Step 2: Check holdings table for IBKR data (has isin + symbol + listing_exchange)
  defp check_holdings(isin) do
    holding =
      Holding
      |> where([h], h.isin == ^isin and not is_nil(h.listing_exchange))
      |> order_by([h], desc: h.report_date)
      |> limit(1)
      |> Repo.one()

    case holding do
      %Holding{symbol: symbol, listing_exchange: exchange} when is_binary(symbol) ->
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

  # Cache the resolution result
  defp cache_result(isin, security_name, result) do
    attrs =
      case result do
        {:ok, symbol} ->
          %{
            isin: isin,
            finnhub_symbol: symbol,
            security_name: security_name,
            status: "resolved"
          }

        {:unmappable, reason} ->
          %{
            isin: isin,
            security_name: security_name,
            status: "unmappable",
            notes: reason
          }

        {:pending, _} ->
          %{
            isin: isin,
            security_name: security_name,
            status: "pending"
          }
      end

    case Repo.get_by(SymbolMapping, isin: isin) do
      nil ->
        %SymbolMapping{}
        |> SymbolMapping.changeset(attrs)
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:isin])

      existing ->
        existing
        |> SymbolMapping.changeset(attrs)
        |> Repo.update()
    end
  end

  # Get distinct ISINs with security names from broker_transactions
  defp distinct_isins do
    alias Dividendsomatic.Portfolio.BrokerTransaction

    BrokerTransaction
    |> where([t], not is_nil(t.isin) and t.transaction_type in ["buy", "sell"])
    |> group_by([t], [t.isin, t.security_name])
    |> select([t], {t.isin, max(t.security_name)})
    |> Repo.all()
  end
end
