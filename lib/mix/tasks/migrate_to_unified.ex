defmodule Mix.Tasks.Migrate.ToUnified do
  @moduledoc """
  Migrates data from legacy_portfolio_snapshots + legacy_holdings
  to the new unified portfolio_snapshots + positions tables.

  Maps old IBKR-specific field names to generic names and precomputes
  total_value/total_cost per snapshot.

  Usage:
    mix migrate.to_unified            # Run migration
    mix migrate.to_unified --dry-run  # Preview without writing
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{Holding, LegacyPortfolioSnapshot, PortfolioSnapshot, Position}
  alias Dividendsomatic.Repo

  @shortdoc "Migrate legacy snapshots/holdings to unified schema"

  def run(args) do
    Mix.Task.run("app.start")

    if "--dry-run" in args do
      dry_run()
    else
      migrate()
    end
  end

  defp dry_run do
    IO.puts("--- Dry Run: Legacy → Unified Migration ---\n")

    snapshots = Repo.all(LegacyPortfolioSnapshot)
    IO.puts("  Legacy snapshots: #{length(snapshots)}")

    holdings_count =
      Holding
      |> select([h], count())
      |> Repo.one()

    IO.puts("  Legacy holdings: #{holdings_count}")

    existing =
      PortfolioSnapshot
      |> select([s], count())
      |> Repo.one()

    IO.puts("  Existing unified snapshots: #{existing}")
    IO.puts("\n  Would migrate #{length(snapshots)} snapshots with #{holdings_count} positions")
  end

  defp migrate do
    IO.puts("--- Migrating Legacy → Unified Schema ---\n")

    snapshots = Repo.all(LegacyPortfolioSnapshot)
    IO.puts("  Legacy snapshots to migrate: #{length(snapshots)}")

    {created, skipped, errors} =
      Enum.reduce(snapshots, {0, 0, 0}, fn legacy_snap, acc ->
        process_legacy_snapshot(legacy_snap, acc)
      end)

    IO.puts("\n--- Done ---")
    IO.puts("  Created: #{created}")
    IO.puts("  Skipped: #{skipped} (already exist)")
    IO.puts("  Errors: #{errors}")
  end

  defp process_legacy_snapshot(legacy_snap, {c, s, e}) do
    case migrate_snapshot(legacy_snap) do
      :ok ->
        if rem(c + 1, 25) == 0, do: IO.puts("  Migrated #{c + 1} snapshots...")
        {c + 1, s, e}

      :skipped ->
        {c, s + 1, e}

      {:error, reason} ->
        IO.puts("  ERROR #{legacy_snap.report_date}: #{inspect(reason)}")
        {c, s, e + 1}
    end
  end

  defp migrate_snapshot(legacy_snap) do
    # Skip if date already exists in new table
    if Repo.exists?(from s in PortfolioSnapshot, where: s.date == ^legacy_snap.report_date) do
      :skipped
    else
      do_migrate_snapshot(legacy_snap)
    end
  end

  defp do_migrate_snapshot(legacy_snap) do
    # Load legacy holdings for this snapshot
    legacy_holdings =
      Holding
      |> where([h], h.portfolio_snapshot_id == ^legacy_snap.id)
      |> Repo.all()

    # Compute totals
    {total_value, total_cost} = compute_totals(legacy_holdings)

    source = map_source(legacy_snap.source)
    data_quality = if source == "nordnet", do: "reconstructed", else: "actual"

    Repo.transaction(fn ->
      {:ok, new_snap} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{
          date: legacy_snap.report_date,
          total_value: total_value,
          total_cost: total_cost,
          source: source,
          data_quality: data_quality,
          positions_count: length(legacy_holdings),
          metadata: build_metadata(legacy_snap)
        })
        |> Repo.insert()

      Enum.each(legacy_holdings, fn h ->
        migrate_holding(new_snap.id, h)
      end)

      new_snap
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp compute_totals(holdings) do
    Enum.reduce(holdings, {Decimal.new("0"), Decimal.new("0")}, fn h, {val_acc, cost_acc} ->
      fx = h.fx_rate_to_base || Decimal.new("1")
      pos_val = h.position_value || Decimal.new("0")
      cost_val = h.cost_basis_money || Decimal.new("0")

      {
        Decimal.add(val_acc, Decimal.mult(pos_val, fx)),
        Decimal.add(cost_acc, Decimal.mult(cost_val, fx))
      }
    end)
  end

  defp migrate_holding(snapshot_id, h) do
    %Position{}
    |> Position.changeset(%{
      portfolio_snapshot_id: snapshot_id,
      date: h.report_date,
      isin: h.isin,
      symbol: h.symbol,
      name: h.description,
      asset_class: h.asset_class,
      exchange: h.listing_exchange,
      quantity: h.quantity,
      price: h.mark_price,
      value: h.position_value,
      cost_basis: h.cost_basis_money,
      cost_price: h.cost_basis_price,
      currency: h.currency_primary,
      fx_rate: h.fx_rate_to_base,
      unrealized_pnl: h.fifo_pnl_unrealized,
      weight: h.percent_of_nav,
      figi: h.figi,
      data_source: "ibkr_flex"
    })
    |> Repo.insert!()
  end

  defp map_source(nil), do: "ibkr_flex"
  defp map_source("nordnet_reconstructed"), do: "nordnet"
  defp map_source(source), do: source

  defp build_metadata(%{raw_csv_data: nil}), do: nil
  defp build_metadata(%{raw_csv_data: csv}), do: %{"raw_csv" => String.length(csv)}
end
