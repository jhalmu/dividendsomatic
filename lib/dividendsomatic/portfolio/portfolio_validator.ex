defmodule Dividendsomatic.Portfolio.PortfolioValidator do
  @moduledoc """
  Validates portfolio-level data integrity.

  Checks the accounting identity: current_value ≈ net_invested + total_return
  """

  alias Dividendsomatic.Portfolio

  @warn_threshold Decimal.new("1")
  @fail_threshold Decimal.new("5")

  @doc """
  Runs all portfolio validations and returns a report.
  """
  def validate do
    checks =
      case balance_check() do
        nil -> []
        check -> [check]
      end

    summary = summarize(checks)

    %{checks: checks, summary: summary}
  end

  defp balance_check do
    snapshot = Portfolio.get_latest_snapshot()

    case snapshot do
      nil ->
        nil

      snapshot ->
        zero = Decimal.new("0")

        current_value =
          Enum.reduce(snapshot.positions, zero, fn pos, acc ->
            fx = pos.fx_rate || Decimal.new("1")
            val = pos.value || zero
            Decimal.add(acc, Decimal.mult(val, fx))
          end)

        unrealized_pnl =
          Enum.reduce(snapshot.positions, zero, fn pos, acc ->
            pnl = pos.unrealized_pnl || zero
            Decimal.add(acc, pnl)
          end)

        summary = Portfolio.investment_summary()

        total_return =
          summary.net_profit
          |> Decimal.add(unrealized_pnl)

        expected = Decimal.add(summary.net_invested, total_return)
        difference = Decimal.abs(Decimal.sub(current_value, expected))

        difference_pct =
          if Decimal.compare(current_value, zero) == :gt do
            difference
            |> Decimal.div(current_value)
            |> Decimal.mult(Decimal.new("100"))
            |> Decimal.round(2)
          else
            zero
          end

        status = determine_status(difference_pct)

        %{
          name: :balance_check,
          status: status,
          expected: expected,
          actual: current_value,
          difference: difference,
          difference_pct: difference_pct,
          tolerance_pct: @warn_threshold,
          components: %{
            net_invested: summary.net_invested,
            total_deposits: summary.total_deposits,
            total_withdrawals: summary.total_withdrawals,
            realized_pnl: summary.realized_pnl,
            unrealized_pnl: unrealized_pnl,
            total_dividends: summary.total_dividends,
            total_costs: summary.total_costs,
            total_return: total_return,
            current_value: current_value
          }
        }
    end
  end

  defp determine_status(pct) do
    cond do
      Decimal.compare(pct, @warn_threshold) == :lt -> :pass
      Decimal.compare(pct, @fail_threshold) == :lt -> :warning
      true -> :fail
    end
  end

  defp summarize(checks) do
    Enum.reduce(checks, %{passed: 0, warnings: 0, failed: 0}, fn check, acc ->
      case check.status do
        :pass -> %{acc | passed: acc.passed + 1}
        :warning -> %{acc | warnings: acc.warnings + 1}
        :fail -> %{acc | failed: acc.failed + 1}
      end
    end)
  end
end
