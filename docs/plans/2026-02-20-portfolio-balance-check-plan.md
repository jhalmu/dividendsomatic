# Portfolio Balance Check Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Validate the accounting identity `current_value ≈ net_invested + total_return` via a `PortfolioValidator` module integrated into `mix validate.data`.

**Architecture:** New `PortfolioValidator` module following the `DividendValidator` pattern. Reuses existing `Portfolio.investment_summary/0` for most data, adds unrealized P&L computation from latest snapshot positions. Integrated into the existing mix task as a new section.

**Tech Stack:** Elixir, Ecto queries, Decimal arithmetic, Mix task

---

### Task 1: PortfolioValidator — failing tests

**Files:**
- Create: `test/dividendsomatic/portfolio/portfolio_validator_test.exs`

**Step 1: Write failing tests**

```elixir
defmodule Dividendsomatic.Portfolio.PortfolioValidatorTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.{
    CashFlow,
    PortfolioSnapshot,
    PortfolioValidator,
    Position,
    SoldPosition
  }

  describe "validate/0" do
    test "should return empty checks with no data" do
      result = PortfolioValidator.validate()
      assert result.checks == []
      assert result.summary == %{passed: 0, warnings: 0, failed: 0}
    end

    test "should pass when balance is within 1% tolerance" do
      setup_balanced_portfolio(
        deposits: "100000",
        current_value: "110000",
        unrealized_pnl: "10000",
        cost_basis: "100000"
      )

      result = PortfolioValidator.validate()
      assert length(result.checks) == 1

      check = hd(result.checks)
      assert check.name == :balance_check
      assert check.status == :pass
      assert check.components.net_invested == Decimal.new("100000")
      assert check.components.current_value == Decimal.new("110000")
    end

    test "should warn when difference is between 1% and 5%" do
      # net_invested=100k, unrealized=10k → expected=110k, but current_value=113k (2.7% off)
      setup_balanced_portfolio(
        deposits: "100000",
        current_value: "113000",
        unrealized_pnl: "10000",
        cost_basis: "100000"
      )

      result = PortfolioValidator.validate()
      check = hd(result.checks)
      assert check.status == :warning
      assert result.summary.warnings == 1
    end

    test "should fail when difference exceeds 5%" do
      # net_invested=100k, unrealized=10k → expected=110k, but current_value=120k (9.1% off)
      setup_balanced_portfolio(
        deposits: "100000",
        current_value: "120000",
        unrealized_pnl: "10000",
        cost_basis: "100000"
      )

      result = PortfolioValidator.validate()
      check = hd(result.checks)
      assert check.status == :fail
      assert result.summary.failed == 1
    end

    test "should include all components in the check" do
      setup_balanced_portfolio(
        deposits: "100000",
        current_value: "110000",
        unrealized_pnl: "10000",
        cost_basis: "100000"
      )

      result = PortfolioValidator.validate()
      check = hd(result.checks)

      assert Map.has_key?(check.components, :net_invested)
      assert Map.has_key?(check.components, :total_deposits)
      assert Map.has_key?(check.components, :total_withdrawals)
      assert Map.has_key?(check.components, :realized_pnl)
      assert Map.has_key?(check.components, :unrealized_pnl)
      assert Map.has_key?(check.components, :total_dividends)
      assert Map.has_key?(check.components, :total_costs)
      assert Map.has_key?(check.components, :total_return)
      assert Map.has_key?(check.components, :current_value)
    end

    test "should compute difference and percentage correctly" do
      setup_balanced_portfolio(
        deposits: "100000",
        current_value: "110500",
        unrealized_pnl: "10000",
        cost_basis: "100000"
      )

      result = PortfolioValidator.validate()
      check = hd(result.checks)

      # expected = 100000 (net_invested) + 10000 (unrealized) = 110000
      # actual = 110500
      # difference = 500
      assert Decimal.equal?(check.difference, Decimal.new("500"))
    end
  end

  # Helper: creates a minimal balanced portfolio for testing.
  # Deposits go into cash_flows, positions into a snapshot.
  defp setup_balanced_portfolio(opts) do
    deposits = Keyword.fetch!(opts, :deposits)
    current_value = Keyword.fetch!(opts, :current_value)
    unrealized_pnl = Keyword.fetch!(opts, :unrealized_pnl)
    cost_basis = Keyword.fetch!(opts, :cost_basis)

    # Insert deposit cash flow
    %CashFlow{}
    |> CashFlow.changeset(%{
      external_id: "test-deposit-1",
      flow_type: "deposit",
      date: ~D[2024-01-01],
      amount: Decimal.new(deposits),
      currency: "EUR",
      fx_rate: Decimal.new("1"),
      amount_eur: Decimal.new(deposits),
      description: "Test deposit"
    })
    |> Repo.insert!()

    # Insert snapshot with position
    {:ok, snapshot} =
      %PortfolioSnapshot{}
      |> PortfolioSnapshot.changeset(%{
        date: ~D[2024-06-15],
        total_value: Decimal.new(current_value),
        total_cost: Decimal.new(cost_basis),
        source: "test",
        data_quality: "actual"
      })
      |> Repo.insert()

    %Position{}
    |> Position.changeset(%{
      portfolio_snapshot_id: snapshot.id,
      date: ~D[2024-06-15],
      symbol: "TEST",
      name: "Test Stock",
      isin: "US0000000000",
      quantity: Decimal.new("1000"),
      price: Decimal.div(Decimal.new(current_value), Decimal.new("1000")),
      value: Decimal.new(current_value),
      cost_basis: Decimal.new(cost_basis),
      cost_price: Decimal.div(Decimal.new(cost_basis), Decimal.new("1000")),
      currency: "EUR",
      fx_rate: Decimal.new("1"),
      unrealized_pnl: Decimal.new(unrealized_pnl)
    })
    |> Repo.insert!()
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/dividendsomatic/portfolio/portfolio_validator_test.exs`
Expected: FAIL — `PortfolioValidator` module not found

---

### Task 2: PortfolioValidator — implementation

**Files:**
- Create: `lib/dividendsomatic/portfolio/portfolio_validator.ex`

**Step 3: Write minimal implementation**

```elixir
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

        # Current value from positions
        current_value =
          Enum.reduce(snapshot.positions, zero, fn pos, acc ->
            fx = pos.fx_rate || Decimal.new("1")
            val = pos.value || zero
            Decimal.add(acc, Decimal.mult(val, fx))
          end)

        # Unrealized P&L from positions
        unrealized_pnl =
          Enum.reduce(snapshot.positions, zero, fn pos, acc ->
            pnl = pos.unrealized_pnl || zero
            Decimal.add(acc, pnl)
          end)

        # Get investment summary (net_invested, realized_pnl, dividends, costs)
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
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/dividendsomatic/portfolio/portfolio_validator_test.exs`
Expected: All PASS

**Step 5: Commit**

```bash
git add lib/dividendsomatic/portfolio/portfolio_validator.ex test/dividendsomatic/portfolio/portfolio_validator_test.exs
git commit -m "feat: PortfolioValidator with balance check

- Validates current_value ≈ net_invested + total_return
- 1%/5% tolerance thresholds (pass/warning/fail)
- 6 tests covering pass, warn, fail, edge cases"
```

---

### Task 3: Integrate into mix validate.data

**Files:**
- Modify: `lib/mix/tasks/validate_data.ex`

**Step 6: Write failing test for mix task integration**

No separate test needed — the mix task is tested via the validator itself. Integration is output formatting only.

**Step 7: Add portfolio balance section to mix task**

In `lib/mix/tasks/validate_data.ex`, add after the dividend validation output:

1. Add alias: `alias Dividendsomatic.Portfolio.PortfolioValidator`
2. After the dividend report output (line ~46), add:

```elixir
# Portfolio balance check
portfolio_report = PortfolioValidator.validate()
print_portfolio_balance(portfolio_report)
```

3. Add the formatting function:

```elixir
defp print_portfolio_balance(%{checks: []}) do
  Mix.shell().info("\n=== Portfolio Balance Check ===")
  Mix.shell().info("  No portfolio data available.")
end

defp print_portfolio_balance(%{checks: checks}) do
  Mix.shell().info("\n=== Portfolio Balance Check ===")

  Enum.each(checks, fn check ->
    c = check.components
    sign = if Decimal.negative?(c.total_costs), do: "", else: "-"

    Mix.shell().info("  Net invested:     €#{format_decimal(c.net_invested)}")
    Mix.shell().info("  + Total return:   €#{format_decimal(c.total_return)}")
    Mix.shell().info("    (Realized P&L:   €#{format_decimal(c.realized_pnl)})")
    Mix.shell().info("    (Unrealized P&L: €#{format_decimal(c.unrealized_pnl)})")
    Mix.shell().info("    (Dividends:      €#{format_decimal(c.total_dividends)})")
    Mix.shell().info("    (Costs:         #{sign}€#{format_decimal(c.total_costs)})")
    Mix.shell().info("  = Expected value: €#{format_decimal(check.expected)}")
    Mix.shell().info("  Current value:    €#{format_decimal(check.actual)}")
    Mix.shell().info("  Difference:       €#{format_decimal(check.difference)} (#{check.difference_pct}%)")
    Mix.shell().info("  Status:           #{status_icon(check.status)}")
  end)
end

defp format_decimal(decimal) do
  decimal
  |> Decimal.round(2)
  |> Decimal.to_string()
end

defp status_icon(:pass), do: "✓ PASS (within 1% tolerance)"
defp status_icon(:warning), do: "⚠ WARNING (1-5% difference)"
defp status_icon(:fail), do: "✗ FAIL (>5% difference)"
```

**Step 8: Run full test suite**

Run: `mix test`
Expected: All tests pass (668 + new tests)

**Step 9: Manual verification**

Run: `mix validate.data`
Expected: New "Portfolio Balance Check" section appears in output

**Step 10: Commit**

```bash
git add lib/mix/tasks/validate_data.ex
git commit -m "feat: Integrate portfolio balance check into mix validate.data

- Adds Portfolio Balance Check section to validation output
- Shows all components, expected vs actual, difference %
- Status icons: ✓ PASS / ⚠ WARNING / ✗ FAIL"
```

---

### Task 4: Include in export/compare

**Files:**
- Modify: `lib/mix/tasks/validate_data.ex`

**Step 11: Add portfolio balance to export JSON**

In `serialize_report/1`, add portfolio data so `--export` and `--compare` include the balance check results.

Update `run/1` to pass portfolio_report to export:

```elixir
def run(args) do
  Mix.Task.run("app.start")

  report = DividendValidator.validate()
  portfolio_report = PortfolioValidator.validate()

  # ... existing dividend output ...
  print_portfolio_balance(portfolio_report)

  if "--export" in args, do: export_report(report, portfolio_report)
  if "--compare" in args, do: compare_with_latest(report, portfolio_report)
  if "--suggest" in args, do: print_suggestions()
end
```

Update `serialize_report/2`:

```elixir
defp serialize_report(report, portfolio_report) do
  base = serialize_report(report)
  Map.put(base, :portfolio_balance, serialize_portfolio(portfolio_report))
end

defp serialize_portfolio(%{checks: checks, summary: summary}) do
  %{
    checks: Enum.map(checks, fn check ->
      %{
        name: Atom.to_string(check.name),
        status: Atom.to_string(check.status),
        expected: Decimal.to_string(check.expected),
        actual: Decimal.to_string(check.actual),
        difference: Decimal.to_string(check.difference),
        difference_pct: Decimal.to_string(check.difference_pct)
      }
    end),
    summary: summary
  }
end
```

**Step 12: Run full test suite**

Run: `mix test`
Expected: All pass

**Step 13: Commit**

```bash
git add lib/mix/tasks/validate_data.ex
git commit -m "feat: Include portfolio balance in validate.data export/compare

- Balance check results included in JSON export
- Compare shows portfolio balance changes over time"
```

---

### Task 5: Final verification

**Step 14: Run mix precommit**

Run: `mix precommit`
Expected: compile + format + test all pass

**Step 15: Run mix validate.data**

Run: `mix validate.data`
Expected: Full output with both dividend validation and portfolio balance check

**Step 16: Run mix validate.data --export**

Run: `mix validate.data --export`
Expected: JSON file includes `portfolio_balance` key
