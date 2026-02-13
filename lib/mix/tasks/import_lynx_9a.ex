defmodule Mix.Tasks.ImportLynx9a do
  @moduledoc """
  Import sold positions from Lynx 9A tax form CSV extract.

  The 9A CSV has total amounts (not per-share), so we derive per-share prices.
  Stock names are mapped to ticker symbols via DB lookups and a manual map.

  ## Usage

      mix import.lynx_9a [--year 2019] [--year 2020] [--dry-run]

  Without --year flags, imports all years present in the CSV.
  """
  use Mix.Task
  require Logger

  alias Dividendsomatic.Portfolio.SoldPosition
  alias Dividendsomatic.Repo

  import Ecto.Query

  @csv_path "csv_data/archive/lynx_all_9a_trades.csv"

  @shortdoc "Import sold positions from Lynx 9A tax form CSV"
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [year: :keep, dry_run: :boolean],
        aliases: [n: :dry_run]
      )

    years = Keyword.get_values(opts, :year)
    dry_run = Keyword.get(opts, :dry_run, false)

    if dry_run, do: IO.puts("=== DRY RUN — no database changes ===\n")

    trades = read_csv()
    IO.puts("Read #{length(trades)} trades from #{@csv_path}")

    trades =
      if years != [] do
        filtered = Enum.filter(trades, &(&1.tax_year in years))
        IO.puts("Filtered to years #{inspect(years)}: #{length(filtered)} trades")
        filtered
      else
        trades
      end

    name_map = build_name_to_symbol_map()
    IO.puts("Name→symbol mappings: #{map_size(name_map)} (DB + manual)")

    {created, skipped, errors} = import_trades(trades, name_map, dry_run)

    IO.puts("\n#{"=" |> String.duplicate(60)}")
    IO.puts("Results: #{created} created, #{skipped} skipped, #{errors} errors")
    if dry_run, do: IO.puts("(dry run — nothing was written)")
  end

  defp read_csv do
    @csv_path
    |> File.stream!()
    |> NimbleCSV.RFC4180.parse_stream(skip_headers: false)
    |> Enum.to_list()
    |> then(fn [header | rows] ->
      keys = Enum.map(header, &String.to_atom/1)
      Enum.map(rows, fn row -> Enum.zip(keys, row) |> Map.new() end)
    end)
  end

  defp import_trades(trades, name_map, dry_run) do
    Enum.reduce(trades, {0, 0, 0}, fn trade, {created, skipped, errors} ->
      case import_one(trade, name_map, dry_run) do
        :created -> {created + 1, skipped, errors}
        :skipped -> {created, skipped + 1, errors}
        :error -> {created, skipped, errors + 1}
      end
    end)
  end

  defp import_one(trade, name_map, dry_run) do
    with {:ok, attrs} <- build_attrs(trade, name_map),
         false <- position_exists?(attrs) do
      if dry_run do
        IO.puts(
          "  WOULD CREATE: #{attrs.symbol} qty=#{attrs.quantity} " <>
            "sold=#{attrs.sale_date} pnl=~#{format_pnl(trade)}"
        )

        :created
      else
        case %SoldPosition{} |> SoldPosition.changeset(attrs) |> Repo.insert() do
          {:ok, _} ->
            :created

          {:error, cs} ->
            IO.puts("  ERROR: #{trade.stock_name} — #{inspect(cs.errors)}")
            :error
        end
      end
    else
      true ->
        :skipped

      {:error, reason} ->
        IO.puts("  SKIP: #{trade.stock_name} — #{reason}")
        :skipped
    end
  end

  defp build_attrs(trade, name_map) do
    quantity = parse_decimal(trade.quantity)
    sell_price_total = parse_decimal(trade.sell_price)
    buy_price_total = parse_decimal(trade.buy_price)

    cond do
      is_nil(quantity) or Decimal.compare(quantity, 0) != :gt ->
        {:error, "invalid quantity: #{trade.quantity}"}

      is_nil(sell_price_total) or Decimal.compare(sell_price_total, 0) != :gt ->
        {:error, "invalid sell_price: #{trade.sell_price}"}

      is_nil(buy_price_total) or Decimal.compare(buy_price_total, 0) != :gt ->
        {:error, "invalid buy_price: #{trade.buy_price}"}

      true ->
        sale_price = Decimal.div(sell_price_total, quantity) |> Decimal.round(6)
        purchase_price = Decimal.div(buy_price_total, quantity) |> Decimal.round(6)

        symbol = resolve_symbol(trade.stock_name, name_map)

        {:ok,
         %{
           symbol: symbol,
           description: trade.stock_name,
           quantity: quantity,
           purchase_price: purchase_price,
           purchase_date: parse_date(trade.buy_date),
           sale_price: sale_price,
           sale_date: parse_date(trade.sell_date),
           currency: "EUR",
           source: "lynx_9a",
           notes: "Tax year #{trade.tax_year}, account #{trade.account}"
         }}
    end
  end

  defp position_exists?(attrs) do
    SoldPosition
    |> where(
      [s],
      s.symbol == ^attrs.symbol and
        s.sale_date == ^attrs.sale_date and
        s.purchase_date == ^attrs.purchase_date and
        s.purchase_price == ^attrs.purchase_price and
        s.quantity == ^attrs.quantity and
        s.source == "lynx_9a"
    )
    |> Repo.exists?()
  end

  defp resolve_symbol(stock_name, name_map) do
    key = String.upcase(String.trim(stock_name))
    Map.get(name_map, key, stock_name)
  end

  defp build_name_to_symbol_map do
    db_map = build_db_map()
    Map.merge(db_map, manual_name_map())
  end

  defp build_db_map do
    # From broker_transactions: security_name → raw_data->symbol
    bt_mappings =
      from(bt in "broker_transactions",
        where: bt.broker == "ibkr" and bt.transaction_type in ["buy", "sell"],
        select: %{
          name: bt.security_name,
          symbol: fragment("raw_data->>'symbol'")
        },
        distinct: true
      )
      |> Repo.all()

    # From sold_positions: description → symbol
    sp_mappings =
      from(sp in "sold_positions",
        where: not is_nil(sp.description) and sp.description != "",
        select: %{name: sp.description, symbol: sp.symbol},
        distinct: true
      )
      |> Repo.all()

    (bt_mappings ++ sp_mappings)
    |> Enum.reduce(%{}, fn m, acc ->
      if m.symbol && m.name do
        Map.put(acc, String.upcase(String.trim(m.name)), String.trim(m.symbol))
      else
        acc
      end
    end)
  end

  # Manual mapping for stocks not found in DB
  defp manual_name_map do
    %{
      # 2019-2020 stocks
      "ABERDEEN ASIA-PAC INCOME FD" => "FAX",
      "ALLIANZGI CONV & INCOME II" => "NCZ",
      "ANNALY CAPITAL MANAGEMENT IN" => "NLY",
      "APOLLO INVESTMENT CORP" => "AINV",
      "BURE EQUITY AB" => "BURE",
      "CASTLE BRANDS INC" => "ROX",
      "CENTER COAST BROOKFIELD MLP &" => "CEN",
      "CHERRY HILL MORTGAGE INVESTM" => "CHMI",
      "COHEN & STEERS INFRASTRUCTUR" => "UTF",
      "COLUMBIA SELIG PREM TECH GW" => "STK",
      "DEUTSCHE BOERSE AG" => "DB1",
      "DHT HOLDINGS INC" => "DHT",
      "DOUBLELINE INCOME SOLUTIONS" => "DSL",
      "DUFF & PHELPS SEL MLP & MIDS" => "DSE",
      "DUFF & PHELPS UTILITY & INC" => "DPG",
      "FIRST TRUST ABERDEEN EMG OPP" => "FEO",
      "FRONTLINE LTD" => "FRO",
      "GABELLI MULTIMEDIA TRUST INC" => "GGT",
      "GAMCO GLOBAL GOLD NATURAL RE" => "GGN",
      "GEO GROUP INC/THE" => "GEO",
      "INVESTOR AB-B SHS" => "INVE-B",
      "ISHARES GLOBAL CLEAN ENERGY" => "ICLN",
      "JOHN HANCOCK FINANCIAL OPPOR" => "BTO",
      "KAYNE ANDERSON MIDSTREAM/ENE" => "KYN",
      "MILLER/HOWARD HIGH INCOME EQ" => "HIE",
      "MIND MEDICINE MINDMED INC" => "MNMD",
      "NEW RESIDENTIAL INVESTMENT" => "NRZ",
      "NUVEEN CREDIT STRAT INCM" => "JQC",
      "OFS CREDIT CO INC" => "OCCI",
      "PACIFIC COAST OIL TRUST" => "ROYT",
      "QUANTUMSCAPE CORP" => "QS",
      "RESURS HOLDING AB" => "RESURS",
      "RIVERNORTH OPPORTUNITI-RT-WI" => "RIV-RT",
      "SMART EYE AB" => "SEYE",
      "STONE HARBOR EMER MKT INC" => "EDI",
      "SVENSKA HANDELSBANKEN-A SHS" => "SHB-A",
      "TCG BDC INC" => "CGBD",
      "TEKLA HEALTHCARE INVESTORS" => "HQH",
      "UNUM GROUP" => "UNM",
      "VOYA ASIA PAC HI DVD EQ INC" => "IAE",
      "VOYA EMRG MRKTS HI INC DVD" => "IHD",
      "WASHINGTON PRIME GROUP INC" => "WPG",
      # 2021-2024 stocks
      "ABBVIE INC" => "ABBV",
      "ABERDEEN ASIA-PACIFIC INCOME" => "FAX",
      "ABERDEEN GLOBAL INCOME FUND" => "FCO",
      "ABERDEEN INCOME CREDI-RT" => "ACP-RT",
      "AGRICULTURAL BANK OF CHINA-H" => "1288",
      "ALLSPRING INCOME OPPORTUNITI" => "EAD",
      "ALPHAMIN RESOURCES CORP" => "AFM",
      "ALTRIA GROUP INC" => "MO",
      "AMC ENTERTAINMENT HLDS-CL A" => "AMC",
      "AMGEN INC" => "AMGN",
      "AMUNDI PEA SP500 H UCITS ETF" => "PE500",
      "APHRIA INC" => "APHA",
      "APPLE INC" => "AAPL",
      "ARES DYNAMIC CREDIT ALLOCATI" => "ARDC",
      "ARGENTINA LITHIUM & ENERGY C" => "LIT.V",
      "ARMOUR RESIDENTIAL REIT" => "ARR",
      "ARMOUR RESIDENTIAL REIT INC" => "ARR",
      "ATLANTICA SUSTAINABLE INFRAS" => "AY",
      "BALLARD POWER SYSTEMS INC" => "BLDP",
      "BARINGS GL SH DUR HI YLD" => "BGH",
      "BASTEI LUBBE AG" => "BST-DE",
      "BLACKROCK ENHANCED EQTY DVD" => "BDJ",
      "BLACKROCK MULTI-SECTOR INCOM" => "BIT",
      "BNYM HIGH YIELD STRAT" => "BYM",
      "BRANDYWINEGLOBAL GLOBAL INCO" => "BWG",
      "BRIGHT SMART SECURITIES AND" => "1428",
      "BROADMARK REALTY CAPITAL INC" => "BRMK",
      "CALAMOS DYNAMIC CONVERTIBLE" => "CCD",
      "CATO CORP-CLASS A" => "CATO",
      "CBRE GLOBAL REAL ESTATE INCO" => "IGR",
      "CENTRAL AND EASTERN EUROPE F" => "CEE",
      "CHINA COMMUNICATIONS CONST-H" => "1800",
      "CHINA FUND INC" => "CHN",
      "CIBUS NORDIC REAL ESTAT PUBL" => "CIBUS",
      "CIBUS NORDIC REAL ESTATE AB" => "CIBUS",
      "CIM 8 PERP PD" => "CIM-PD",
      "CLOUGH GLOBAL EQUITY FUND" => "GLQ",
      "CLOVER HEALTH INVESTMENTS CO" => "CLOV",
      "COHEN & STEERS MLP INCOME AN" => "MIE",
      "COHEN & STEERS QUAL INC RLTY" => "RQI",
      "COHEN & STEERS REIT AND PREF" => "RNP",
      "COHEN & STEERS SELECT PREFER" => "PSF",
      "COHEN & STEERS TAX-ADVANTAGE" => "PTA",
      "COLUMBIA CARE INC" => "CCHWF",
      "COMMUNITY HEALTHCARE TRUST I" => "CHCT",
      "COMPASS PATHWAYS PLC" => "CMPS",
      "CORECIVIC INC" => "CXW",
      "CREDIT SUISSE ASSET MGMT INC" => "CIK",
      "CRESTWOOD EQUITY PARTNER" => "CEQP",
      "CRESTWOOD EQUITY PARTNERS LP" => "CEQP",
      "CTO REALTY GROWTH INC" => "CTO",
      "CUSHING NEXTGEN INFRA INC" => "SZC",
      "CYCLO THERAPEUTICS INC" => "CYTH",
      "DANAOS CORP" => "DAC",
      "DIVIDEND 15 SPLIT CORP II-A" => "DFN",
      "DIVIDEND 15 SPLIT CORP-A" => "DFN",
      "DIVIDEND GROWTH SPLIT CORP-A" => "DGS",
      "DIVIO TECHNOLOGIES AB" => "DIVIO",
      "EATON VANCE RISK-MANAGED DIV" => "ETJ",
      "EATON VANCE T/A GL DVD INCM" => "ETO",
      "EATON VANCE T/M BUY-WR IN" => "ETB",
      "EATON VANCE T/M BUY-WRITE OP" => "ETV",
      "EATON VANCE TAX-MANAGED GLOB" => "EXG",
      "EATON VANCE TAX-MGD B/W STR" => "EXD",
      "ELLSWORTH GROWTH AND INCOME" => "ECF",
      "ENBRIDGE INC" => "ENB",
      "ENTERPRISE PRODUCTS PARTNERS" => "EPD",
      "EURUSD 18MAR21 1.2225 1.2225 P EUR/USD Turbo Bear" => "EUR-TURBO",
      "FIERA CAPITAL CORP" => "FSZ",
      "FIRST SOLAR INC" => "FSLR",
      "FIRST TRUST ABERDEEN GLOBAL" => "FAM",
      "FIRST TRUST HIGH INCOME LONG" => "FSD",
      "FIRST TRUST NEW OPPORTUNITIE" => "FPL",
      "FLAH & CRUM TTL RTRN FND" => "FLC",
      "FLAHERTY & CRUMRINE PREFERRE" => "FFC",
      "FORTRESS BIOTECH INC" => "FBIO",
      "FRANKLIN LTD DUR INC TR" => "FTF",
      "GAZPROM PJSC-SPON ADR" => "OGZPY",
      "GENWORTH MI CANADA INC" => "MIC",
      "GLENCORE PLC" => "GLEN",
      "GLOBAL MEDICAL REIT INC" => "GMRE",
      "GLOBAL NET LEASE INC" => "GNL",
      "GLOBAL SHIP LEASE INC-CL A" => "GSL",
      "GMLP 8/34 PERP PFD" => "GMLP-PA",
      "GREAT AJAX CORP" => "AJX",
      "GRINDROD SHIPPING HOLDINGS L" => "GRIN",
      "GUGGENHEIM ENHANCED EQUITY I" => "GPM",
      "GUGGENHEIM STRATEGIC OPPORTU" => "GOF",
      "HIGHLAND GLOBAL ALLOCATION" => "HGLB",
      "HMLP 8 3/4 PERP PFD" => "HMLP-PA",
      "INTEL CORP" => "INTC",
      "IRON MOUNTAIN INC" => "IRM",
      "KAYNE ANDERSON NEXTGEN ENERG" => "KYN",
      "KENON HOLDINGS LTD" => "KEN",
      "KKR INCOME OPPORTUNITIES" => "KIO",
      "KKR INCOME OPPORTUNITIES FUN" => "KIO",
      "KNOT OFFSHORE PARTNERS LP" => "KNOP",
      "LAZARD GLOBAL TOT RT & INC" => "LGI",
      "LIBERTY ALL STAR EQUITY FUND" => "USA",
      "LIBERTY ALL-STAR GROWTH FD" => "ASG",
      "META PLATFORMS INC-CLASS A" => "META",
      "METRO AG" => "B4B",
      "MFA FINANCIAL INC" => "MFA",
      "NAC KAZATOMPROM JSC-GDR" => "KAP",
      "NEW AMERICA HIGH INCOME FUND" => "HYB",
      "NEW ORIENTAL EDUCATIO-SP ADR" => "EDU",
      "NEW YORK MORTGAGE TRUST" => "NYMT",
      "NEWTEK BUSINESS SERVICES COR" => "NEWT",
      "NOVO NORDISK A/S-B" => "NVO",
      "NUVEEN REAL EST INC FD" => "JRS",
      "PCM FUND INC" => "PCM",
      "PENNANTPARK INVESTMENT CORP" => "PNNT",
      "PGIM GLOBAL HIGH YIELD FUND" => "GHY",
      "PIMCO CORPORATE & INCOME OPP" => "PTY",
      "PIMCO DYNAMIC CREDIT AND MOR" => "PCI",
      "PIMCO GLOBAL STOCKSPLUS & IN" => "PGP",
      "PIONEER DIVERSIFIED HIGH INC" => "HNW",
      "PLUG POWER INC" => "PLUG",
      "POWERCELL SWEDEN AB" => "PCELL",
      "READY CAPITAL CORP" => "RC",
      "REAVES UTILITY INCOME FUND" => "UTG",
      "RENESOLA LTD-ADR" => "SOL",
      "REPSOL SA" => "REP",
      "SABA CAPITAL INCOME & OPPORT" => "BRW",
      "SALIENT MIDSTREAM & MLP FUND" => "SMM",
      "SCORPIO TANKERS INC" => "STNG",
      "SFL CORP LTD" => "SFL",
      "SG ETC NAT GAS DAILY EU HDG" => "GASZ",
      "SPECIAL OPPORTUNITIES FUND" => "SPE",
      "SPROTT PHYSICAL URANIUM TRUS" => "U.UN",
      "STONE HARBOR EM MKT TOTL INC" => "EDI",
      "TAIWAN FUND INC" => "TWN",
      "TEEKAY LNG PARTNERS LP" => "TGP",
      "TEKLA WORLD HEALTHCARE FUND" => "THW",
      "TELEFONICA SA" => "TEF",
      "TELEFONICA SA-SPON ADR" => "TEF",
      "TEMPLETON EMERG MKTS INC FD" => "TEI",
      "TEVA PHARMACEUTICAL-SP ADR" => "TEVA",
      "TORTOISE ENERGY INFRASTRUCT" => "TYG",
      "TWO HARBORS INVESTMENT CORP" => "TWO",
      "UNIVERSAL HEALTH RLTY INCOME" => "UHT",
      "UR-ENERGY INC" => "URG",
      "URANIUM ENERGY CORP" => "UEC",
      "URANIUM ROYALTY CORP" => "UROY",
      "USA COMPRESSION PARTNERS LP" => "USAC",
      "VICI PROPERTIES INC" => "VICI",
      "VIRTUS ALLIANZGI ARTIFICIAL" => "AIO",
      "VIRTUS ALLIANZGI CN & INC II" => "NCZ",
      "VIRTUS ALLIANZGI CONVERTIBLE &" => "NCV",
      "VIRTUS ALLIANZGI DIV & INC" => "NFJ",
      "VOYA GLOBAL ADVANTAGE AND PR" => "IGA",
      "WESTERN ASSET GL CORP DEF OP" => "GDO",
      "WESTERN ASSET GLOBAL HIGH IN" => "EHI",
      "WOORI FINANCIAL-SPON ADR" => "WF",
      "WP CAREY INC - SPINOFF" => "WPC-SO"
    }
  end

  defp parse_date(str) when is_binary(str) do
    case String.split(str, "/") do
      [d, m, y] ->
        Date.new!(String.to_integer(y), String.to_integer(m), String.to_integer(d))

      _ ->
        nil
    end
  end

  defp parse_date(_), do: nil

  defp parse_decimal(str) when is_binary(str) and str != "" do
    case Decimal.parse(str) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp parse_decimal(_), do: nil

  defp format_pnl(trade) do
    cond do
      trade.gain != "" -> "+#{trade.gain}"
      trade.loss != "" -> "-#{trade.loss}"
      true -> "0"
    end
  end
end
