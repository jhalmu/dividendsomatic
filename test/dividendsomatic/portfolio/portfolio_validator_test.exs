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

      assert Map.has_key?(check.components, :initial_capital)
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

    test "should only count IBKR realized P&L, not other sources" do
      setup_balanced_portfolio(
        deposits: "100000",
        current_value: "110000",
        unrealized_pnl: "10000",
        cost_basis: "100000"
      )

      # IBKR sold position — should be counted
      %SoldPosition{}
      |> SoldPosition.changeset(%{
        symbol: "IBKR-STOCK",
        quantity: Decimal.new("100"),
        purchase_price: Decimal.new("10"),
        purchase_date: ~D[2024-01-15],
        sale_price: Decimal.new("12"),
        sale_date: ~D[2024-03-15],
        currency: "EUR",
        realized_pnl: Decimal.new("200"),
        source: "ibkr"
      })
      |> Repo.insert!()

      # Lynx 9A sold position — should NOT be counted
      %SoldPosition{}
      |> SoldPosition.changeset(%{
        symbol: "LYNX-STOCK",
        quantity: Decimal.new("500"),
        purchase_price: Decimal.new("20"),
        purchase_date: ~D[2023-01-15],
        sale_price: Decimal.new("10"),
        sale_date: ~D[2024-02-15],
        currency: "EUR",
        realized_pnl: Decimal.new("-5000"),
        source: "lynx_9a"
      })
      |> Repo.insert!()

      result = PortfolioValidator.validate()
      check = hd(result.checks)

      # Only IBKR's +200 should be counted, not Lynx's -5000
      assert Decimal.equal?(check.components.realized_pnl, Decimal.new("200"))
    end

    test "should include initial capital from first ibkr_flex snapshot cost basis" do
      # First IBKR Flex snapshot — represents transferred positions
      {:ok, first_snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{
          date: ~D[2022-01-04],
          total_value: Decimal.new("200000"),
          total_cost: Decimal.new("190000"),
          source: "ibkr_flex",
          data_quality: "actual"
        })
        |> Repo.insert()

      %Position{}
      |> Position.changeset(%{
        portfolio_snapshot_id: first_snapshot.id,
        date: ~D[2022-01-04],
        symbol: "OLD",
        name: "Old Stock",
        isin: "US1111111111",
        quantity: Decimal.new("1000"),
        price: Decimal.new("200"),
        value: Decimal.new("200000"),
        cost_basis: Decimal.new("190000"),
        cost_price: Decimal.new("190"),
        currency: "EUR",
        fx_rate: Decimal.new("1"),
        unrealized_pnl: Decimal.new("10000")
      })
      |> Repo.insert!()

      # Latest snapshot — current portfolio
      {:ok, latest_snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{
          date: ~D[2024-06-15],
          total_value: Decimal.new("250000"),
          total_cost: Decimal.new("240000"),
          source: "ibkr_flex",
          data_quality: "actual"
        })
        |> Repo.insert()

      %Position{}
      |> Position.changeset(%{
        portfolio_snapshot_id: latest_snapshot.id,
        date: ~D[2024-06-15],
        symbol: "NEW",
        name: "New Stock",
        isin: "US2222222222",
        quantity: Decimal.new("1000"),
        price: Decimal.new("250"),
        value: Decimal.new("250000"),
        cost_basis: Decimal.new("240000"),
        cost_price: Decimal.new("240"),
        currency: "EUR",
        fx_rate: Decimal.new("1"),
        unrealized_pnl: Decimal.new("10000")
      })
      |> Repo.insert!()

      # Cash deposit of 50k AFTER first snapshot (on top of 190k initial = 240k)
      %CashFlow{}
      |> CashFlow.changeset(%{
        external_id: "test-deposit-after",
        flow_type: "deposit",
        date: ~D[2023-01-01],
        amount: Decimal.new("50000"),
        currency: "EUR",
        fx_rate: Decimal.new("1"),
        amount_eur: Decimal.new("50000"),
        description: "Electronic Fund Transfer"
      })
      |> Repo.insert!()

      # Cash deposit BEFORE first snapshot — should NOT be counted separately
      # (already included in initial_capital cost basis)
      %CashFlow{}
      |> CashFlow.changeset(%{
        external_id: "test-deposit-before",
        flow_type: "deposit",
        date: ~D[2021-06-01],
        amount: Decimal.new("99999"),
        currency: "EUR",
        fx_rate: Decimal.new("1"),
        amount_eur: Decimal.new("99999"),
        description: "Electronic Fund Transfer"
      })
      |> Repo.insert!()

      result = PortfolioValidator.validate()
      check = hd(result.checks)

      # initial_capital = first ibkr_flex snapshot cost basis = 190000
      # deposits after 2022-01-04 = 50000 (the 99999 is before, excluded)
      # net_invested = 190000 + 50000 = 240000
      # total_return = unrealized_pnl(10000) = 10000
      # expected = 240000 + 10000 = 250000
      # actual = 250000
      assert check.status == :pass
      assert Decimal.equal?(check.components.initial_capital, Decimal.new("190000"))
      assert Decimal.equal?(check.components.total_deposits, Decimal.new("50000"))
      assert Decimal.equal?(check.components.net_invested, Decimal.new("240000"))
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
