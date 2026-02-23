defmodule Mix.Tasks.Migrate.LegacyCosts do
  @shortdoc "Migrate legacy_costs interest/fees to cash_flows"
  @moduledoc """
  One-time migration of legacy_costs to cash_flows.

  - commission (3,266) → skip (already on trades as commission field)
  - foreign_tax/withholding_tax (1,174) → skip (already on dividend_payments)
  - loan_interest/capital_interest (158) → cash_flows as interest type

  ## Usage

      mix migrate.legacy_costs
      mix migrate.legacy_costs --dry-run
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.CashFlow
  alias Dividendsomatic.Repo

  @interest_types ~w(loan_interest capital_interest)
  @skip_types ~w(commission foreign_tax withholding_tax)

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    dry_run? = "--dry-run" in args
    label = if dry_run?, do: "DRY RUN: ", else: ""

    IO.puts("\n=== #{label}Legacy Costs Migration ===")

    print_skipped_counts()
    results = migrate_interest_records(dry_run?)

    IO.puts("\n--- Results ---")
    IO.puts("  Interest migrated: #{results.migrated}")
    IO.puts("  Skipped (dup):     #{results.skipped}")
    IO.puts("  Errors:            #{results.errors}")

    unless dry_run? do
      IO.puts("\nMigration complete. Safe to drop legacy_costs table.")
    end
  end

  defp print_skipped_counts do
    skip_counts =
      Repo.all(
        from(c in "legacy_costs",
          where: c.cost_type in ^@skip_types,
          group_by: c.cost_type,
          select: {c.cost_type, count()}
        )
      )

    Enum.each(skip_counts, fn {type, count} ->
      IO.puts("  Skip #{type}: #{count} (already on trades/dividend_payments)")
    end)
  end

  defp migrate_interest_records(dry_run?) do
    interest_records =
      Repo.all(
        from(c in "legacy_costs",
          where: c.cost_type in ^@interest_types,
          select: %{
            id: c.id,
            cost_type: c.cost_type,
            date: c.date,
            amount: c.amount,
            currency: c.currency,
            description: c.description,
            broker: c.broker
          },
          order_by: [asc: c.date]
        )
      )

    IO.puts("  Interest records to migrate: #{length(interest_records)}")

    Enum.reduce(interest_records, %{migrated: 0, skipped: 0, errors: 0}, fn rec, acc ->
      process_interest_record(rec, acc, dry_run?)
    end)
  end

  defp process_interest_record(rec, acc, dry_run?) do
    ext_id = "legacy_cost_#{rec.cost_type}_#{Ecto.UUID.cast!(rec.id)}"

    cond do
      Repo.exists?(from(cf in CashFlow, where: cf.external_id == ^ext_id)) ->
        %{acc | skipped: acc.skipped + 1}

      dry_run? ->
        %{acc | migrated: acc.migrated + 1}

      true ->
        insert_interest_cash_flow(rec, ext_id, acc)
    end
  end

  defp insert_interest_cash_flow(rec, ext_id, acc) do
    attrs = %{
      external_id: ext_id,
      flow_type: "interest",
      date: rec.date,
      amount: rec.amount || Decimal.new("0"),
      currency: rec.currency || "EUR",
      description: rec.description || "#{rec.cost_type} (#{rec.broker})",
      raw_data: %{"legacy_cost_type" => rec.cost_type, "broker" => rec.broker}
    }

    case Repo.insert(CashFlow.changeset(%CashFlow{}, attrs)) do
      {:ok, _} -> %{acc | migrated: acc.migrated + 1}
      {:error, _} -> %{acc | errors: acc.errors + 1}
    end
  end
end
