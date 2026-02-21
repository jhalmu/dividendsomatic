defmodule Mix.Tasks.Backfill.Aliases do
  @moduledoc """
  Backfill and clean up instrument aliases.

  Sub-tasks:
  1. Split comma-separated aliases into individual records
  2. Set is_primary flags (best alias per instrument)
  3. Fix instruments.symbol to base names (remove broker codes)

  With --variants flag, also collects variant aliases from positions,
  sold_positions, and trades tables.

  ## Usage

      mix backfill.aliases              # Split commas, set primary, fix base names
      mix backfill.aliases --variants   # Also collect variant aliases from data tables
      mix backfill.aliases --dry-run    # Preview without changes
  """

  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{Instrument, InstrumentAlias, Trade}
  alias Dividendsomatic.Repo

  require Logger

  @shortdoc "Clean up instrument aliases: split commas, set primary, fix base names"

  # Broker code / full company name → canonical ticker overrides
  @base_name_overrides %{
    # Nordic broker codes
    "TELIA1" => "TELIA",
    "NDA FI" => "NORDEA",
    "NDA1V" => "NORDEA",
    "STERV" => "STORA ENSO",
    "KNEBV" => "KONE",
    "NOKIA HEX" => "NOKIA",
    "OUT1V" => "OUTOKUMPU",
    "FORTUM HEX" => "FORTUM",
    "SAMPO HEX" => "SAMPO",
    "UPM HEX" => "UPM-KYMMENE",
    "ORNBV" => "ORION",
    "NESTE HEX" => "NESTE",
    "TIETO HEX" => "TIETOEVRY",
    "WRT1V" => "WARTSILA",
    "METSO HEX" => "METSO",
    "CTY1S" => "CITYCON",
    "METSB HEX" => "METSA BOARD",
    "KCR" => "KONECRANES",
    "KESKOB" => "KESKO",
    "HUH1V" => "HUHTAMAKI",
    "ELISA HEX" => "ELISA",
    "VALMT" => "VALMET",
    "SSABBH" => "SSAB",
    "TLS" => "TELIA",
    "DP4A" => "MAERSK",
    "P500H" => "PE500",
    "CEN.OLD" => "CENTRICA",
    "GLAD.OLD" => "GLAD",
    "M&G PLC" => "MNG",
    "BIOGEN INC" => "BIIB",
    # Full company names → tickers (from IBKR aliases)
    "ALIBABA GROUP HOLDING-SP ADR" => "BABA",
    "ALGONQUIN POWER & UTILITIES" => "AQN",
    "AMERICAN AXLE & MFG HOLDINGS" => "AXL",
    "ANTERO MIDSTREAM CORP" => "AM",
    "ABRDN INCOME CREDIT STRATEGI" => "ACP",
    "BARRICK GOLD CORP" => "GOLD",
    "BLACKROCK CORP HI YLD" => "HYT",
    "BLACKSTONE SECURED LENDING F" => "BXSL",
    "CIBUS NORDIC REAL ESTATE AB" => "CIBUS",
    "CLOUGH GLBL OPPORTUNITIES FD" => "GLO",
    "ENERGY FUELS INC" => "UUUU",
    "FORTRESS BIOTECH INC" => "FBIOP",
    "FREEPORT-MCMORAN INC" => "FCX",
    "GENCO SHIPPING & TRADING LTD" => "GNK",
    "GILEAD SCIENCES INC" => "GILD",
    "GLADSTONE CAPITAL CORP" => "GLAD",
    "GLADSTONE COMMERCIAL CORP" => "GOOD",
    "GLADSTONE COMMER" => "GOODO",
    "NAVIOS MARITIME PARTNERS LP" => "NMM",
    "NEXTERA ENERGY PARTNERS LP" => "NEP",
    "NORDIC AMERICAN TANKERS LTD" => "NAT",
    "NORTH AMERICAN FINANCIAL" => "FFN",
    "OAKTREE SPECIALTY LENDING CO" => "OCSL",
    "OCCIDENTAL PETROLEUM CORP" => "OXY",
    "ONEMAIN HOLDINGS INC" => "OMF",
    "PERMIANVILLE ROYALTY TRUST" => "PVL",
    "PETROLEO BRASILEIRO-SPON ADR" => "PBR",
    "PHOENIX GROUP HOLDINGS PLC" => "PHNX",
    "SABRA HEALTH CARE REIT INC" => "SBRA",
    "SIBANYE-STILLWATER LTD-ADR" => "SBSW",
    "SIXTH STREET SPECIALTY LENDI" => "TSLX",
    "STAR BULK CARRIERS CORP" => "SBLK",
    "TELEFONICA SA-SPON ADR" => "TEF",
    "TPG RE FINANCE TRUST INC" => "TRTX",
    "WP CAREY INC" => "WPC",
    "WP CAREY INC - SPINOFF" => "NLOP",
    "ZIM INTEGRATED SHIPPING SERV" => "ZIM",
    "ZOOM VIDEO COMMUNICATIONS-A" => "ZM"
  }

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Logger.configure(level: :info)

    {opts, _, _} = OptionParser.parse(args, switches: [dry_run: :boolean, variants: :boolean])
    dry_run = opts[:dry_run] || false
    variants = opts[:variants] || false

    if dry_run, do: Mix.shell().info("=== DRY RUN — no changes will be made ===\n")

    Mix.shell().info("=== Backfilling instrument aliases ===\n")

    unless dry_run do
      split_count = split_comma_aliases()
      Mix.shell().info("Step 1: Split #{split_count} comma-separated aliases\n")

      primary_count = set_primary_flags()
      Mix.shell().info("Step 2: Set is_primary on #{primary_count} instruments\n")

      base_count = fix_base_names()
      Mix.shell().info("Step 3: Fixed #{base_count} instrument base names\n")
    end

    if dry_run do
      preview_comma_aliases()
      preview_primary_flags()
      preview_base_names()
    end

    if variants do
      Mix.shell().info("\n=== Collecting variant aliases ===\n")

      unless dry_run do
        pos_count = collect_position_variants()
        Mix.shell().info("Step 3a: Added #{pos_count} aliases from positions\n")

        sold_count = collect_sold_position_variants()
        Mix.shell().info("Step 3b: Added #{sold_count} aliases from sold_positions\n")

        trade_count = collect_trade_variants()
        Mix.shell().info("Step 3c: Added #{trade_count} aliases from trades\n")
      end

      if dry_run do
        preview_variants()
      end
    end

    # Summary
    total_aliases = Repo.one(from(a in InstrumentAlias, select: count()))

    primary_aliases =
      Repo.one(from(a in InstrumentAlias, where: a.is_primary == true, select: count()))

    comma_aliases =
      Repo.one(
        from(a in InstrumentAlias,
          where: like(a.symbol, "%,%") and fragment("length(?)", a.symbol) <= 30,
          select: count()
        )
      )

    Mix.shell().info("\n=== Summary ===")
    Mix.shell().info("Total aliases: #{total_aliases}")
    Mix.shell().info("Primary aliases: #{primary_aliases}")
    Mix.shell().info("Comma-separated aliases remaining: #{comma_aliases}")
  end

  # --- Step 2a: Split comma-separated aliases ---

  @doc false
  def split_comma_aliases do
    # Only split short aliases — long ones with commas are company names (e.g., "GROUP, LLC")
    comma_aliases =
      Repo.all(
        from(a in InstrumentAlias,
          where: like(a.symbol, "%,%") and fragment("length(?)", a.symbol) <= 30,
          select: %{
            id: a.id,
            instrument_id: a.instrument_id,
            symbol: a.symbol,
            exchange: a.exchange,
            source: a.source
          }
        )
      )

    Enum.reduce(comma_aliases, 0, fn alias_record, count ->
      symbols =
        alias_record.symbol
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      case symbols do
        [first | rest] ->
          update_or_delete_original(alias_record, first)
          count + insert_split_symbols(rest, alias_record)

        [] ->
          count
      end
    end)
  end

  defp update_or_delete_original(alias_record, first_symbol) do
    first_exists =
      InstrumentAlias
      |> where([a], a.instrument_id == ^alias_record.instrument_id and a.symbol == ^first_symbol)
      |> where([a], a.id != ^alias_record.id)
      |> where_exchange(alias_record.exchange)
      |> Repo.exists?()

    if first_exists do
      InstrumentAlias |> where([a], a.id == ^alias_record.id) |> Repo.delete_all()
    else
      InstrumentAlias
      |> where([a], a.id == ^alias_record.id)
      |> Repo.update_all(set: [symbol: first_symbol, updated_at: DateTime.utc_now()])
    end
  end

  defp insert_split_symbols(symbols, alias_record) do
    Enum.reduce(symbols, 0, fn symbol, acc ->
      attrs = %{
        instrument_id: alias_record.instrument_id,
        symbol: symbol,
        exchange: alias_record.exchange,
        source: alias_record.source
      }

      existing =
        InstrumentAlias
        |> where([a], a.instrument_id == ^attrs.instrument_id and a.symbol == ^attrs.symbol)
        |> where_exchange(attrs.exchange)
        |> Repo.one()

      if existing, do: acc, else: insert_alias!(attrs, acc)
    end)
  end

  defp insert_alias!(attrs, acc) do
    %InstrumentAlias{} |> InstrumentAlias.changeset(attrs) |> Repo.insert!()
    acc + 1
  end

  # --- Step 2b: Set is_primary flags ---

  @doc false
  def set_primary_flags do
    # Reset all to false first
    InstrumentAlias
    |> where([a], a.is_primary == true)
    |> Repo.update_all(set: [is_primary: false, updated_at: DateTime.utc_now()])

    # Get all instruments that have aliases
    instrument_ids =
      Repo.all(
        from(a in InstrumentAlias,
          distinct: true,
          select: a.instrument_id
        )
      )

    Enum.reduce(instrument_ids, 0, fn instrument_id, count ->
      aliases =
        Repo.all(
          from(a in InstrumentAlias,
            where: a.instrument_id == ^instrument_id,
            select: %{id: a.id, symbol: a.symbol, source: a.source, inserted_at: a.inserted_at}
          )
        )

      case pick_primary(aliases) do
        nil ->
          count

        primary ->
          InstrumentAlias
          |> where([a], a.id == ^primary.id)
          |> Repo.update_all(set: [is_primary: true, updated_at: DateTime.utc_now()])

          count + 1
      end
    end)
  end

  defp pick_primary(aliases) do
    # Priority: finnhub > symbol_mapping > ibkr matching instrument.symbol > most recent
    finnhub = Enum.find(aliases, &(&1.source == "finnhub"))
    symbol_mapping = Enum.find(aliases, &(&1.source == "symbol_mapping"))

    ibkr =
      Enum.find(aliases, fn a ->
        a.source != nil and String.starts_with?(a.source, "ibkr")
      end)

    cond do
      finnhub -> finnhub
      symbol_mapping -> symbol_mapping
      ibkr -> ibkr
      true -> Enum.max_by(aliases, & &1.inserted_at, NaiveDateTime)
    end
  end

  # --- Step 2c: Fix instruments.symbol to base names ---

  @doc false
  def fix_base_names do
    instruments =
      Repo.all(
        from(i in Instrument,
          where: not is_nil(i.symbol),
          select: %{id: i.id, symbol: i.symbol}
        )
      )

    Enum.reduce(instruments, 0, fn instrument, count ->
      new_symbol = resolve_base_name(instrument)

      if new_symbol != instrument.symbol do
        Instrument
        |> where([i], i.id == ^instrument.id)
        |> Repo.update_all(set: [symbol: new_symbol, updated_at: DateTime.utc_now()])

        count + 1
      else
        count
      end
    end)
  end

  defp resolve_base_name(instrument) do
    # Check override map first
    case Map.get(@base_name_overrides, instrument.symbol) do
      nil ->
        # If symbol looks like a broker code, try to find a better alias
        if broker_code?(instrument.symbol) do
          find_better_alias(instrument.id) || instrument.symbol
        else
          instrument.symbol
        end

      override ->
        override
    end
  end

  defp where_exchange(query, nil), do: where(query, [a], is_nil(a.exchange))
  defp where_exchange(query, exchange), do: where(query, [a], a.exchange == ^exchange)

  defp broker_code?(symbol) do
    # Only match short IBKR Nordic-style broker codes: TELIA1, OUT1V, NDA1V
    # Excludes: company names, exchange tickers (.T, .UN), preferred shares (PR*)
    byte_size(symbol) <= 12 and String.match?(symbol, ~r/^[A-Z]+\d+[A-Z]?$/)
  end

  defp find_better_alias(instrument_id) do
    # Look for a finnhub or symbol_mapping alias
    Repo.one(
      from(a in InstrumentAlias,
        where: a.instrument_id == ^instrument_id,
        where: a.source in ["finnhub", "symbol_mapping"],
        order_by: [
          asc: fragment("CASE WHEN ? = 'finnhub' THEN 0 ELSE 1 END", a.source),
          desc: a.inserted_at
        ],
        select: a.symbol,
        limit: 1
      )
    )
  end

  # --- Step 3a: Collect variants from positions ---

  @doc false
  def collect_position_variants do
    # Positions have symbol + isin. Match isin → instrument, collect symbols.
    position_symbols =
      Repo.all(
        from(p in "positions",
          join: i in Instrument,
          on: p.isin == i.isin,
          where: not is_nil(p.symbol) and not is_nil(p.isin),
          group_by: [i.id, p.symbol],
          select: {i.id, p.symbol}
        )
      )

    insert_variant_aliases(position_symbols, "ibkr_position")
  end

  # --- Step 3b: Collect variants from sold_positions ---

  @doc false
  def collect_sold_position_variants do
    sold_symbols =
      Repo.all(
        from(sp in "sold_positions",
          join: i in Instrument,
          on: sp.isin == i.isin,
          where: not is_nil(sp.symbol) and not is_nil(sp.isin),
          group_by: [i.id, sp.symbol],
          select: {i.id, type(sp.symbol, :string)}
        )
      )

    insert_variant_aliases(sold_symbols, "sold_position")
  end

  # --- Step 3c: Collect variants from trades ---

  @doc false
  def collect_trade_variants do
    # Trades have instrument_id + raw_data with symbol in different positions:
    # "Order" rows: [Order, asset, currency, account, SYMBOL, datetime, ...]
    # "Trade" rows: [Trade, asset, currency, SYMBOL, datetime, exchange, ...]
    # Legacy rows: %{"broker" => ..., "legacy_id" => ...} — no symbol
    trades =
      Repo.all(
        from(t in Trade,
          where: not is_nil(t.raw_data),
          select: {t.instrument_id, t.raw_data}
        )
      )

    symbol_pairs =
      trades
      |> Enum.map(fn {instrument_id, raw_data} ->
        {instrument_id, extract_trade_symbol(raw_data)}
      end)
      |> Enum.filter(fn {_id, symbol} -> is_binary(symbol) and symbol != "" end)
      |> Enum.uniq()

    insert_variant_aliases(symbol_pairs, "ibkr_trade")
  end

  defp extract_trade_symbol(%{"row" => ["Order", _, _, _, sym | _]}) when is_binary(sym), do: sym
  defp extract_trade_symbol(%{"row" => ["Trade", _, _, sym | _]}) when is_binary(sym), do: sym
  defp extract_trade_symbol(_), do: nil

  defp insert_variant_aliases(pairs, source) do
    Enum.reduce(pairs, 0, fn {instrument_id, symbol}, count ->
      if alias_exists?(instrument_id, symbol) do
        count
      else
        insert_variant(instrument_id, symbol, source, count)
      end
    end)
  end

  defp alias_exists?(instrument_id, symbol) do
    Repo.exists?(
      from(a in InstrumentAlias,
        where: a.instrument_id == ^instrument_id and a.symbol == ^symbol
      )
    )
  end

  defp insert_variant(instrument_id, symbol, source, count) do
    attrs = %{instrument_id: instrument_id, symbol: symbol, source: source}

    case %InstrumentAlias{} |> InstrumentAlias.changeset(attrs) |> Repo.insert() do
      {:ok, _} -> count + 1
      {:error, _} -> count
    end
  end

  # --- Preview functions for dry run ---

  defp preview_comma_aliases do
    comma_aliases =
      Repo.all(
        from(a in InstrumentAlias,
          where: like(a.symbol, "%,%"),
          select: %{symbol: a.symbol, source: a.source}
        )
      )

    Mix.shell().info("Step 1: #{length(comma_aliases)} comma-separated aliases to split:")

    Enum.each(comma_aliases, fn a ->
      Mix.shell().info("  #{a.symbol} (#{a.source})")
    end)

    Mix.shell().info("")
  end

  defp preview_primary_flags do
    instruments_with_aliases =
      Repo.one(
        from(a in InstrumentAlias,
          select: count(a.instrument_id, :distinct)
        )
      )

    current_primary =
      Repo.one(from(a in InstrumentAlias, where: a.is_primary == true, select: count()))

    Mix.shell().info(
      "Step 2: #{instruments_with_aliases} instruments with aliases, #{current_primary} currently have primary"
    )

    Mix.shell().info("")
  end

  defp preview_base_names do
    overrides_found =
      Repo.all(
        from(i in Instrument,
          where: i.symbol in ^Map.keys(@base_name_overrides),
          select: %{symbol: i.symbol, name: i.name}
        )
      )

    broker_codes =
      Repo.all(
        from(i in Instrument,
          where:
            not is_nil(i.symbol) and
              (like(i.symbol, "% %") or like(i.symbol, "%.%")),
          select: %{symbol: i.symbol, name: i.name}
        )
      )

    Mix.shell().info("Step 3: #{length(overrides_found)} symbols match override map:")

    Enum.each(overrides_found, fn i ->
      new = Map.get(@base_name_overrides, i.symbol)
      Mix.shell().info("  #{i.symbol} → #{new} (#{i.name})")
    end)

    remaining_broker =
      Enum.reject(broker_codes, fn i -> Map.has_key?(@base_name_overrides, i.symbol) end)

    if remaining_broker != [] do
      Mix.shell().info("\n  #{length(remaining_broker)} broker codes not in override map:")

      Enum.each(remaining_broker, fn i ->
        Mix.shell().info("  #{i.symbol} (#{i.name})")
      end)
    end

    Mix.shell().info("")
  end

  defp preview_variants do
    pos_count =
      Repo.one(
        from(p in "positions",
          join: i in Instrument,
          on: p.isin == i.isin,
          where: not is_nil(p.symbol) and not is_nil(p.isin),
          select: count(fragment("DISTINCT (?, ?)", i.id, p.symbol))
        )
      )

    sold_count =
      Repo.one(
        from(sp in "sold_positions",
          join: i in Instrument,
          on: sp.isin == i.isin,
          where: not is_nil(sp.symbol) and not is_nil(sp.isin),
          select: count(fragment("DISTINCT (?, ?)", i.id, sp.symbol))
        )
      )

    Mix.shell().info("Variants: #{pos_count} position pairs, #{sold_count} sold_position pairs")
  end
end
