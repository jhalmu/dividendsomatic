defmodule Mix.Tasks.Backfill.Isin do
  @moduledoc """
  Backfills ISIN on broker_transactions and sold_positions.

  IBKR trade rows don't include ISIN, leaving 3,793 buy/sell transactions
  with isin = nil. This task resolves ISINs from three sources:

  1. Holdings table (Flex reports carry ISIN per symbol)
  2. Dividend/tax broker_transactions (these rows carry ISIN)
  3. Static map of well-known tickers

  After ISIN backfill, also computes identifier_key on all sold_positions.

  Usage:
    mix backfill.isin              # Run full backfill
    mix backfill.isin --dry-run    # Preview without writing
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{BrokerTransaction, Holding, SoldPosition}
  alias Dividendsomatic.Repo

  @shortdoc "Backfill ISIN on broker_transactions and sold_positions"

  alias Dividendsomatic.Portfolio.IsinMap

  def run(args) do
    Mix.Task.run("app.start")

    dry_run? = "--dry-run" in args

    if dry_run?, do: IO.puts("=== DRY RUN — no changes will be written ===\n")

    # Phase 1: Diagnostic
    phase_1_diagnostic()

    # Phase 2: Build ticker→ISIN mapping
    mapping = phase_2_build_mapping()

    # Phase 3: Update broker_transactions
    phase_3_update_broker_transactions(mapping, dry_run?)

    # Phase 4: Update sold_positions
    phase_4_update_sold_positions(mapping, dry_run?)

    # Phase 5: Backfill identifier_key on sold_positions
    phase_5_backfill_identifier_key(dry_run?)

    # Phase 6: Final report
    phase_6_report()
  end

  # --- Phase 1: Diagnostic ---

  defp phase_1_diagnostic do
    IO.puts("--- Phase 1: Diagnostic ---\n")

    nil_isin_count =
      BrokerTransaction
      |> where(
        [t],
        t.broker == "ibkr" and t.transaction_type in ["buy", "sell"] and is_nil(t.isin)
      )
      |> Repo.aggregate(:count)

    distinct_tickers =
      BrokerTransaction
      |> where(
        [t],
        t.broker == "ibkr" and t.transaction_type in ["buy", "sell"] and is_nil(t.isin)
      )
      |> select([t], fragment("DISTINCT ?->>?", t.raw_data, "symbol"))
      |> Repo.all()

    sold_nil_isin =
      SoldPosition
      |> where([s], is_nil(s.isin))
      |> Repo.aggregate(:count)

    IO.puts("  IBKR buy/sell with isin=nil: #{nil_isin_count}")
    IO.puts("  Distinct tickers: #{length(distinct_tickers)}")
    IO.puts("  Sold positions with isin=nil: #{sold_nil_isin}\n")
  end

  # --- Phase 2: Build mapping ---

  defp phase_2_build_mapping do
    IO.puts("--- Phase 2: Build ticker→ISIN mapping ---\n")

    # Source 1: Holdings table (Flex reports)
    holdings_map =
      Holding
      |> where([h], not is_nil(h.isin) and h.isin > "")
      |> distinct([h], [h.symbol])
      |> select([h], {h.symbol, h.isin})
      |> Repo.all()
      |> Map.new()

    # Source 2: Dividend/tax broker_transactions
    div_map =
      BrokerTransaction
      |> where(
        [t],
        t.broker == "ibkr" and
          t.transaction_type in ["dividend", "withholding_tax"] and
          not is_nil(t.isin)
      )
      |> select([t], {fragment("?->>?", t.raw_data, "symbol"), t.isin})
      |> distinct([t], [fragment("?->>?", t.raw_data, "symbol")])
      |> Repo.all()
      |> Map.new()

    # Merge: holdings takes priority over dividends, static map fills the rest
    merged =
      IsinMap.static_map()
      |> Map.merge(div_map)
      |> Map.merge(holdings_map)

    # Count coverage
    all_tickers =
      BrokerTransaction
      |> where(
        [t],
        t.broker == "ibkr" and t.transaction_type in ["buy", "sell"] and is_nil(t.isin)
      )
      |> select([t], fragment("DISTINCT ?->>?", t.raw_data, "symbol"))
      |> Repo.all()
      |> MapSet.new()

    resolved = Enum.count(all_tickers, &Map.has_key?(merged, &1))
    unresolved = MapSet.difference(all_tickers, MapSet.new(Map.keys(merged)))

    IO.puts("  Holdings pairs: #{map_size(holdings_map)}")
    IO.puts("  Dividend pairs: #{map_size(div_map)}")
    IO.puts("  Static map pairs: #{map_size(IsinMap.static_map())}")
    IO.puts("  Merged total: #{map_size(merged)}")
    IO.puts("  Coverage: #{resolved}/#{MapSet.size(all_tickers)} tickers")

    if MapSet.size(unresolved) > 0 do
      IO.puts("\n  Unresolved tickers (#{MapSet.size(unresolved)}):")

      unresolved
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.each(&IO.puts("    - #{&1}"))
    end

    IO.puts("")
    merged
  end

  # --- Phase 3: Update broker_transactions ---

  defp phase_3_update_broker_transactions(mapping, dry_run?) do
    IO.puts("--- Phase 3: Update broker_transactions ---\n")

    total_updated =
      mapping
      |> Enum.reduce(0, fn {ticker, isin}, acc ->
        count =
          BrokerTransaction
          |> where(
            [t],
            t.broker == "ibkr" and
              is_nil(t.isin) and
              fragment("?->>? = ?", t.raw_data, "symbol", ^ticker)
          )
          |> Repo.aggregate(:count)

        if count > 0, do: update_broker_transactions(ticker, isin, count, dry_run?)

        acc + count
      end)

    IO.puts(
      "\n  Total: #{total_updated} broker_transactions #{if dry_run?, do: "would be", else: ""} updated\n"
    )
  end

  defp update_broker_transactions(ticker, isin, count, true) do
    IO.puts("  Would update #{count} transactions: #{ticker} → #{isin}")
  end

  defp update_broker_transactions(ticker, isin, _count, false) do
    {updated, _} =
      BrokerTransaction
      |> where(
        [t],
        t.broker == "ibkr" and
          is_nil(t.isin) and
          fragment("?->>? = ?", t.raw_data, "symbol", ^ticker)
      )
      |> Repo.update_all(set: [isin: isin])

    if updated > 0, do: IO.puts("  Updated #{updated}: #{ticker} → #{isin}")
  end

  # --- Phase 4: Update sold_positions ---

  defp phase_4_update_sold_positions(mapping, dry_run?) do
    IO.puts("--- Phase 4: Update sold_positions ---\n")

    total_updated =
      mapping
      |> Enum.reduce(0, fn {ticker, isin}, acc ->
        count =
          SoldPosition
          |> where([s], s.symbol == ^ticker and is_nil(s.isin))
          |> Repo.aggregate(:count)

        if count > 0, do: update_sold_positions(ticker, isin, count, dry_run?)

        acc + count
      end)

    IO.puts(
      "\n  Total: #{total_updated} sold_positions #{if dry_run?, do: "would be", else: ""} updated\n"
    )
  end

  defp update_sold_positions(ticker, isin, count, true) do
    IO.puts("  Would update #{count} sold_positions: #{ticker} → #{isin}")
  end

  defp update_sold_positions(ticker, isin, _count, false) do
    {updated, _} =
      SoldPosition
      |> where([s], s.symbol == ^ticker and is_nil(s.isin))
      |> Repo.update_all(set: [isin: isin])

    if updated > 0, do: IO.puts("  Updated #{updated}: #{ticker} → #{isin}")
  end

  # --- Phase 5: Backfill identifier_key on all sold_positions ---

  defp phase_5_backfill_identifier_key(dry_run?) do
    IO.puts("--- Phase 5: Backfill identifier_key on sold_positions ---\n")

    # Update all sold_positions where identifier_key is empty/null
    # Set to ISIN if available, else "symbol:TICKER"
    if dry_run? do
      needs_key =
        SoldPosition
        |> where([s], is_nil(s.identifier_key) or s.identifier_key == "")
        |> Repo.aggregate(:count)

      IO.puts("  Would update identifier_key on #{needs_key} sold_positions\n")
    else
      # Set identifier_key = isin where isin is present
      %{num_rows: with_isin} =
        Repo.query!(
          """
          UPDATE sold_positions SET identifier_key = isin
          WHERE (identifier_key IS NULL OR identifier_key = '')
            AND isin IS NOT NULL AND isin != ''
          """,
          []
        )

      # Set identifier_key = 'symbol:' || symbol for the rest
      %{num_rows: with_symbol} =
        Repo.query!(
          """
          UPDATE sold_positions SET identifier_key = 'symbol:' || symbol
          WHERE (identifier_key IS NULL OR identifier_key = '')
            AND symbol IS NOT NULL
          """,
          []
        )

      IO.puts("  Set identifier_key from ISIN: #{with_isin}")
      IO.puts("  Set identifier_key from symbol: #{with_symbol}\n")
    end
  end

  # --- Phase 6: Final report ---

  defp phase_6_report do
    IO.puts("--- Final Report ---\n")

    remaining_txn =
      BrokerTransaction
      |> where(
        [t],
        t.broker == "ibkr" and t.transaction_type in ["buy", "sell"] and is_nil(t.isin)
      )
      |> Repo.aggregate(:count)

    remaining_sold =
      SoldPosition
      |> where([s], is_nil(s.isin))
      |> Repo.aggregate(:count)

    empty_key =
      SoldPosition
      |> where([s], is_nil(s.identifier_key) or s.identifier_key == "")
      |> Repo.aggregate(:count)

    IO.puts("  IBKR buy/sell with isin=nil: #{remaining_txn}")
    IO.puts("  Sold positions with isin=nil: #{remaining_sold}")
    IO.puts("  Sold positions with empty identifier_key: #{empty_key}")

    if remaining_txn == 0 and remaining_sold == 0 and empty_key == 0 do
      IO.puts("\n  ✓ All gaps filled!")
    else
      IO.puts("\n  Some gaps remain — check unresolved tickers above")
    end
  end
end
