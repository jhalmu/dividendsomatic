defmodule Mix.Tasks.Cleanup.CashFlows do
  @moduledoc """
  Clean up cash_flow records: remove Nordnet data and IBKR currency duplicates.

  Three passes:
  1. Nordnet removal: Finnish-language records from Nordnet broker
  2. Currency-duplicate removal: IBKR interest/fee recorded in both original
     currency AND EUR — keeps the EUR version
  3. Variant-description duplicates: "Debit Interest for Debit Interest" style
     entries that duplicate clean descriptions

  ## Usage

      mix cleanup.cash_flows              # Dry-run (show what would be deleted)
      mix cleanup.cash_flows --execute    # Actually delete records
  """
  use Mix.Task

  alias Dividendsomatic.Repo

  @shortdoc "Remove Nordnet data and currency duplicates from cash_flows"

  # Nordnet Finnish-language descriptions
  @nordnet_descriptions [
    "TALLETUS REAL-TIME",
    "TALLETUS",
    "NOSTO",
    "LAINAKORKO",
    "PÄÄOMIT YLIT.KORKO"
  ]

  # Nordnet migrated description patterns (LIKE match)
  @nordnet_patterns [
    "%nordnet%",
    "%legacy (nordnet)%"
  ]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    execute? = "--execute" in args

    mode = if execute?, do: "EXECUTE", else: "DRY RUN"
    Mix.shell().info("=== Cleanup Cash Flows (#{mode}) ===\n")

    show_pre_cleanup_counts()

    # Pass 1: Nordnet records
    nordnet_ids = find_nordnet_records()
    Mix.shell().info("\nPass 1 (Nordnet removal): #{length(nordnet_ids)} records")
    show_summary("  Nordnet", nordnet_ids)

    # Pass 2: Currency-duplicate interest/fee (non-EUR with matching EUR record)
    currency_dupe_ids = find_currency_duplicates()
    Mix.shell().info("\nPass 2 (currency duplicates): #{length(currency_dupe_ids)} records")
    show_summary("  Currency dupe", currency_dupe_ids)

    # Pass 3: Variant-description duplicates
    already = MapSet.new(nordnet_ids ++ currency_dupe_ids)
    variant_ids = find_variant_description_dupes(already)
    Mix.shell().info("\nPass 3 (variant descriptions): #{length(variant_ids)} records")
    show_summary("  Variant", variant_ids)

    all_ids = Enum.uniq(nordnet_ids ++ currency_dupe_ids ++ variant_ids)
    Mix.shell().info("\n--- Total: #{length(all_ids)} records to delete ---")
    show_summary("  Total", all_ids)

    if execute? and all_ids != [] do
      deleted = delete_records(all_ids)
      Mix.shell().info("\nDeleted #{deleted} records.")
      show_post_cleanup_counts()
    else
      if all_ids != [] do
        Mix.shell().info("\nRun with --execute to delete these records.")
      else
        Mix.shell().info("\nNothing to clean up.")
      end
    end
  end

  defp find_nordnet_records do
    # Exact description matches
    placeholders =
      @nordnet_descriptions
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {_, i} -> "$#{i}" end)

    %{rows: exact_rows} =
      Repo.query!(
        "SELECT id FROM cash_flows WHERE description IN (#{placeholders})",
        @nordnet_descriptions
      )

    exact_ids = Enum.map(exact_rows, fn [id] -> id end)

    # LIKE pattern matches
    like_ids =
      Enum.flat_map(@nordnet_patterns, fn pattern ->
        %{rows: rows} =
          Repo.query!("SELECT id FROM cash_flows WHERE description LIKE $1", [pattern])

        Enum.map(rows, fn [id] -> id end)
      end)

    Enum.uniq(exact_ids ++ like_ids)
  end

  defp find_currency_duplicates do
    # Find non-EUR interest/fee records that have a matching EUR record
    # on same (date, flow_type, description). The EUR version is more useful
    # for our EUR-based accounting.
    %{rows: rows} =
      Repo.query!("""
      SELECT a.id
      FROM cash_flows a
      JOIN cash_flows b ON a.date = b.date
        AND a.flow_type = b.flow_type
        AND a.description = b.description
        AND b.currency = 'EUR'
        AND a.currency != 'EUR'
        AND a.id != b.id
      WHERE a.flow_type IN ('interest', 'fee')
      """)

    Enum.map(rows, fn [id] -> id end)
  end

  defp find_variant_description_dupes(already_removing) do
    # Find "Debit Interest for Debit Interest" variants that duplicate
    # a clean "Debit Interest for Month-Year" record on the same date
    %{rows: rows} =
      Repo.query!("""
      SELECT a.id
      FROM cash_flows a
      WHERE a.flow_type = 'interest'
        AND a.description LIKE '%Debit Interest for Debit Interest%'
        AND EXISTS (
          SELECT 1 FROM cash_flows b
          WHERE b.date = a.date
            AND b.flow_type = a.flow_type
            AND b.currency = a.currency
            AND b.id != a.id
            AND b.description NOT LIKE '%Debit Interest for Debit Interest%'
            AND ABS(b.amount - a.amount) < 0.01
        )
      """)

    rows
    |> Enum.map(fn [id] -> id end)
    |> Enum.reject(&MapSet.member?(already_removing, &1))
  end

  defp delete_records(ids) do
    ids
    |> Enum.chunk_every(100)
    |> Enum.reduce(0, fn batch, acc ->
      %{num_rows: count} =
        Repo.query!("DELETE FROM cash_flows WHERE id = ANY($1)", [batch])

      acc + count
    end)
  end

  defp show_summary(_label, []), do: :ok

  defp show_summary(label, ids) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT flow_type, COUNT(*), SUM(ABS(COALESCE(amount_eur, amount)))
        FROM cash_flows
        WHERE id = ANY($1)
        GROUP BY flow_type
        ORDER BY flow_type
        """,
        [ids]
      )

    for [ft, cnt, total] <- rows do
      Mix.shell().info(
        "#{label} #{ft}: #{cnt} records (€#{Decimal.round(Decimal.new(to_string(total)), 2)})"
      )
    end
  end

  defp show_pre_cleanup_counts do
    Mix.shell().info("=== Current counts ===")

    %{rows: rows} =
      Repo.query!("""
      SELECT flow_type, COUNT(*), SUM(ABS(COALESCE(amount_eur, amount)))
      FROM cash_flows
      GROUP BY flow_type
      ORDER BY flow_type
      """)

    for [ft, cnt, total] <- rows do
      Mix.shell().info(
        "  #{ft}: #{cnt} records, €#{Decimal.round(Decimal.new(to_string(total)), 2)}"
      )
    end
  end

  defp show_post_cleanup_counts do
    Mix.shell().info("\n=== Post-cleanup counts ===")

    %{rows: rows} =
      Repo.query!("""
      SELECT flow_type, COUNT(*), SUM(ABS(COALESCE(amount_eur, amount)))
      FROM cash_flows
      GROUP BY flow_type
      ORDER BY flow_type
      """)

    for [ft, cnt, total] <- rows do
      Mix.shell().info(
        "  #{ft}: #{cnt} records, €#{Decimal.round(Decimal.new(to_string(total)), 2)}"
      )
    end
  end
end
