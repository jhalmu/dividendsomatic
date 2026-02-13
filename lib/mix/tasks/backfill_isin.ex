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

  # Static map for tickers not resolvable from holdings or dividend rows.
  # Verified ISINs for well-known stocks.
  @static_isin_map %{
    "AIO" => "US92838Y1029",
    "AQN" => "CA0158571053",
    "ARR" => "US0423155078",
    "AXL" => "US0240611030",
    "BABA" => "US01609W1027",
    "BIIB" => "US09062X1037",
    "BST" => "US09260D1081",
    "CCJ" => "CA13321L1085",
    "CGBD" => "US14316A1088",
    "CHCT" => "US20369C1062",
    "CTO" => "US1264081035",
    "DFN" => "CA25490A1084",
    "DHT" => "MHY2065G1219",
    "ECC" => "US26982Y1091",
    "ENB" => "CA29250N1050",
    "ET" => "US29273V1008",
    "FCX" => "US35671D8570",
    "FSZ" => "CA31660A1049",
    "GILD" => "US3755581036",
    "GNK" => "MHY2685T1313",
    "GOLD" => "CA0679011084",
    "GSBD" => "US38147U1016",
    "HTGC" => "US4271143047",
    "HYT" => "US09255P1075",
    "IAF" => "US0030281010",
    "KMF" => "US48661E1082",
    "NAT" => "BMG657731060",
    "NEWT" => "US65253E1010",
    "OCCI" => "US67111Q1076",
    "OCSL" => "US67401P1084",
    "OMF" => "US68268W1036",
    "ORA" => "FR0000133308",
    "ORCC" => "US69121K1043",
    "OXY" => "US6745991058",
    "PBR" => "US71654V4086",
    "PRA" => "US74267C1062",
    "REI.UN" => "CA7669101031",
    "RNP" => "US19247X1000",
    "SACH PRA" => "US78590A2079",
    "SBRA" => "US78573L1061",
    "SBSW" => "US82575P1075",
    "SCCO" => "US84265V1052",
    "SSSS" => "US86885M1053",
    "TDS PRU" => "US87943P1030",
    "TDS PRV" => "US87943P2020",
    "TEF" => "US8793822086",
    "TELL" => "US87968A1043",
    "TY" => "US8955731080",
    "UMH" => "US9030821043",
    "UUUU" => "CA2926717083",
    "WF" => "US98105F1049",
    "XFLT" => "US98400U1016",
    "ZM" => "US98980L1017",
    "ZTR" => "US92837G1004"
  }

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
      @static_isin_map
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
    IO.puts("  Static map pairs: #{map_size(@static_isin_map)}")
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

        if count > 0 do
          if dry_run? do
            IO.puts("  Would update #{count} transactions: #{ticker} → #{isin}")
          else
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
        end

        acc + count
      end)

    IO.puts(
      "\n  Total: #{total_updated} broker_transactions #{if dry_run?, do: "would be", else: ""} updated\n"
    )
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

        if count > 0 do
          if dry_run? do
            IO.puts("  Would update #{count} sold_positions: #{ticker} → #{isin}")
          else
            {updated, _} =
              SoldPosition
              |> where([s], s.symbol == ^ticker and is_nil(s.isin))
              |> Repo.update_all(set: [isin: isin])

            if updated > 0, do: IO.puts("  Updated #{updated}: #{ticker} → #{isin}")
          end
        end

        acc + count
      end)

    IO.puts(
      "\n  Total: #{total_updated} sold_positions #{if dry_run?, do: "would be", else: ""} updated\n"
    )
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
