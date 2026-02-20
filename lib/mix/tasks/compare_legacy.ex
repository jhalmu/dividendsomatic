defmodule Mix.Tasks.Compare.Legacy do
  @moduledoc """
  Compare legacy tables against new clean tables to identify data gaps.

  ## Usage

      mix compare.legacy
  """

  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Repo

  @shortdoc "Compare legacy vs new tables"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("=== Legacy vs New Table Comparison ===\n")

    compare_trades()
    compare_dividends()
    compare_costs()
    summary()
  end

  defp compare_trades do
    Mix.shell().info("--- Trades ---")

    legacy_count = Repo.one(from(t in "legacy_broker_transactions", select: count()))
    new_count = Repo.one(from(t in "trades", select: count()))

    Mix.shell().info("  Legacy broker_transactions: #{legacy_count}")
    Mix.shell().info("  New trades:                 #{new_count}")
    Mix.shell().info("  Difference:                 #{new_count - legacy_count}")

    Mix.shell().info(
      "  Note: New trades has #{new_count - legacy_count} more (IBKR fill-level detail)"
    )

    Mix.shell().info("")
  end

  defp compare_dividends do
    Mix.shell().info("--- Dividends ---")

    legacy_count = Repo.one(from(d in "legacy_dividends", select: count()))
    new_count = Repo.one(from(d in "dividend_payments", select: count()))

    Mix.shell().info("  Legacy dividends:    #{legacy_count}")
    Mix.shell().info("  New dividend_payments: #{new_count}")

    # Break down legacy by source
    by_source =
      Repo.all(
        from(d in "legacy_dividends",
          group_by: d.source,
          select: {d.source, count()}
        )
      )

    Mix.shell().info("  Legacy by source:")
    Enum.each(by_source, fn {src, count} -> Mix.shell().info("    #{src || "nil"}: #{count}") end)

    # Check how many legacy dividends have zero income
    zero_income =
      Repo.one(
        from(d in "legacy_dividends",
          where:
            fragment("COALESCE(CAST(? AS numeric), 0)", d.amount) == 0.0 or
              is_nil(d.amount),
          select: count()
        )
      )

    Mix.shell().info("  Legacy zero-income dividends: #{zero_income}")

    # IBKR-only legacy dividends (comparable to new)
    ibkr_legacy =
      Repo.one(
        from(d in "legacy_dividends",
          where: d.source in ["ibkr", "ibkr_flex_dividend"],
          select: count()
        )
      )

    Mix.shell().info("  Legacy IBKR dividends:  #{ibkr_legacy}")
    Mix.shell().info("  New IBKR dividends:     #{new_count} (all are IBKR)")

    # Compare totals for IBKR dividends
    legacy_total =
      Repo.one(
        from(d in "legacy_dividends",
          where: d.source in ["ibkr", "ibkr_flex_dividend"],
          select: sum(fragment("COALESCE(?, 0)", d.net_amount))
        )
      ) || Decimal.new("0")

    new_total =
      Repo.one(from(d in "dividend_payments", select: sum(d.net_amount))) || Decimal.new("0")

    Mix.shell().info("  Legacy IBKR total net:  #{Decimal.round(legacy_total, 2)}")

    Mix.shell().info("  New total net:          #{Decimal.round(new_total, 2)}")
    Mix.shell().info("")
  end

  defp compare_costs do
    Mix.shell().info("--- Costs ---")

    legacy_count = Repo.one(from(c in "legacy_costs", select: count()))

    new_cf_cost_count =
      Repo.one(
        from(c in "cash_flows",
          where: c.flow_type in ["interest", "fee"],
          select: count()
        )
      )

    Mix.shell().info("  Legacy costs:         #{legacy_count}")
    Mix.shell().info("  New cash_flows (int+fee): #{new_cf_cost_count}")

    # Break down legacy
    legacy_by_type =
      Repo.all(
        from(c in "legacy_costs",
          group_by: c.cost_type,
          select:
            {c.cost_type, count(),
             sum(fragment("ABS(COALESCE(CAST(? AS numeric), 0))", c.amount))}
        )
      )

    Mix.shell().info("  Legacy by type:")

    Enum.each(legacy_by_type, fn {type, count, total} ->
      total_str = if total, do: " (total: #{Decimal.round(total, 2)})", else: ""
      Mix.shell().info("    #{type}: #{count}#{total_str}")
    end)

    # New cash flow costs breakdown
    new_by_type =
      Repo.all(
        from(c in "cash_flows",
          where: c.flow_type in ["interest", "fee"],
          group_by: c.flow_type,
          select: {c.flow_type, count(), sum(fragment("ABS(?)", c.amount))}
        )
      )

    Mix.shell().info("  New by type:")

    Enum.each(new_by_type, fn {type, count, total} ->
      total_str = if total, do: " (total: #{Decimal.round(total, 2)})", else: ""
      Mix.shell().info("    #{type}: #{count}#{total_str}")
    end)

    Mix.shell().info(
      "\n  Note: Legacy 'commission' (#{commission_count(legacy_by_type)}) is now in trades.commission column"
    )

    Mix.shell().info(
      "  Note: Legacy 'withholding_tax' + 'foreign_tax' is now in dividend_payments.withholding_tax"
    )

    Mix.shell().info("")
  end

  defp commission_count(by_type) do
    Enum.find_value(by_type, 0, fn {type, count, _} ->
      if type == "commission", do: count
    end)
  end

  defp summary do
    Mix.shell().info("--- Data Coverage Summary ---")

    # Commissions: legacy had them as separate costs, new has them in trades.commission
    commission_total =
      Repo.one(
        from(t in "trades",
          select: sum(fragment("ABS(?)", t.commission))
        )
      ) || Decimal.new("0")

    Mix.shell().info(
      "  Trade commissions (from trades.commission): #{Decimal.round(commission_total, 2)}"
    )

    # WHT: now in dividend_payments.withholding_tax
    wht_total =
      Repo.one(
        from(d in "dividend_payments",
          select: sum(fragment("ABS(?)", d.withholding_tax))
        )
      ) || Decimal.new("0")

    Mix.shell().info("  Withholding tax (from dividend_payments): #{Decimal.round(wht_total, 2)}")

    # Interest: in cash_flows
    interest_total =
      Repo.one(
        from(c in "cash_flows",
          where: c.flow_type == "interest",
          select: sum(fragment("ABS(?)", c.amount))
        )
      ) || Decimal.new("0")

    Mix.shell().info("  Interest costs (from cash_flows): #{Decimal.round(interest_total, 2)}")

    # Fees: in cash_flows
    fee_total =
      Repo.one(
        from(c in "cash_flows",
          where: c.flow_type == "fee",
          select: sum(fragment("ABS(?)", c.amount))
        )
      ) || Decimal.new("0")

    Mix.shell().info("  Fee costs (from cash_flows): #{Decimal.round(fee_total, 2)}")

    Mix.shell().info("\n  Verdict: Legacy cost data is now distributed across:")
    Mix.shell().info("    commission → trades.commission")
    Mix.shell().info("    withholding_tax/foreign_tax → dividend_payments.withholding_tax")
    Mix.shell().info("    loan_interest/capital_interest → cash_flows (interest)")
    Mix.shell().info("    fees → cash_flows (fee)")
  end
end
