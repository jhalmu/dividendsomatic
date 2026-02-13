defmodule Mix.Tasks.Backfill.SoldPnlEur do
  @moduledoc """
  Backfill realized_pnl_eur on sold_positions using historical FX rates.

  Phase 1 (Diagnostic): Reports currency coverage and FX rate availability.
  Phase 2 (Conversion): Converts non-EUR positions using OANDA FX rates.

  Usage:
    mix backfill.sold_pnl_eur           # Run diagnostic + conversion
    mix backfill.sold_pnl_eur --dry-run # Diagnostic only
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.SoldPosition
  alias Dividendsomatic.Repo
  alias Dividendsomatic.Stocks

  @shortdoc "Backfill realized_pnl_eur on sold positions"
  def run(args) do
    Mix.Task.run("app.start")

    dry_run = "--dry-run" in args

    Mix.shell().info("\n=== Realized P&L EUR Backfill ===\n")

    # Phase 1: Diagnostic
    currency_stats = diagnose_currencies()

    if currency_stats == [] do
      Mix.shell().info("No non-EUR positions need conversion. Done!")
      return_ok()
    else
      missing_pairs = report_fx_coverage(currency_stats)

      if missing_pairs != [] do
        Mix.shell().info("\nMissing FX pairs: #{Enum.join(missing_pairs, ", ")}")

        Mix.shell().info("Run `mix fetch.fx_rates` first, or these positions will be skipped.")
      end

      if dry_run do
        Mix.shell().info("\n--dry-run: No changes written.")
      else
        # Phase 2: Conversion
        Mix.shell().info("\n--- Phase 2: Converting ---\n")
        convert_positions(currency_stats)
      end

      return_ok()
    end
  end

  defp return_ok, do: :ok

  # Phase 1: Gather currency statistics for non-EUR unconverted positions
  defp diagnose_currencies do
    SoldPosition
    |> where([s], s.currency != "EUR" and is_nil(s.realized_pnl_eur))
    |> group_by([s], s.currency)
    |> select([s], %{
      currency: s.currency,
      count: count(s.id),
      min_date: min(s.sale_date),
      max_date: max(s.sale_date)
    })
    |> Repo.all()
  end

  defp report_fx_coverage(currency_stats) do
    Mix.shell().info(
      String.pad_trailing("Currency", 10) <>
        String.pad_trailing("Records", 10) <>
        String.pad_trailing("Date Range", 25) <>
        String.pad_trailing("FX Pair", 20) <>
        "Coverage"
    )

    Mix.shell().info(String.duplicate("-", 85))

    Enum.reduce(currency_stats, [], fn stat, missing_acc ->
      pair = "OANDA:EUR_#{stat.currency}"
      range = Stocks.historical_price_range(pair)

      {coverage, missing?} =
        case range do
          %{count: 0} ->
            {"NOT FOUND", true}

          nil ->
            {"NOT FOUND", true}

          %{min_date: min_d, max_date: max_d, count: count} ->
            # Calculate expected trading days in the needed range
            needed_days = Date.diff(stat.max_date, stat.min_date) + 1
            # Rough coverage: FX markets ~260 days/year, so ~71% of calendar days
            expected_trading_days = max(round(needed_days * 0.71), 1)
            pct = min(round(count / expected_trading_days * 100), 100)
            {"#{pct}% (#{count} days, #{min_d} → #{max_d})", false}
        end

      date_range = "#{stat.min_date} → #{stat.max_date}"

      Mix.shell().info(
        String.pad_trailing(stat.currency || "?", 10) <>
          String.pad_trailing(to_string(stat.count), 10) <>
          String.pad_trailing(date_range, 25) <>
          String.pad_trailing(pair, 20) <>
          coverage
      )

      if missing?, do: [pair | missing_acc], else: missing_acc
    end)
  end

  # Phase 2: Load FX rates and convert positions
  defp convert_positions(currency_stats) do
    # Build FX pair list and date range
    fx_pairs = Enum.map(currency_stats, fn s -> "OANDA:EUR_#{s.currency}" end)
    min_date = currency_stats |> Enum.map(& &1.min_date) |> Enum.min(Date) |> Date.add(-5)
    max_date = currency_stats |> Enum.map(& &1.max_date) |> Enum.max(Date)

    # Batch-load all FX rates
    price_map = Stocks.batch_historical_prices(fx_pairs, min_date, max_date)

    # Load unconverted positions
    positions =
      SoldPosition
      |> where([s], is_nil(s.realized_pnl_eur) and s.currency != "EUR")
      |> Repo.all()

    {converted, skipped} =
      Enum.reduce(positions, {0, 0}, fn pos, {conv, skip} ->
        case convert_single_position(pos, price_map) do
          :converted -> {conv + 1, skip}
          :skipped -> {conv, skip + 1}
        end
      end)

    Mix.shell().info("Converted: #{converted}")
    Mix.shell().info("Skipped (missing FX rate): #{skipped}")

    if skipped > 0 do
      report_skipped_details(positions, price_map)
    end
  end

  defp convert_single_position(pos, price_map) do
    pair = "OANDA:EUR_#{pos.currency}"

    case lookup_positive_rate(price_map, pair, pos.sale_date) do
      {:ok, rate} ->
        pnl_eur = Decimal.div(pos.realized_pnl, rate)

        pos
        |> SoldPosition.changeset(%{realized_pnl_eur: pnl_eur, exchange_rate_to_eur: rate})
        |> Repo.update!()

        :converted

      :skip ->
        :skipped
    end
  end

  defp lookup_positive_rate(price_map, pair, date) do
    case Stocks.batch_get_close_price(price_map, pair, date) do
      {:ok, rate} when not is_nil(rate) ->
        if Decimal.compare(rate, Decimal.new("0")) == :gt, do: {:ok, rate}, else: :skip

      _ ->
        :skip
    end
  end

  defp report_skipped_details(positions, price_map) do
    Mix.shell().info("\nSkipped position details:")

    positions
    |> Enum.filter(fn pos ->
      pair = "OANDA:EUR_#{pos.currency}"
      Stocks.batch_get_close_price(price_map, pair, pos.sale_date) == {:error, :no_price}
    end)
    |> Enum.take(20)
    |> Enum.each(fn pos ->
      Mix.shell().info("  #{pos.symbol} #{pos.currency} #{pos.sale_date}")
    end)
  end
end
