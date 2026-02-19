defmodule Dividendsomatic.Portfolio.MarginEquityTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Portfolio
  alias Dividendsomatic.Portfolio.{MarginEquitySnapshot, MarginRates, PortfolioSnapshot}

  describe "MarginEquitySnapshot changeset" do
    test "should require date and source" do
      changeset = MarginEquitySnapshot.changeset(%MarginEquitySnapshot{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).date
      assert "can't be blank" in errors_on(changeset).source
    end

    test "should accept valid snapshot" do
      attrs = %{date: ~D[2026-02-17], source: "ibkr_flex"}
      changeset = MarginEquitySnapshot.changeset(%MarginEquitySnapshot{}, attrs)

      assert changeset.valid?
    end

    test "should accept snapshot with all fields" do
      attrs = %{
        date: ~D[2026-02-17],
        source: "ibkr_flex",
        cash_balance: Decimal.new("-150000"),
        margin_loan: Decimal.new("150000"),
        net_liquidation_value: Decimal.new("310000"),
        own_equity: Decimal.new("86000"),
        metadata: %{"report_type" => "flex"}
      }

      changeset = MarginEquitySnapshot.changeset(%MarginEquitySnapshot{}, attrs)

      assert changeset.valid?
    end

    test "should compute leverage_ratio from net_liquidation_value and own_equity" do
      attrs = %{
        date: ~D[2026-02-17],
        source: "ibkr_flex",
        net_liquidation_value: Decimal.new("310000"),
        own_equity: Decimal.new("86000")
      }

      changeset = MarginEquitySnapshot.changeset(%MarginEquitySnapshot{}, attrs)

      assert changeset.valid?
      leverage = Ecto.Changeset.get_change(changeset, :leverage_ratio)
      assert Decimal.compare(leverage, Decimal.new("3.60")) == :eq
    end

    test "should compute loan_to_value from margin_loan and net_liquidation_value" do
      attrs = %{
        date: ~D[2026-02-17],
        source: "ibkr_flex",
        margin_loan: Decimal.new("150000"),
        net_liquidation_value: Decimal.new("310000"),
        own_equity: Decimal.new("86000")
      }

      changeset = MarginEquitySnapshot.changeset(%MarginEquitySnapshot{}, attrs)

      assert changeset.valid?
      ltv = Ecto.Changeset.get_change(changeset, :loan_to_value)
      # 150000 / 310000 = 0.4839
      assert Decimal.compare(ltv, Decimal.new("0.4839")) == :eq
    end

    test "should persist and enforce unique date" do
      attrs = %{date: ~D[2026-02-17], source: "ibkr_flex", own_equity: Decimal.new("86000")}

      {:ok, _} =
        %MarginEquitySnapshot{}
        |> MarginEquitySnapshot.changeset(attrs)
        |> Repo.insert()

      assert {:error, changeset} =
               %MarginEquitySnapshot{}
               |> MarginEquitySnapshot.changeset(attrs)
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).date
    end
  end

  describe "MarginRates" do
    test "should return correct spread for small balance" do
      assert MarginRates.spread_for_balance(Decimal.new("50000")) == Decimal.new("1.5")
    end

    test "should return correct spread for medium balance" do
      assert MarginRates.spread_for_balance(Decimal.new("200000")) == Decimal.new("1.0")
    end

    test "should return correct spread at tier boundary" do
      assert MarginRates.spread_for_balance(Decimal.new("100000")) == Decimal.new("1.5")
    end

    test "should return benchmark rates for known currencies" do
      rates = MarginRates.benchmark_rates()
      assert Map.has_key?(rates, "EUR")
      assert Map.has_key?(rates, "USD")
      assert Map.has_key?(rates, "SEK")
    end

    test "should calculate effective rate for EUR" do
      rate = MarginRates.effective_rate("EUR", Decimal.new("150000"))
      bm = MarginRates.benchmark_rate("EUR")
      # 150K is in tier 2 (100K-1M), spread = 1.0%
      expected = Decimal.add(bm, Decimal.new("1.0"))
      assert Decimal.compare(rate, expected) == :eq
    end

    test "should calculate expected annual cost" do
      cost = MarginRates.expected_annual_cost("EUR", Decimal.new("150000"))
      assert Decimal.compare(cost, Decimal.new("0")) == :gt
    end

    test "should return complete rate summary" do
      summary = MarginRates.rate_summary("EUR", Decimal.new("150000"))

      assert summary.currency == "EUR"
      assert Decimal.compare(summary.loan_amount, Decimal.new("150000")) == :eq
      assert Decimal.compare(summary.annual_cost, Decimal.new("0")) == :gt
      assert Decimal.compare(summary.monthly_cost, Decimal.new("0")) == :gt
    end

    test "should handle negative loan amounts (absolute value)" do
      cost_neg = MarginRates.expected_annual_cost("EUR", Decimal.new("-150000"))
      cost_pos = MarginRates.expected_annual_cost("EUR", Decimal.new("150000"))
      assert Decimal.compare(cost_neg, cost_pos) == :eq
    end
  end

  describe "Portfolio margin equity functions" do
    test "should create margin equity snapshot" do
      attrs = %{
        date: ~D[2026-02-17],
        source: "ibkr_flex",
        cash_balance: Decimal.new("-150000"),
        margin_loan: Decimal.new("150000"),
        net_liquidation_value: Decimal.new("310000"),
        own_equity: Decimal.new("86000")
      }

      assert {:ok, snapshot} = Portfolio.create_margin_equity_snapshot(attrs)
      assert snapshot.date == ~D[2026-02-17]
      assert Decimal.compare(snapshot.own_equity, Decimal.new("86000")) == :eq
    end

    test "should get latest margin equity" do
      Portfolio.create_margin_equity_snapshot(%{
        date: ~D[2026-02-16],
        source: "ibkr_flex",
        own_equity: Decimal.new("85000")
      })

      Portfolio.create_margin_equity_snapshot(%{
        date: ~D[2026-02-17],
        source: "ibkr_flex",
        own_equity: Decimal.new("86000")
      })

      latest = Portfolio.get_latest_margin_equity()
      assert latest.date == ~D[2026-02-17]
    end

    test "should get margin equity for specific date" do
      Portfolio.create_margin_equity_snapshot(%{
        date: ~D[2026-02-17],
        source: "ibkr_flex",
        own_equity: Decimal.new("86000")
      })

      result = Portfolio.get_margin_equity_for_date(~D[2026-02-17])
      assert result.date == ~D[2026-02-17]
    end

    test "should return nil for missing date" do
      assert is_nil(Portfolio.get_margin_equity_for_date(~D[2099-01-01]))
    end

    test "should upsert margin equity snapshot" do
      attrs = %{date: ~D[2026-02-17], source: "ibkr_flex", own_equity: Decimal.new("86000")}
      {:ok, _} = Portfolio.upsert_margin_equity_snapshot(attrs)

      updated_attrs = %{
        date: ~D[2026-02-17],
        source: "ibkr_flex",
        own_equity: Decimal.new("88000")
      }

      {:ok, updated} = Portfolio.upsert_margin_equity_snapshot(updated_attrs)

      assert Decimal.compare(updated.own_equity, Decimal.new("88000")) == :eq
      assert length(Portfolio.list_margin_equity_snapshots()) == 1
    end

    test "should return margin equity summary without data" do
      summary = Portfolio.margin_equity_summary()
      assert summary.has_data == false
      assert Map.has_key?(summary, :actual_interest_total)
    end

    test "should return margin equity summary with data" do
      Portfolio.create_margin_equity_snapshot(%{
        date: ~D[2026-02-17],
        source: "ibkr_flex",
        cash_balance: Decimal.new("-150000"),
        margin_loan: Decimal.new("150000"),
        net_liquidation_value: Decimal.new("310000"),
        own_equity: Decimal.new("86000")
      })

      summary = Portfolio.margin_equity_summary()
      assert summary.has_data == true
      assert Decimal.compare(summary.own_equity, Decimal.new("86000")) == :eq
      assert Decimal.compare(summary.margin_loan, Decimal.new("150000")) == :eq
      assert Map.has_key?(summary, :expected_rate)
      assert Map.has_key?(summary, :payback)
    end
  end

  describe "compute_payback" do
    test "should return zero payback for nil equity" do
      result = Portfolio.compute_payback(nil)
      assert Decimal.compare(result.payback_pct, Decimal.new("0")) == :eq
    end

    test "should return zero payback for zero equity" do
      result = Portfolio.compute_payback(Decimal.new("0"))
      assert Decimal.compare(result.payback_pct, Decimal.new("0")) == :eq
    end

    test "should compute payback with positive equity" do
      # Create a snapshot so the calculation has a date range
      {:ok, _} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{
          date: ~D[2025-01-01],
          source: "test"
        })
        |> Repo.insert()

      result = Portfolio.compute_payback(Decimal.new("86000"))
      assert Map.has_key?(result, :own_equity)
      assert Map.has_key?(result, :cumulative_earnings)
      assert Map.has_key?(result, :payback_pct)
      assert Map.has_key?(result, :projected_payback_date)
    end
  end
end
