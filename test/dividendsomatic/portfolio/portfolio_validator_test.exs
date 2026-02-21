defmodule Dividendsomatic.Portfolio.PortfolioValidatorTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.{
    CashFlow,
    DividendPayment,
    Instrument,
    MarginEquitySnapshot,
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
      # No margin equity data → margin_mode is false
      assert check.components.margin_mode == false
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
      assert Map.has_key?(check.components, :interest_costs)
      assert Map.has_key?(check.components, :fee_costs)
      assert Map.has_key?(check.components, :total_return)
      assert Map.has_key?(check.components, :position_value)
      assert Map.has_key?(check.components, :cash_balance)
      assert Map.has_key?(check.components, :current_value)
      assert Map.has_key?(check.components, :margin_mode)
    end

    test "should use NLV for current_value in margin mode" do
      # First IBKR Flex snapshot
      {:ok, _first_snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{
          date: ~D[2022-01-04],
          total_value: Decimal.new("200000"),
          total_cost: Decimal.new("190000"),
          source: "ibkr_flex",
          data_quality: "actual"
        })
        |> Repo.insert()

      # Latest snapshot with positions
      {:ok, latest_snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{
          date: ~D[2024-06-15],
          total_value: Decimal.new("105000"),
          total_cost: Decimal.new("95000"),
          source: "ibkr_flex",
          data_quality: "actual"
        })
        |> Repo.insert()

      %Position{}
      |> Position.changeset(%{
        portfolio_snapshot_id: latest_snapshot.id,
        date: ~D[2024-06-15],
        symbol: "TEST",
        name: "Test Stock",
        isin: "US0000000000",
        quantity: Decimal.new("1000"),
        price: Decimal.new("105"),
        value: Decimal.new("105000"),
        cost_basis: Decimal.new("95000"),
        cost_price: Decimal.new("95"),
        currency: "EUR",
        fx_rate: Decimal.new("1"),
        unrealized_pnl: Decimal.new("10000")
      })
      |> Repo.insert!()

      # Margin equity snapshot near start (activates margin mode)
      %MarginEquitySnapshot{}
      |> MarginEquitySnapshot.changeset(%{
        date: ~D[2021-12-31],
        cash_balance: Decimal.new("-100000"),
        net_liquidation_value: Decimal.new("90000"),
        own_equity: Decimal.new("90000"),
        source: "test"
      })
      |> Repo.insert!()

      # Latest margin equity snapshot
      %MarginEquitySnapshot{}
      |> MarginEquitySnapshot.changeset(%{
        date: ~D[2024-06-15],
        cash_balance: Decimal.new("5000"),
        net_liquidation_value: Decimal.new("110000"),
        own_equity: Decimal.new("110000"),
        source: "test"
      })
      |> Repo.insert!()

      result = PortfolioValidator.validate()
      check = hd(result.checks)

      # Margin mode active — uses NLV
      assert check.components.margin_mode == true
      # initial_capital = NLV near start (90000), not cost_basis (190000)
      assert Decimal.equal?(check.components.initial_capital, Decimal.new("90000"))
      # current_value = latest NLV (110000), not position_value (105000)
      assert Decimal.equal?(check.components.current_value, Decimal.new("110000"))
      # position_value still exposed for transparency
      assert Decimal.equal?(check.components.position_value, Decimal.new("105000"))
      assert Decimal.equal?(check.components.cash_balance, Decimal.new("5000"))
    end

    test "should use wider thresholds in margin mode" do
      # First IBKR snapshot
      {:ok, _} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{
          date: ~D[2022-01-04],
          total_value: Decimal.new("200000"),
          total_cost: Decimal.new("190000"),
          source: "ibkr_flex",
          data_quality: "actual"
        })
        |> Repo.insert()

      # Latest snapshot
      {:ok, latest_snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{
          date: ~D[2024-06-15],
          total_value: Decimal.new("100000"),
          total_cost: Decimal.new("90000"),
          source: "ibkr_flex",
          data_quality: "actual"
        })
        |> Repo.insert()

      %Position{}
      |> Position.changeset(%{
        portfolio_snapshot_id: latest_snapshot.id,
        date: ~D[2024-06-15],
        symbol: "TEST",
        name: "Test",
        isin: "US0000000000",
        quantity: Decimal.new("1000"),
        price: Decimal.new("100"),
        value: Decimal.new("100000"),
        cost_basis: Decimal.new("90000"),
        cost_price: Decimal.new("90"),
        currency: "EUR",
        fx_rate: Decimal.new("1"),
        unrealized_pnl: Decimal.new("10000")
      })
      |> Repo.insert!()

      # Margin equity (activates margin mode)
      %MarginEquitySnapshot{}
      |> MarginEquitySnapshot.changeset(%{
        date: ~D[2021-12-31],
        net_liquidation_value: Decimal.new("100000"),
        cash_balance: Decimal.new("-90000"),
        own_equity: Decimal.new("100000"),
        source: "test"
      })
      |> Repo.insert!()

      # Latest NLV has a 10% gap from expected — warning in margin mode, fail in normal
      %MarginEquitySnapshot{}
      |> MarginEquitySnapshot.changeset(%{
        date: ~D[2024-06-15],
        net_liquidation_value: Decimal.new("122000"),
        cash_balance: Decimal.new("5000"),
        own_equity: Decimal.new("122000"),
        source: "test"
      })
      |> Repo.insert!()

      result = PortfolioValidator.validate()
      check = hd(result.checks)

      # 10% gap = warning in margin mode (threshold 5-20%)
      assert check.components.margin_mode == true
      assert check.status == :warning
      assert Decimal.equal?(check.tolerance_pct, Decimal.new("5"))
    end

    test "should split costs into interest and fees" do
      setup_balanced_portfolio(
        deposits: "100000",
        current_value: "110000",
        unrealized_pnl: "10000",
        cost_basis: "100000"
      )

      # Add interest cost
      %CashFlow{}
      |> CashFlow.changeset(%{
        external_id: "test-interest-1",
        flow_type: "interest",
        date: ~D[2024-03-01],
        amount: Decimal.new("-500"),
        currency: "EUR"
      })
      |> Repo.insert!()

      # Add fee cost
      %CashFlow{}
      |> CashFlow.changeset(%{
        external_id: "test-fee-1",
        flow_type: "fee",
        date: ~D[2024-03-01],
        amount: Decimal.new("-100"),
        currency: "EUR"
      })
      |> Repo.insert!()

      result = PortfolioValidator.validate()
      check = hd(result.checks)

      assert Decimal.equal?(check.components.interest_costs, Decimal.new("500"))
      assert Decimal.equal?(check.components.fee_costs, Decimal.new("100"))
      assert Decimal.equal?(check.components.total_costs, Decimal.new("600"))
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

      # No margin equity data → uses cost_basis from first ibkr_flex snapshot
      assert check.components.margin_mode == false
      assert check.status == :pass
      assert Decimal.equal?(check.components.initial_capital, Decimal.new("190000"))
      assert Decimal.equal?(check.components.total_deposits, Decimal.new("50000"))
      assert Decimal.equal?(check.components.net_invested, Decimal.new("240000"))
    end

    test "should EUR-convert unrealized P&L using position fx_rate" do
      {:ok, snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{
          date: ~D[2024-06-15],
          total_value: Decimal.new("100000"),
          source: "test",
          data_quality: "actual"
        })
        |> Repo.insert()

      # USD position: unrealized = 1000 USD, fx_rate = 0.92
      %Position{}
      |> Position.changeset(%{
        portfolio_snapshot_id: snapshot.id,
        date: ~D[2024-06-15],
        symbol: "USD-STOCK",
        name: "USD Stock",
        isin: "US1111111111",
        quantity: Decimal.new("100"),
        price: Decimal.new("500"),
        value: Decimal.new("50000"),
        cost_basis: Decimal.new("49000"),
        cost_price: Decimal.new("490"),
        currency: "USD",
        fx_rate: Decimal.new("0.92"),
        unrealized_pnl: Decimal.new("1000")
      })
      |> Repo.insert!()

      # EUR position: unrealized = 2000 EUR, fx_rate = 1
      %Position{}
      |> Position.changeset(%{
        portfolio_snapshot_id: snapshot.id,
        date: ~D[2024-06-15],
        symbol: "EUR-STOCK",
        name: "EUR Stock",
        isin: "FI2222222222",
        quantity: Decimal.new("100"),
        price: Decimal.new("500"),
        value: Decimal.new("50000"),
        cost_basis: Decimal.new("48000"),
        cost_price: Decimal.new("480"),
        currency: "EUR",
        fx_rate: Decimal.new("1"),
        unrealized_pnl: Decimal.new("2000")
      })
      |> Repo.insert!()

      # Need a deposit to create net_invested
      %CashFlow{}
      |> CashFlow.changeset(%{
        external_id: "test-deposit-fx",
        flow_type: "deposit",
        date: ~D[2024-01-01],
        amount: Decimal.new("90000"),
        currency: "EUR"
      })
      |> Repo.insert!()

      result = PortfolioValidator.validate()
      check = hd(result.checks)

      # unrealized = 1000 * 0.92 + 2000 * 1 = 920 + 2000 = 2920 EUR
      assert Decimal.equal?(check.components.unrealized_pnl, Decimal.new("2920.00"))
    end

    test "should include dividend_payments in total_dividends via direct EUR sum" do
      setup_balanced_portfolio(
        deposits: "100000",
        current_value: "115000",
        unrealized_pnl: "10000",
        cost_basis: "100000"
      )

      # Create instrument for dividend
      {:ok, instrument} =
        %Instrument{}
        |> Instrument.changeset(%{
          name: "Test Corp",
          isin: "US9999999999",
          currency: "EUR"
        })
        |> Repo.insert()

      # EUR dividend with amount_eur
      %DividendPayment{}
      |> DividendPayment.changeset(%{
        external_id: "test-div-eur",
        instrument_id: instrument.id,
        pay_date: ~D[2024-06-01],
        currency: "EUR",
        gross_amount: Decimal.new("3500"),
        net_amount: Decimal.new("3000"),
        amount_eur: Decimal.new("3000"),
        fx_rate: Decimal.new("1"),
        source: "test"
      })
      |> Repo.insert!()

      # USD dividend with EUR conversion
      %DividendPayment{}
      |> DividendPayment.changeset(%{
        external_id: "test-div-usd",
        instrument_id: instrument.id,
        pay_date: ~D[2024-07-01],
        currency: "USD",
        gross_amount: Decimal.new("1200"),
        net_amount: Decimal.new("1000"),
        amount_eur: Decimal.new("920"),
        fx_rate: Decimal.new("0.92"),
        source: "test"
      })
      |> Repo.insert!()

      result = PortfolioValidator.validate()
      check = hd(result.checks)

      # Direct EUR sum: 3000 + 920 = 3920
      assert Decimal.equal?(check.components.total_dividends, Decimal.new("3920"))
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
