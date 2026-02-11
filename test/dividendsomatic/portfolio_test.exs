defmodule Dividendsomatic.PortfolioTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Portfolio

  describe "portfolio snapshots" do
    @valid_csv """
    "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
    "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
    "2026-01-28","EUR","TELIA1","TELIA CO AB","COMMON","10000","3.858","38580","3.5871187","35871.187","3.5871187","16.34","2708.813","FWB","STK","1","SE0000667925","BBG000GJ9377"
    """

    @valid_date ~D[2026-01-28]

    test "create_snapshot_from_csv/2 creates snapshot with holdings" do
      assert {:ok, snapshot} = Portfolio.create_snapshot_from_csv(@valid_csv, @valid_date)
      assert snapshot.report_date == @valid_date
      assert length(Repo.preload(snapshot, :holdings).holdings) == 2
    end

    test "get_latest_snapshot/0 returns most recent snapshot" do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-27])
      {:ok, latest} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      result = Portfolio.get_latest_snapshot()
      assert result.report_date == latest.report_date
    end

    test "get_snapshot_by_date/1 finds specific snapshot" do
      {:ok, snapshot} = Portfolio.create_snapshot_from_csv(@valid_csv, @valid_date)

      result = Portfolio.get_snapshot_by_date(@valid_date)
      assert result.id == snapshot.id
    end

    test "get_previous_snapshot/1 returns earlier snapshot" do
      {:ok, earlier} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-27])
      {:ok, _later} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      result = Portfolio.get_previous_snapshot(~D[2026-01-28])
      assert result.id == earlier.id
    end

    test "get_next_snapshot/1 returns later snapshot" do
      {:ok, _earlier} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-27])
      {:ok, later} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      result = Portfolio.get_next_snapshot(~D[2026-01-27])
      assert result.id == later.id
    end

    test "get_previous_snapshot/1 returns nil when no earlier snapshot" do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      result = Portfolio.get_previous_snapshot(~D[2026-01-28])
      assert is_nil(result)
    end

    test "get_next_snapshot/1 returns nil when no later snapshot" do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      result = Portfolio.get_next_snapshot(~D[2026-01-28])
      assert is_nil(result)
    end
  end

  describe "holdings" do
    @valid_csv """
    "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
    "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
    """

    test "holdings have correct decimal values" do
      {:ok, snapshot} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])
      [holding] = Repo.preload(snapshot, :holdings).holdings

      assert Decimal.equal?(holding.quantity, Decimal.new("1000"))
      assert Decimal.equal?(holding.mark_price, Decimal.new("21"))
      assert Decimal.equal?(holding.position_value, Decimal.new("21000"))
      assert Decimal.equal?(holding.fifo_pnl_unrealized, Decimal.new("2735.41"))
    end

    test "holdings have correct string values" do
      {:ok, snapshot} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])
      [holding] = Repo.preload(snapshot, :holdings).holdings

      assert holding.symbol == "KESKOB"
      assert holding.description == "KESKO OYJ-B SHS"
      assert holding.currency_primary == "EUR"
      assert holding.asset_class == "STK"
    end
  end

  describe "chart data" do
    @valid_csv """
    "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
    "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
    """

    test "get_all_chart_data/0 returns data points with date and value" do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-27])
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      chart_data = Portfolio.get_all_chart_data()

      assert length(chart_data) == 2
      [first | _] = chart_data
      assert Map.has_key?(first, :date)
      assert Map.has_key?(first, :value)
      assert Map.has_key?(first, :value_float)
    end

    test "get_chart_data/1 respects limit" do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-26])
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-27])
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      chart_data = Portfolio.get_chart_data(2)
      assert length(chart_data) == 2
    end

    test "get_growth_stats/0 returns first/last comparison" do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-27])
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      stats = Portfolio.get_growth_stats()

      assert stats.first_date == ~D[2026-01-27]
      assert stats.latest_date == ~D[2026-01-28]
      assert %Decimal{} = stats.first_value
      assert %Decimal{} = stats.absolute_change
    end

    test "count_snapshots/0 returns correct count" do
      assert Portfolio.count_snapshots() == 0

      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])
      assert Portfolio.count_snapshots() == 1
    end

    test "get_snapshot_position/1 returns correct position" do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-27])
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      assert Portfolio.get_snapshot_position(~D[2026-01-27]) == 1
      assert Portfolio.get_snapshot_position(~D[2026-01-28]) == 2
    end
  end

  describe "dividends" do
    test "create_dividend/1 creates a dividend record" do
      attrs = %{
        symbol: "KESKOB",
        ex_date: ~D[2026-01-15],
        pay_date: ~D[2026-02-01],
        amount: Decimal.new("0.50"),
        currency: "EUR"
      }

      assert {:ok, dividend} = Portfolio.create_dividend(attrs)
      assert dividend.symbol == "KESKOB"
      assert Decimal.equal?(dividend.amount, Decimal.new("0.50"))
    end

    test "list_dividends_this_year/0 returns current year dividends" do
      today = Date.utc_today()

      {:ok, _} =
        Portfolio.create_dividend(%{
          symbol: "KESKOB",
          ex_date: Date.new!(today.year, 1, 15),
          amount: Decimal.new("1.00"),
          currency: "EUR"
        })

      dividends = Portfolio.list_dividends_this_year()
      assert length(dividends) == 1
    end

    test "total_dividends_this_year/0 sums dividend income (per-share * qty * fx)" do
      today = Date.utc_today()

      # Create a snapshot with holdings so income can be calculated
      {:ok, snapshot} =
        %Portfolio.PortfolioSnapshot{}
        |> Portfolio.PortfolioSnapshot.changeset(%{report_date: Date.new!(today.year, 1, 10)})
        |> Dividendsomatic.Repo.insert()

      # KESKOB: 100 shares, fx 1.0 (EUR)
      insert_test_holding(snapshot.id, Date.new!(today.year, 1, 10), "KESKOB", 100, "1")
      # TELIA1: 200 shares, fx 1.0 (EUR)
      insert_test_holding(snapshot.id, Date.new!(today.year, 1, 10), "TELIA1", 200, "1")

      {:ok, _} =
        Portfolio.create_dividend(%{
          symbol: "KESKOB",
          ex_date: Date.new!(today.year, 1, 15),
          amount: Decimal.new("1.00"),
          currency: "EUR"
        })

      {:ok, _} =
        Portfolio.create_dividend(%{
          symbol: "TELIA1",
          ex_date: Date.new!(today.year, 1, 20),
          amount: Decimal.new("2.00"),
          currency: "EUR"
        })

      # KESKOB: 1.00 * 100 * 1.0 = 100, TELIA1: 2.00 * 200 * 1.0 = 400
      total = Portfolio.total_dividends_this_year()
      assert Decimal.equal?(total, Decimal.new("500"))
    end
  end

  describe "sold positions (what-if)" do
    test "create_sold_position/1 creates a sold position record" do
      attrs = %{
        symbol: "AAPL",
        quantity: Decimal.new("100"),
        purchase_price: Decimal.new("150.00"),
        purchase_date: ~D[2025-01-01],
        sale_price: Decimal.new("175.00"),
        sale_date: ~D[2026-01-15]
      }

      assert {:ok, sold} = Portfolio.create_sold_position(attrs)
      assert sold.symbol == "AAPL"
      # 100 * (175 - 150) = 2500
      assert Decimal.equal?(sold.realized_pnl, Decimal.new("2500.00"))
    end

    test "total_realized_pnl/0 sums all realized P&L" do
      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "AAPL",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("100.00"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("150.00"),
          sale_date: ~D[2026-01-15]
        })

      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "MSFT",
          quantity: Decimal.new("50"),
          purchase_price: Decimal.new("200.00"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("250.00"),
          sale_date: ~D[2026-01-15]
        })

      total = Portfolio.total_realized_pnl()
      # AAPL: 100 * 50 = 5000, MSFT: 50 * 50 = 2500
      assert Decimal.equal?(total, Decimal.new("7500.00"))
    end

    test "what_if_value/1 calculates hypothetical value at current prices" do
      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "AAPL",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("100.00"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("150.00"),
          sale_date: ~D[2026-01-15]
        })

      # What if current price is $200?
      current_prices = %{"AAPL" => Decimal.new("200.00")}
      value = Portfolio.what_if_value(current_prices)

      # 100 shares * $200 = $20,000
      assert Decimal.equal?(value, Decimal.new("20000.00"))
    end

    test "what_if_opportunity_cost/1 calculates selling decision quality" do
      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "AAPL",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("100.00"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("150.00"),
          sale_date: ~D[2026-01-15]
        })

      # If current price is $200, selling at $150 was a bad decision
      current_prices = %{"AAPL" => Decimal.new("200.00")}
      opportunity = Portfolio.what_if_opportunity_cost(current_prices)

      # Sale proceeds: 100 * 150 = 15000
      # Current value: 100 * 200 = 20000
      # Opportunity cost: 15000 - 20000 = -5000 (bad decision)
      assert Decimal.equal?(opportunity, Decimal.new("-5000.00"))
    end
  end

  defp insert_test_holding(snapshot_id, report_date, symbol, qty, fx_rate) do
    %Portfolio.Holding{}
    |> Portfolio.Holding.changeset(%{
      portfolio_snapshot_id: snapshot_id,
      report_date: report_date,
      symbol: symbol,
      currency_primary: "EUR",
      quantity: qty,
      mark_price: "10",
      position_value: "1000",
      cost_basis_price: "10",
      cost_basis_money: "1000",
      percent_of_nav: "50",
      listing_exchange: "HEX",
      asset_class: "STK",
      fx_rate_to_base: fx_rate
    })
    |> Dividendsomatic.Repo.insert!()
  end
end
