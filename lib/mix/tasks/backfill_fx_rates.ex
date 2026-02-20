defmodule Mix.Tasks.Backfill.FxRates do
  @moduledoc """
  Backfill fx_rate and amount_eur on dividend_payments and cash_flows.

  ## Usage

      mix backfill.fx_rates              # Backfill all records
      mix backfill.fx_rates --dry-run    # Show what would be updated

  For each record where fx_rate IS NULL:
  - EUR records: fx_rate = 1, amount_eur = amount
  - Other currencies: look up fx_rate from fx_rates table, compute amount_eur
  """

  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio
  alias Dividendsomatic.Portfolio.{CashFlow, Dividend, DividendPayment}
  alias Dividendsomatic.Repo

  require Logger

  @shortdoc "Backfill fx_rate + amount_eur on dividend_payments and cash_flows"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Logger.configure(level: :info)

    {opts, _, _} = OptionParser.parse(args, switches: [dry_run: :boolean])
    dry_run = opts[:dry_run] || false

    if dry_run, do: Mix.shell().info("DRY RUN — no records will be updated\n")

    div_result = backfill_dividends(dry_run)
    cf_result = backfill_cash_flows(dry_run)
    legacy_result = backfill_legacy_dividends(dry_run)

    Mix.shell().info("\nSummary:")

    Mix.shell().info(
      "  Dividends: #{div_result.updated} updated, #{div_result.skipped} skipped (no rate)"
    )

    Mix.shell().info(
      "  Cash flows: #{cf_result.updated} updated, #{cf_result.skipped} skipped (no rate)"
    )

    Mix.shell().info(
      "  Legacy dividends: #{legacy_result.updated} updated, #{legacy_result.skipped} skipped (no rate)"
    )

    remaining_div = DividendPayment |> where([d], is_nil(d.fx_rate)) |> Repo.aggregate(:count)
    remaining_cf = CashFlow |> where([c], is_nil(c.fx_rate)) |> Repo.aggregate(:count)

    remaining_legacy =
      Dividend
      |> where([d], d.amount_type == "total_net" and d.currency != "EUR" and is_nil(d.fx_rate))
      |> Repo.aggregate(:count)

    Mix.shell().info(
      "\n  Remaining without fx_rate: #{remaining_div} dividends, #{remaining_cf} cash flows, #{remaining_legacy} legacy dividends"
    )
  end

  defp backfill_dividends(dry_run) do
    records =
      DividendPayment
      |> where([d], is_nil(d.fx_rate))
      |> select([d], %{
        id: d.id,
        currency: d.currency,
        pay_date: d.pay_date,
        net_amount: d.net_amount
      })
      |> Repo.all()

    Mix.shell().info("Backfilling #{length(records)} dividend_payments...")

    Enum.reduce(records, %{updated: 0, skipped: 0}, fn record, acc ->
      rate = Portfolio.get_fx_rate(record.currency, record.pay_date)
      apply_backfill(DividendPayment, record.id, record.net_amount, rate, dry_run, acc)
    end)
  end

  defp backfill_cash_flows(dry_run) do
    records =
      CashFlow
      |> where([c], is_nil(c.fx_rate))
      |> select([c], %{id: c.id, currency: c.currency, date: c.date, amount: c.amount})
      |> Repo.all()

    Mix.shell().info("Backfilling #{length(records)} cash_flows...")

    Enum.reduce(records, %{updated: 0, skipped: 0}, fn record, acc ->
      rate = Portfolio.get_fx_rate(record.currency, record.date)
      apply_backfill(CashFlow, record.id, record.amount, rate, dry_run, acc)
    end)
  end

  defp backfill_legacy_dividends(dry_run) do
    records =
      Dividend
      |> where([d], d.amount_type == "total_net" and d.currency != "EUR" and is_nil(d.fx_rate))
      |> select([d], %{id: d.id, currency: d.currency, ex_date: d.ex_date, amount: d.amount})
      |> Repo.all()

    Mix.shell().info("Backfilling #{length(records)} legacy_dividends...")

    Enum.reduce(records, %{updated: 0, skipped: 0}, fn record, acc ->
      rate = Portfolio.get_fx_rate(record.currency, record.ex_date)
      apply_backfill(Dividend, record.id, record.amount, rate, dry_run, acc)
    end)
  end

  defp apply_backfill(_schema, _id, _amount, nil, _dry_run, acc) do
    %{acc | skipped: acc.skipped + 1}
  end

  defp apply_backfill(_schema, _id, _amount, _rate, true, acc) do
    %{acc | updated: acc.updated + 1}
  end

  # Dividend schema has no amount_eur field — only set fx_rate
  defp apply_backfill(Dividend, id, _amount, rate, false, acc) do
    Dividend
    |> where([r], r.id == ^id)
    |> Repo.update_all(set: [fx_rate: rate])

    %{acc | updated: acc.updated + 1}
  end

  defp apply_backfill(schema, id, amount, rate, false, acc) do
    amount_eur = Decimal.mult(amount, rate)

    schema
    |> where([r], r.id == ^id)
    |> Repo.update_all(set: [fx_rate: rate, amount_eur: amount_eur])

    %{acc | updated: acc.updated + 1}
  end
end
