defmodule Mix.Tasks.Fix.PositionSymbols do
  @moduledoc """
  Normalize position and sold_position symbols to match instrument canonical symbols.

  Sub-tasks:
  1. Remap stale ISINs in positions (old CUSIP→new CUSIP)
  2. Normalize position symbols via ISIN→instrument join
  3. Normalize sold_position symbols via ISIN→instrument join
  4. Fix specific position symbols without instrument match
  5. Fix instrument currencies
  6. Fill missing instrument listing_exchange

  ## Usage

      mix fix.position_symbols             # Run all fixes
      mix fix.position_symbols --dry-run   # Preview without changes
  """

  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.Instrument
  alias Dividendsomatic.Repo

  require Logger

  @shortdoc "Normalize position & sold_position symbols to match instruments"

  # Old ISIN → new ISIN (same company, CUSIP changed)
  @isin_remappings %{
    "US0030281010" => "US0030111035",
    "US09260D1081" => "US09258G1040",
    "US1264081035" => "US22948Q1013",
    "US26982Y1091" => "US2698081013",
    "CA31660A1049" => "CA31660A1030",
    "US38147U1016" => "US38147U1079",
    "US4271143047" => "US4270965084",
    "US86885M1053" => "US86887Q1094",
    "US9030821043" => "US9030021037",
    "US92838Y1029" => "US92838Y1001",
    "US98400U1016" => "US98400T1060",
    "US8955731080" => "US8954361031",
    "US65253E1010" => "US6525262035"
  }

  # Positions with ISINs not in instruments table — manual symbol fixes
  @manual_symbol_fixes %{
    "US87943P1030" => "TDS-A",
    "US87943P2020" => "TDS",
    "US78590A2079" => "SACH"
  }

  # Instrument currency corrections
  @currency_fixes %{
    "CY0200352116" => "NOK",
    "BMG9156K1018" => "NOK"
  }

  # Missing listing_exchange fills (keyed by ISIN or legacy identifier_key)
  @exchange_fixes %{
    "US26923G1031" => "AMEX",
    "US1514611003" => "NYSE",
    "FI0009002471" => "HEX",
    "US3453708600" => "NYSE",
    "LEGACY:FROo" => "OSE",
    "US90273A2078" => "NYSE",
    "US90269A3023" => "NYSE",
    "FI0009902530" => "HEX",
    "US6740012017" => "NYSE",
    "US90267B7652" => "NYSE",
    "LEGACY:GLAD.OLD" => "NASDAQ",
    "LEGACY:2A41" => "FWB",
    "LEGACY:BCIC" => "NASDAQ",
    "LEGACY:FOT" => "FWB"
  }

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Logger.configure(level: :info)

    {opts, _, _} = OptionParser.parse(args, switches: [dry_run: :boolean])
    dry_run = opts[:dry_run] || false

    if dry_run, do: Mix.shell().info("=== DRY RUN — no changes will be made ===\n")

    Mix.shell().info("=== Fixing position symbols ===\n")

    isin_count = remap_stale_isins(dry_run)
    Mix.shell().info("Step 1: Remapped #{isin_count} position ISINs (#{map_size(@isin_remappings)} old→new pairs)")

    pos_count = normalize_position_symbols(dry_run)
    Mix.shell().info("Step 2: Normalized #{pos_count} position symbols via instrument lookup")

    sold_count = normalize_sold_position_symbols(dry_run)
    Mix.shell().info("Step 3: Normalized #{sold_count} sold_position symbols")

    manual_count = fix_manual_symbols(dry_run)
    Mix.shell().info("Step 4: Fixed #{manual_count} specific position symbols (TDS, SACH)")

    currency_count = fix_instrument_currencies(dry_run)
    Mix.shell().info("Step 5: Fixed #{currency_count} instrument currencies")

    exchange_count = fill_listing_exchanges(dry_run)
    Mix.shell().info("Step 6: Filled #{exchange_count} instrument listing_exchanges")

    # Summary
    print_summary()
  end

  # Step 1: Remap stale ISINs
  defp remap_stale_isins(dry_run) do
    Enum.reduce(@isin_remappings, 0, fn {old_isin, new_isin}, total ->
      count =
        if dry_run do
          Repo.one(
            from(p in "positions",
              where: p.isin == ^old_isin,
              select: count()
            )
          )
        else
          {count, _} =
            from(p in "positions", where: p.isin == ^old_isin)
            |> Repo.update_all(set: [isin: new_isin])

          count
        end

      if count > 0 do
        Mix.shell().info("  #{old_isin} → #{new_isin}: #{count} positions")
      end

      total + count
    end)
  end

  # Step 2: Normalize position symbols via ISIN→instrument join
  defp normalize_position_symbols(dry_run) do
    if dry_run do
      Repo.one(
        from(p in "positions",
          join: i in Instrument,
          on: p.isin == i.isin,
          where: p.symbol != i.symbol and not is_nil(i.symbol),
          select: count()
        )
      )
    else
      {count, _} =
        Repo.query!("""
        UPDATE positions p
        SET symbol = i.symbol
        FROM instruments i
        WHERE p.isin = i.isin
          AND p.symbol != i.symbol
          AND i.symbol IS NOT NULL
        """)
        |> then(fn %{num_rows: n} -> {n, nil} end)

      count
    end
  end

  # Step 3: Normalize sold_position symbols via ISIN→instrument join
  defp normalize_sold_position_symbols(dry_run) do
    if dry_run do
      Repo.one(
        from(sp in "sold_positions",
          join: i in Instrument,
          on: sp.isin == i.isin,
          where: sp.symbol != i.symbol and not is_nil(i.symbol) and not is_nil(sp.isin),
          select: count()
        )
      )
    else
      %{num_rows: count} =
        Repo.query!("""
        UPDATE sold_positions sp
        SET symbol = i.symbol
        FROM instruments i
        WHERE sp.isin = i.isin
          AND sp.symbol != i.symbol
          AND i.symbol IS NOT NULL
        """)

      count
    end
  end

  # Step 4: Fix specific position symbols without instrument match
  defp fix_manual_symbols(dry_run) do
    Enum.reduce(@manual_symbol_fixes, 0, fn {isin, symbol}, total ->
      count =
        if dry_run do
          Repo.one(
            from(p in "positions",
              where: p.isin == ^isin and p.symbol != ^symbol,
              select: count()
            )
          )
        else
          {count, _} =
            from(p in "positions", where: p.isin == ^isin and p.symbol != ^symbol)
            |> Repo.update_all(set: [symbol: symbol])

          count
        end

      if count > 0 do
        Mix.shell().info("  #{isin} → #{symbol}: #{count} positions")
      end

      total + count
    end)
  end

  # Step 5: Fix instrument currencies
  defp fix_instrument_currencies(dry_run) do
    Enum.reduce(@currency_fixes, 0, fn {isin, currency}, total ->
      count =
        if dry_run do
          Repo.one(
            from(i in Instrument,
              where: i.isin == ^isin and i.currency != ^currency,
              select: count()
            )
          )
        else
          {count, _} =
            from(i in Instrument, where: i.isin == ^isin and i.currency != ^currency)
            |> Repo.update_all(set: [currency: currency, updated_at: DateTime.utc_now()])

          count
        end

      if count > 0 do
        instrument =
          Repo.one(from(i in Instrument, where: i.isin == ^isin, select: {i.symbol, i.currency}))

        {sym, curr} = instrument || {"?", "?"}
        Mix.shell().info("  #{sym} (#{isin}): #{curr} → #{currency}")
      end

      total + count
    end)
  end

  # Step 6: Fill missing listing_exchange
  defp fill_listing_exchanges(dry_run) do
    {isin_fixes, legacy_fixes} =
      Enum.split_with(@exchange_fixes, fn {key, _} -> not String.starts_with?(key, "LEGACY:") end)

    isin_count =
      Enum.reduce(isin_fixes, 0, fn {isin, exchange}, total ->
        count =
          if dry_run do
            Repo.one(
              from(i in Instrument,
                where: i.isin == ^isin and is_nil(i.listing_exchange),
                select: count()
              )
            )
          else
            {count, _} =
              from(i in Instrument, where: i.isin == ^isin and is_nil(i.listing_exchange))
              |> Repo.update_all(
                set: [listing_exchange: exchange, updated_at: DateTime.utc_now()]
              )

            count
          end

        if count > 0 do
          sym =
            Repo.one(from(i in Instrument, where: i.isin == ^isin, select: i.symbol)) || "?"

          Mix.shell().info("  #{sym} (#{isin}) → #{exchange}")
        end

        total + count
      end)

    legacy_count =
      Enum.reduce(legacy_fixes, 0, fn {"LEGACY:" <> identifier, exchange}, total ->
        # Legacy instruments use identifier_key like "symbol:exchange" or just the symbol
        identifier_key = "LEGACY:#{identifier}"

        count =
          if dry_run do
            Repo.one(
              from(i in Instrument,
                where:
                  fragment("? LIKE ?", i.isin, ^identifier_key) and
                    is_nil(i.listing_exchange),
                select: count()
              )
            )
          else
            {count, _} =
              from(i in Instrument,
                where:
                  fragment("? LIKE ?", i.isin, ^identifier_key) and
                    is_nil(i.listing_exchange)
              )
              |> Repo.update_all(
                set: [listing_exchange: exchange, updated_at: DateTime.utc_now()]
              )

            count
          end

        if count > 0 do
          Mix.shell().info("  #{identifier_key} → #{exchange}")
        end

        total + count
      end)

    isin_count + legacy_count
  end

  defp print_summary do
    total_positions = Repo.one(from(p in "positions", select: count()))

    # Positions matching an instrument symbol
    clean_positions =
      Repo.one(
        from(p in "positions",
          join: i in Instrument,
          on: p.isin == i.isin and p.symbol == i.symbol,
          select: count()
        )
      )

    total_sold = Repo.one(from(sp in "sold_positions", select: count()))

    clean_sold =
      Repo.one(
        from(sp in "sold_positions",
          join: i in Instrument,
          on: sp.isin == i.isin and sp.symbol == i.symbol,
          select: count()
        )
      )

    missing_exchange =
      Repo.one(
        from(i in Instrument,
          where: is_nil(i.listing_exchange),
          select: count()
        )
      )

    Mix.shell().info("\n=== Summary ===")

    Mix.shell().info(
      "Positions with clean symbols: #{format_number(clean_positions)} / #{format_number(total_positions)}"
    )

    Mix.shell().info(
      "Sold positions with clean symbols: #{format_number(clean_sold)} / #{format_number(total_sold)}"
    )

    Mix.shell().info("Instruments missing listing_exchange: #{missing_exchange}")
  end

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
