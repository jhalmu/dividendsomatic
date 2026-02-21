defmodule Dividendsomatic.Portfolio.PortfolioValidator do
  @moduledoc """
  Validates portfolio-level data integrity.

  Checks the accounting identity: current_value ≈ net_invested + total_return

  For margin accounts (when margin_equity_snapshots exist), uses NLV
  (net liquidation value) for both start and end points instead of
  position_value/cost_basis. This correctly accounts for margin-funded
  positions and cash balances.

  Scoped to IBKR data only. Cash flows and positions are IBKR-sourced,
  so realized P&L is filtered to source="ibkr" to avoid counting
  Nordnet/Lynx 9A trades that lack corresponding deposit records.
  """

  import Ecto.Query

  alias Dividendsomatic.Portfolio

  alias Dividendsomatic.Portfolio.{
    CashFlow,
    DividendPayment,
    MarginEquitySnapshot,
    PortfolioSnapshot,
    SoldPosition
  }

  alias Dividendsomatic.Repo

  # Thresholds for cash/simple accounts (no margin data)
  @warn_threshold Decimal.new("1")
  @fail_threshold Decimal.new("5")

  # Wider thresholds for margin accounts — FX effects on cash balances,
  # corporate actions, and timing differences cause legitimate gaps
  @margin_warn_threshold Decimal.new("5")
  @margin_fail_threshold Decimal.new("20")

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

        position_value = compute_position_value(snapshot.positions, zero)

        # EUR-converted unrealized P&L (multiply by fx_rate per position)
        unrealized_pnl = compute_unrealized_pnl(snapshot.positions, zero)

        # Cash balance from latest margin equity snapshot (informational)
        cash_balance = latest_cash_balance()

        # Initial capital + date boundary from first IBKR Flex snapshot.
        # For margin accounts, uses NLV from nearest margin equity snapshot
        # instead of cost_basis (which includes margin-funded positions).
        {initial_capital, ibkr_start_date, margin_mode} =
          initial_capital_and_date(zero)

        # For margin accounts, use NLV as current_value (accounts for cash/margin).
        # For simple accounts, use position_value (no margin data available).
        current_value =
          if margin_mode do
            latest_nlv() || position_value
          else
            position_value
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

        # Dividends — direct EUR sum from dividend_payments table.
        # More accurate than the compute_dividend_income pipeline which
        # zeroes out cross-currency dividends without position fx_rate.
        total_dividends = total_dividends_eur()

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

        status = determine_status(difference_pct, margin_mode)

        %{
          name: :balance_check,
          status: status,
          expected: expected,
          actual: current_value,
          difference: difference,
          difference_pct: difference_pct,
          tolerance_pct: if(margin_mode, do: @margin_warn_threshold, else: @warn_threshold),
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
            current_value: current_value,
            margin_mode: margin_mode
          }
        }
    end
  end

  defp compute_position_value(positions, zero) do
    Enum.reduce(positions, zero, fn pos, acc ->
      fx = pos.fx_rate || Decimal.new("1")
      val = pos.value || zero
      Decimal.add(acc, Decimal.mult(val, fx))
    end)
  end

  defp compute_unrealized_pnl(positions, zero) do
    Enum.reduce(positions, zero, fn pos, acc ->
      pnl = pos.unrealized_pnl || zero
      fx = pos.fx_rate || Decimal.new("1")
      Decimal.add(acc, Decimal.mult(pnl, fx))
    end)
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

  # Direct EUR sum from dividend_payments — more accurate than the
  # compute_dividend_income pipeline which zeroes out cross-currency
  # dividends without matching position fx_rate.
  defp total_dividends_eur do
    DividendPayment
    |> select([d], sum(fragment("COALESCE(?, ?)", d.amount_eur, d.net_amount)))
    |> Repo.one() || Decimal.new("0")
  end

  # Returns {cost_basis, date} from the first IBKR Flex snapshot.
  defp first_ibkr_snapshot do
    PortfolioSnapshot
    |> where([s], s.source == "ibkr_flex")
    |> order_by([s], asc: s.date)
    |> limit(1)
    |> select([s], {s.total_cost, s.date})
    |> Repo.one()
  end

  # Determines initial capital and whether to use margin (NLV) mode.
  # For margin accounts, NLV is the correct starting equity (not cost_basis,
  # which includes margin-funded positions).
  defp initial_capital_and_date(zero) do
    case first_ibkr_snapshot() do
      {cost_basis, ibkr_date} ->
        case margin_equity_near_date(ibkr_date) do
          %{net_liquidation_value: nlv} when not is_nil(nlv) ->
            {nlv, ibkr_date, true}

          _ ->
            {cost_basis, ibkr_date, false}
        end

      nil ->
        {zero, nil, false}
    end
  end

  defp margin_equity_near_date(date) do
    Portfolio.get_margin_equity_nearest_date(date)
  end

  defp latest_nlv do
    Repo.one(
      from(m in MarginEquitySnapshot,
        order_by: [desc: m.date],
        limit: 1,
        select: m.net_liquidation_value
      )
    )
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
      |> select([c], %{flow_type: c.flow_type, amount: c.amount, amount_eur: c.amount_eur})
      |> Repo.all()

    Enum.reduce(results, {zero, zero}, fn cf, {dep_acc, wd_acc} ->
      # Prefer EUR-converted amount, fall back to raw amount
      amt = Decimal.abs(cf.amount_eur || cf.amount || zero)

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

  defp determine_status(pct, margin_mode) do
    {warn, fail} =
      if margin_mode,
        do: {@margin_warn_threshold, @margin_fail_threshold},
        else: {@warn_threshold, @fail_threshold}

    cond do
      Decimal.compare(pct, warn) == :lt -> :pass
      Decimal.compare(pct, fail) == :lt -> :warning
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
