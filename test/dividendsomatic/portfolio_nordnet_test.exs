defmodule Dividendsomatic.PortfolioNordnetTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio
  alias Dividendsomatic.Portfolio.CashFlow

  describe "costs (from cash_flows)" do
    test "should list costs" do
      insert_cash_flow("interest", ~D[2026-01-06], "-100.50", "EUR")

      assert length(Portfolio.list_costs()) == 1
    end

    test "should list costs by type" do
      insert_cash_flow("interest", ~D[2026-01-06], "-100.50", "EUR")
      insert_cash_flow("fee", ~D[2026-01-10], "-5.00", "EUR")

      interest = Portfolio.list_costs_by_type("interest")
      assert length(interest) == 1
    end

    test "should return costs summary" do
      insert_cash_flow("interest", ~D[2026-01-06], "-100.50", "EUR")
      insert_cash_flow("interest", ~D[2026-02-06], "-90.00", "EUR")

      summary = Portfolio.costs_summary()
      assert summary.count == 2
      # Amounts stored as negative, costs_summary uses ABS
      assert Decimal.equal?(summary.total, Decimal.new("190.50"))
      assert Decimal.equal?(summary.by_type["interest"], Decimal.new("190.50"))
    end

    test "should return total costs by type" do
      insert_cash_flow("interest", ~D[2026-01-06], "-50.00", "EUR")
      insert_cash_flow("fee", ~D[2026-01-10], "-10.00", "EUR")

      by_type = Portfolio.total_costs_by_type()
      assert Decimal.equal?(by_type["interest"], Decimal.new("50.00"))
      assert Decimal.equal?(by_type["fee"], Decimal.new("10.00"))
    end
  end

  describe "broker_coverage/0" do
    test "should return coverage data" do
      coverage = Portfolio.broker_coverage()
      assert Map.has_key?(coverage, :ibkr)
      assert Map.has_key?(coverage, :ibkr_txns)
    end
  end

  describe "stock_gaps/1" do
    test "should return empty list when no data" do
      gaps = Portfolio.stock_gaps()
      assert gaps == []
    end
  end

  defp insert_cash_flow(flow_type, date, amount, currency) do
    %CashFlow{}
    |> CashFlow.changeset(%{
      external_id: "test-cf-#{System.unique_integer([:positive])}",
      flow_type: flow_type,
      date: date,
      amount: Decimal.new(amount),
      currency: currency
    })
    |> Dividendsomatic.Repo.insert!()
  end
end
