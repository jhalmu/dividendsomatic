defmodule Dividendsomatic.Portfolio.PortfolioValidator do
  @moduledoc """
  Validates portfolio-level data integrity.

  Checks the accounting identity: current_value ≈ net_invested + total_return

  Scoped to IBKR data only. Cash flows and positions are IBKR-sourced,
  so realized P&L is filtered to source="ibkr" to avoid counting
  Nordnet/Lynx 9A trades that lack corresponding deposit records.
  """

  import Ecto.Query

  alias Dividendsomatic.Portfolio

  alias Dividendsomatic.Portfolio.{
    CashFlow,
    MarginEquitySnapshot,
    PortfolioSnapshot,
    SoldPosition
  }

  alias Dividendsomatic.Repo

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

        position_value =
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

        # Cash balance from latest margin equity snapshot (informational)
        cash_balance = latest_cash_balance()

        # Use position value as current_value for the balance check.
        # The cash_balance is shown separately for transparency but not added
        # to the equation — positions already reflect margin-funded holdings,
        # and the negative cash (margin loan) is a liability, not a loss.
        current_value = position_value

        # Initial capital + date boundary from first IBKR Flex snapshot
        {initial_capital, ibkr_start_date} =
          case first_ibkr_snapshot() do
            {cost, date} -> {cost, date}
            nil -> {zero, nil}
          end

        # Cash flows AFTER the first IBKR snapshot (avoid double-counting)
        {deposits, withdrawals} = deposits_withdrawals_after(ibkr_start_date)

        # Net invested = initial capital + post-snapshot deposits - withdrawals
        net_invested =
          initial_capital
          |> Decimal.add(deposits)
          |> Decimal.sub(withdrawals)

        # Split costs into interest and fees
        costs_by_type = Portfolio.total_costs_by_type()
        interest_costs = Map.get(costs_by_type, "interest", zero)
        fee_costs = Map.get(costs_by_type, "fee", zero)
        total_costs = Decimal.add(interest_costs, fee_costs)

        # Dividends
        total_dividends = portfolio_total_dividends()

        # IBKR-only realized P&L
        realized_pnl = ibkr_realized_pnl()

        net_profit =
          realized_pnl
          |> Decimal.add(total_dividends)
          |> Decimal.sub(total_costs)

        total_return = Decimal.add(net_profit, unrealized_pnl)

        expected = Decimal.add(net_invested, total_return)
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
            initial_capital: initial_capital,
            net_invested: net_invested,
            total_deposits: deposits,
            total_withdrawals: withdrawals,
            realized_pnl: realized_pnl,
            unrealized_pnl: unrealized_pnl,
            total_dividends: total_dividends,
            total_costs: total_costs,
            interest_costs: interest_costs,
            fee_costs: fee_costs,
            total_return: total_return,
            position_value: position_value,
            cash_balance: cash_balance,
            current_value: current_value
          }
        }
    end
  end

  defp latest_cash_balance do
    case Repo.one(
           from(m in MarginEquitySnapshot,
             order_by: [desc: m.date],
             limit: 1,
             select: m.cash_balance
           )
         ) do
      nil -> Decimal.new("0")
      cash -> cash
    end
  end

  defp portfolio_total_dividends do
    zero = Decimal.new("0")

    Portfolio.dividend_years()
    |> Enum.reduce(zero, fn year, acc ->
      Decimal.add(acc, Portfolio.total_dividends_for_year(year))
    end)
  end

  # Returns {cost_basis, date} from the first IBKR Flex snapshot.
  # Cost basis represents positions transferred in-kind + cash deposits
  # up to that date. Cash flows after this date are counted separately.
  defp first_ibkr_snapshot do
    PortfolioSnapshot
    |> where([s], s.source == "ibkr_flex")
    |> order_by([s], asc: s.date)
    |> limit(1)
    |> select([s], {s.total_cost, s.date})
    |> Repo.one()
  end

  # Returns {deposits, withdrawals} for cash flows after the given date.
  # When date is nil (no IBKR snapshot), returns all cash flows.
  defp deposits_withdrawals_after(nil) do
    dw = Portfolio.total_deposits_withdrawals()
    {dw.deposits, dw.withdrawals}
  end

  defp deposits_withdrawals_after(date) do
    zero = Decimal.new("0")

    results =
      CashFlow
      |> where([c], c.flow_type in ["deposit", "withdrawal"])
      |> where([c], c.date > ^date)
      |> select([c], %{flow_type: c.flow_type, amount: c.amount})
      |> Repo.all()

    Enum.reduce(results, {zero, zero}, fn cf, {dep_acc, wd_acc} ->
      amt = Decimal.abs(cf.amount || zero)

      case cf.flow_type do
        "deposit" -> {Decimal.add(dep_acc, amt), wd_acc}
        "withdrawal" -> {dep_acc, Decimal.add(wd_acc, amt)}
        _ -> {dep_acc, wd_acc}
      end
    end)
  end

  defp ibkr_realized_pnl do
    SoldPosition
    |> where([s], s.source == "ibkr")
    |> select([s], sum(fragment("COALESCE(?, ?)", s.realized_pnl_eur, s.realized_pnl)))
    |> Repo.one() || Decimal.new("0")
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
