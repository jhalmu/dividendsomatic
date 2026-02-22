defmodule Mix.Tasks.Dedup.CashFlows do
  @moduledoc """
  Remove duplicate cash_flow records from overlapping Activity Statement imports.

  Two-pass dedup:
  1. Exact match: (flow_type, currency, date, amount)
  2. Description match: (flow_type, currency, date, description) — catches variant
     amounts from different FX conversions across imports

  ## Usage

      mix dedup.cash_flows              # Dry-run (show what would be deleted)
      mix dedup.cash_flows --execute    # Actually delete duplicates
  """
  use Mix.Task

  alias Dividendsomatic.Repo

  @shortdoc "Deduplicate cash_flow records"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    execute? = "--execute" in args

    if execute? do
      Mix.shell().info("=== Dedup Cash Flows (EXECUTE mode) ===\n")
    else
      Mix.shell().info("=== Dedup Cash Flows (DRY RUN) ===\n")
    end

    # Pass 1: Exact amount duplicates
    ids_pass1 = find_exact_dupes()
    Mix.shell().info("Pass 1 (exact amount match): #{length(ids_pass1)} duplicates")

    # Pass 2: Description-based duplicates (catches variant amounts from different imports)
    ids_pass2 = find_description_dupes(ids_pass1)
    Mix.shell().info("Pass 2 (description match):  #{length(ids_pass2)} additional duplicates")

    all_ids = ids_pass1 ++ ids_pass2
    Mix.shell().info("\nTotal: #{length(all_ids)} records to delete\n")

    # Show summary by type
    show_summary(all_ids)

    if execute? and all_ids != [] do
      deleted =
        all_ids
        |> Enum.chunk_every(100)
        |> Enum.reduce(0, fn batch, acc ->
          %{num_rows: count} =
            Repo.query!("DELETE FROM cash_flows WHERE id = ANY($1)", [batch])

          acc + count
        end)

      Mix.shell().info("\nDeleted #{deleted} duplicate records.")

      # Show post-dedup counts
      show_post_dedup_counts()
    else
      if all_ids != [] do
        Mix.shell().info("\nRun with --execute to delete duplicates.")
      end
    end
  end

  defp find_exact_dupes do
    %{rows: groups} =
      Repo.query!("""
      SELECT array_agg(id ORDER BY inserted_at)
      FROM cash_flows
      GROUP BY flow_type, currency, date, amount
      HAVING COUNT(*) > 1
      """)

    groups
    |> Enum.flat_map(fn [ids] -> Enum.drop(ids, 1) end)
  end

  defp find_description_dupes(already_removing) do
    exclude_set = MapSet.new(already_removing)

    # Find groups by (flow_type, description, currency, date) that still have >1
    # after pass 1 removals
    %{rows: groups} =
      Repo.query!("""
      SELECT array_agg(id ORDER BY inserted_at)
      FROM cash_flows
      GROUP BY flow_type, description, currency, date
      HAVING COUNT(*) > 1
      """)

    groups
    |> Enum.flat_map(fn [ids] ->
      # Remove IDs already flagged in pass 1
      remaining = Enum.reject(ids, &MapSet.member?(exclude_set, &1))

      # Keep the first remaining, delete the rest
      case remaining do
        [_ | rest] -> rest
        _ -> []
      end
    end)
  end

  defp show_summary(ids_to_delete) do
    if ids_to_delete != [] do
      %{rows: rows} =
        Repo.query!(
          """
          SELECT flow_type, COUNT(*), SUM(ABS(COALESCE(amount_eur, amount)))
          FROM cash_flows
          WHERE id = ANY($1)
          GROUP BY flow_type
          ORDER BY flow_type
          """,
          [ids_to_delete]
        )

      for [ft, cnt, total] <- rows do
        Mix.shell().info(
          "  #{ft}: #{cnt} records (€#{Decimal.round(Decimal.new(to_string(total)), 2)})"
        )
      end
    end
  end

  defp show_post_dedup_counts do
    Mix.shell().info("\n=== Post-dedup counts ===")

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
