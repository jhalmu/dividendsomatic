defmodule Dividendsomatic.Portfolio.PortfolioValidatorTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.{
    CashFlow,
    PortfolioSnapshot,
    PortfolioValidator,
    Position
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

  defp setup_balanced_portfolio(opts) do
    deposits = Keyword.fetch!(opts, :deposits)
    current_value = Keyword.fetch!(opts, :current_value)
    unrealized_pnl = Keyword.fetch!(opts, :unrealized_pnl)
    cost_basis = Keyword.fetch!(opts, :cost_basis)

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
