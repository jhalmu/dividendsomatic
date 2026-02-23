defmodule Dividendsomatic.PortfolioTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Portfolio
  alias Dividendsomatic.Portfolio.{DividendPayment, Instrument, InstrumentAlias}

  describe "portfolio snapshots" do
    @valid_csv """
    "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
    "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
    "2026-01-28","EUR","TELIA1","TELIA CO AB","COMMON","10000","3.858","38580","3.5871187","35871.187","3.5871187","16.34","2708.813","FWB","STK","1","SE0000667925","BBG000GJ9377"
    """

    @valid_date ~D[2026-01-28]

    test "create_snapshot_from_csv/2 creates snapshot with positions" do
      assert {:ok, snapshot} = Portfolio.create_snapshot_from_csv(@valid_csv, @valid_date)
      assert snapshot.date == @valid_date
      assert length(Repo.preload(snapshot, :positions).positions) == 2
    end

    test "get_latest_snapshot/0 returns most recent snapshot" do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-27])
      {:ok, latest} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      result = Portfolio.get_latest_snapshot()
      assert result.date == latest.date
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

  describe "positions" do
    @valid_csv """
    "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
    "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
    """

    test "positions have correct decimal values" do
      {:ok, snapshot} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])
      [position] = Repo.preload(snapshot, :positions).positions

      assert Decimal.equal?(position.quantity, Decimal.new("1000"))
      assert Decimal.equal?(position.price, Decimal.new("21"))
      assert Decimal.equal?(position.value, Decimal.new("21000"))
      assert Decimal.equal?(position.unrealized_pnl, Decimal.new("2735.41"))
    end

    test "positions have correct string values" do
      {:ok, snapshot} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])
      [position] = Repo.preload(snapshot, :positions).positions

      assert position.symbol == "KESKOB"
      assert position.name == "KESKO OYJ-B SHS"
      assert position.currency == "EUR"
      assert position.asset_class == "STK"
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
    test "list_dividends_this_year/0 returns current year dividends" do
      today = Date.utc_today()
      insert_test_dividend("KESKOB", "FI0009000202", Date.new!(today.year, 1, 15), "100", "EUR")

      dividends = Portfolio.list_dividends_this_year()
      assert length(dividends) == 1
    end

    test "total_dividends_this_year/0 sums dividend net amounts converted to EUR" do
      today = Date.utc_today()

      # Create a snapshot with holdings for FX rate lookup
      {:ok, snapshot} =
        %Portfolio.PortfolioSnapshot{}
        |> Portfolio.PortfolioSnapshot.changeset(%{
          date: Date.new!(today.year, 1, 10),
          source: "test"
        })
        |> Dividendsomatic.Repo.insert()

      insert_test_holding(snapshot.id, Date.new!(today.year, 1, 10), "KESKOB", 100, "1")
      insert_test_holding(snapshot.id, Date.new!(today.year, 1, 10), "TELIA1", 200, "1")

      # EUR dividends: net_amount is already EUR value
      insert_test_dividend("KESKOB", "FI0009000202", Date.new!(today.year, 1, 15), "100", "EUR")
      insert_test_dividend("TELIA1", "SE0000667925", Date.new!(today.year, 1, 20), "400", "EUR")

      # 100 + 400 = 500
      total = Portfolio.total_dividends_this_year()
      assert Decimal.equal?(total, Decimal.new("500"))
    end
  end

  describe "list_dividends_with_income/0" do
    test "should return enriched records with computed income" do
      today = Date.utc_today()

      {:ok, snapshot} =
        %Portfolio.PortfolioSnapshot{}
        |> Portfolio.PortfolioSnapshot.changeset(%{
          date: Date.new!(today.year, 1, 10),
          source: "test"
        })
        |> Dividendsomatic.Repo.insert()

      insert_test_holding(snapshot.id, Date.new!(today.year, 1, 10), "KESKOB", 100, "1")

      # With dividend_payments, net_amount is the total (not per-share)
      insert_test_dividend("KESKOB", "FI0009000202", Date.new!(today.year, 1, 15), "50", "EUR")

      [entry] = Portfolio.list_dividends_with_income()
      assert entry.dividend.symbol == "KESKOB"
      # EUR dividend: net_amount * 1.0 = 50
      assert Decimal.equal?(entry.income, Decimal.new("50"))
    end

    test "should exclude dividends with no matching holdings" do
      today = Date.utc_today()

      # Non-EUR dividend with no position → fx_rate unknown → income = 0 → filtered out
      insert_test_dividend("ORPHAN", "XX0000000000", Date.new!(today.year, 1, 15), "100", "USD")

      assert Portfolio.list_dividends_with_income() == []
    end

    test "should apply FX rate to income calculation" do
      today = Date.utc_today()

      {:ok, snapshot} =
        %Portfolio.PortfolioSnapshot{}
        |> Portfolio.PortfolioSnapshot.changeset(%{
          date: Date.new!(today.year, 1, 10),
          source: "test"
        })
        |> Dividendsomatic.Repo.insert()

      insert_test_holding(snapshot.id, Date.new!(today.year, 1, 10), "AAPL", 50, "0.92", "USD")

      # USD dividend: net_amount = 50 USD (total)
      insert_test_dividend("AAPL", "US0378331005", Date.new!(today.year, 1, 15), "50", "USD")

      [entry] = Portfolio.list_dividends_with_income()
      # 50 * 0.92 = 46.00
      assert Decimal.equal?(entry.income, Decimal.new("46.00"))
    end

    test "should apply fx_rate from payment when present" do
      today = Date.utc_today()

      # SEK dividend with explicit fx_rate on the payment
      {instrument, _alias} = get_or_create_instrument("TELIA1", "SE0000667925")

      %DividendPayment{}
      |> DividendPayment.changeset(%{
        external_id: "test-fx-#{System.unique_integer([:positive])}",
        instrument_id: instrument.id,
        pay_date: Date.new!(today.year, 1, 15),
        gross_amount: Decimal.new("400"),
        net_amount: Decimal.new("400"),
        currency: "SEK",
        fx_rate: Decimal.new("0.094")
      })
      |> Repo.insert!()

      [entry] = Portfolio.list_dividends_with_income()
      assert entry.dividend.symbol == "TELIA1"
      # 400 * 0.094 = 37.600
      assert Decimal.equal?(entry.income, Decimal.new("37.600"))
    end

    test "should treat EUR dividends as base currency" do
      today = Date.utc_today()

      insert_test_dividend("KESKOB", "FI0009000202", Date.new!(today.year, 1, 15), "150", "EUR")

      [entry] = Portfolio.list_dividends_with_income()
      assert entry.dividend.symbol == "KESKOB"
      # EUR: 150 * 1 = 150
      assert Decimal.equal?(entry.income, Decimal.new("150"))
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

    test "create_sold_position/1 should set realized_pnl_eur for EUR positions" do
      {:ok, sold} =
        Portfolio.create_sold_position(%{
          symbol: "KESKOB",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("18.00"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("21.00"),
          sale_date: ~D[2026-01-15],
          currency: "EUR"
        })

      assert Decimal.equal?(sold.realized_pnl_eur, Decimal.new("300.00"))
      assert Decimal.equal?(sold.exchange_rate_to_eur, Decimal.new("1"))
    end

    test "create_sold_position/1 should not set realized_pnl_eur for non-EUR positions" do
      {:ok, sold} =
        Portfolio.create_sold_position(%{
          symbol: "8031",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("5000"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("6000"),
          sale_date: ~D[2026-01-15],
          currency: "JPY"
        })

      assert is_nil(sold.realized_pnl_eur)
    end

    test "create_sold_position/1 should not overwrite explicit realized_pnl_eur" do
      {:ok, sold} =
        Portfolio.create_sold_position(%{
          symbol: "KESKOB",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("18.00"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("21.00"),
          sale_date: ~D[2026-01-15],
          currency: "EUR",
          realized_pnl_eur: Decimal.new("999.99")
        })

      assert Decimal.equal?(sold.realized_pnl_eur, Decimal.new("999.99"))
    end

    test "total_realized_pnl/0 should prefer realized_pnl_eur over realized_pnl" do
      # EUR position: realized_pnl_eur auto-set
      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "AAPL",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("100.00"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("150.00"),
          sale_date: ~D[2026-01-15]
        })

      # Non-EUR position with explicit realized_pnl_eur (as if backfilled)
      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "8031",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("5000"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("6000"),
          sale_date: ~D[2026-01-15],
          currency: "JPY",
          realized_pnl_eur: Decimal.new("600.00"),
          exchange_rate_to_eur: Decimal.new("166.67")
        })

      total = Portfolio.total_realized_pnl()
      # AAPL: 5000.00 (EUR), 8031: 600.00 (converted)
      assert Decimal.equal?(total, Decimal.new("5600.00"))
    end

    test "total_realized_pnl/0 should fall back to realized_pnl when pnl_eur is nil" do
      # Non-EUR position without conversion (e.g. backfill not run)
      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "8031",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("5000"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("6000"),
          sale_date: ~D[2026-01-15],
          currency: "JPY"
        })

      total = Portfolio.total_realized_pnl()
      # Falls back to realized_pnl = 100000 JPY (raw, unconverted)
      assert Decimal.equal?(total, Decimal.new("100000.00"))
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

  describe "realized_pnl_summary/1 EUR conversion" do
    test "should set has_unconverted to false when all positions are EUR" do
      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "KESKOB",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("18.00"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("21.00"),
          sale_date: ~D[2026-01-15],
          currency: "EUR"
        })

      summary = Portfolio.realized_pnl_summary()
      refute summary.has_unconverted
    end

    test "should set has_unconverted to true when non-EUR positions lack pnl_eur" do
      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "8031",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("5000"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("6000"),
          sale_date: ~D[2026-01-15],
          currency: "JPY"
        })

      summary = Portfolio.realized_pnl_summary()
      assert summary.has_unconverted
    end

    test "should set has_unconverted to false when non-EUR positions have pnl_eur" do
      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "8031",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("5000"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("6000"),
          sale_date: ~D[2026-01-15],
          currency: "JPY",
          realized_pnl_eur: Decimal.new("600.00"),
          exchange_rate_to_eur: Decimal.new("166.67")
        })

      summary = Portfolio.realized_pnl_summary()
      refute summary.has_unconverted
    end

    test "should use realized_pnl_eur in grouped totals" do
      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "8031",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("5000"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("6000"),
          sale_date: ~D[2026-01-15],
          currency: "JPY",
          realized_pnl_eur: Decimal.new("600.00"),
          exchange_rate_to_eur: Decimal.new("166.67")
        })

      summary = Portfolio.realized_pnl_summary()
      # Should use pnl_eur (600) not realized_pnl (100000)
      assert Decimal.equal?(summary.total_pnl, Decimal.new("600.00"))
    end
  end

  describe "per-symbol dividend EUR conversion" do
    test "should EUR-convert projected_annual using dividend fx_rate, not position fx_rate" do
      today = Date.utc_today()

      # Position is EUR-listed (like TELIA on Frankfurt), fx_rate = 1
      position = %Portfolio.Position{
        symbol: "TESTSEK",
        currency: "EUR",
        fx_rate: Decimal.new("1"),
        quantity: Decimal.new("1000"),
        cost_price: Decimal.new("4.00"),
        price: Decimal.new("4.00"),
        value: Decimal.new("4000")
      }

      # Insert a SEK dividend with explicit fx_rate (SEK→EUR conversion)
      insert_test_dividend(
        "TESTSEK",
        "SE0000000001",
        Date.new!(today.year, 1, 15),
        "200",
        "SEK",
        fx_rate: Decimal.new("0.09"),
        per_share: Decimal.new("2.00")
      )

      result = Portfolio.compute_dividend_dashboard(today.year, nil, [position])

      per_sym = result.per_symbol["TESTSEK"]
      assert per_sym != nil

      # annual_per_share should be the per_share value (2.00) since it's gross_rate via adapt
      # projected_annual = annual_per_share * qty * div_fx_rate = per_share * 1000 * 0.09
      # NOT per_share * 1000 * 1 (which would be the wrong pos.fx_rate)
      projected = per_sym.projected_annual

      # With div_fx_rate=0.09: projected should be much less than with pos.fx_rate=1
      # The exact value depends on per_share_amount calculation, but it should use 0.09
      assert Decimal.compare(projected, Decimal.new("500")) == :lt,
             "Expected projected_annual < 500 (EUR-converted), got #{projected}"

      assert Decimal.compare(projected, Decimal.new("0")) == :gt,
             "Expected projected_annual > 0, got #{projected}"
    end
  end

  describe "yield FX consistency" do
    test "should ignore FX for same-currency yield (USD/USD, nil div_fx_rate)" do
      today = Date.utc_today()

      # USD stock with fx_rate to EUR = 0.85
      position = %Portfolio.Position{
        symbol: "TESTUSD",
        currency: "USD",
        fx_rate: Decimal.new("0.85"),
        quantity: Decimal.new("100"),
        cost_price: Decimal.new("12.00"),
        price: Decimal.new("15.00"),
        value: Decimal.new("1500")
      }

      # USD dividend with NO fx_rate — this is the exact bug scenario.
      # Before fix, div_fx defaulted to 1.0 instead of pos.fx_rate,
      # inflating yield by ~17% for all USD stocks.
      insert_test_dividend(
        "TESTUSD",
        "US0000000001",
        Date.new!(today.year, 1, 15),
        "200",
        "USD",
        per_share: Decimal.new("2.00")
      )

      result = Portfolio.compute_dividend_dashboard(today.year, nil, [position])
      per_sym = result.per_symbol["TESTUSD"]
      assert per_sym != nil

      # yield = (annual_per_share × div_fx) / (price × pos_fx) × 100
      # div_fx falls back to pos.fx_rate (0.85), so FX cancels out:
      # (2.00 × 0.85) / (15.00 × 0.85) × 100 = 2.00/15.00 × 100 = 13.33
      assert Decimal.equal?(per_sym.current_yield, Decimal.new("13.33")),
             "Expected current_yield 13.33%, got #{per_sym.current_yield}"

      # (2.00 × 0.85) / (12.00 × 0.85) × 100 = 2.00/12.00 × 100 = 16.67
      assert Decimal.equal?(per_sym.yield_on_cost, Decimal.new("16.67")),
             "Expected yield_on_cost 16.67%, got #{per_sym.yield_on_cost}"
    end

    test "should use div_fx_rate for cross-currency yield (SEK dividend, EUR position)" do
      today = Date.utc_today()

      # EUR-listed position (like TELIA on Frankfurt)
      position = %Portfolio.Position{
        symbol: "TESTCROSS",
        currency: "EUR",
        fx_rate: Decimal.new("1.0"),
        quantity: Decimal.new("1000"),
        cost_price: Decimal.new("3.80"),
        price: Decimal.new("4.20"),
        value: Decimal.new("4200")
      }

      # SEK dividend with explicit fx_rate (SEK→EUR = 0.09)
      insert_test_dividend(
        "TESTCROSS",
        "SE0000000002",
        Date.new!(today.year, 1, 15),
        "200",
        "SEK",
        fx_rate: Decimal.new("0.09"),
        per_share: Decimal.new("2.00")
      )

      result = Portfolio.compute_dividend_dashboard(today.year, nil, [position])
      per_sym = result.per_symbol["TESTCROSS"]
      assert per_sym != nil

      # yield = (2.00 × 0.09) / (4.20 × 1.0) × 100 = 0.18/4.20 × 100 = 4.29
      assert Decimal.equal?(per_sym.current_yield, Decimal.new("4.29")),
             "Expected current_yield 4.29%, got #{per_sym.current_yield}"

      # yield_on_cost = (2.00 × 0.09) / (3.80 × 1.0) × 100 = 0.18/3.80 × 100 = 4.74
      assert Decimal.equal?(per_sym.yield_on_cost, Decimal.new("4.74")),
             "Expected yield_on_cost 4.74%, got #{per_sym.yield_on_cost}"
    end

    test "should keep yield and projected_annual consistent under FX fallback" do
      today = Date.utc_today()

      # USD stock — div_fx_rate will be nil, so both yield and projected_annual
      # must use the same fallback (pos.fx_rate). If they diverge, yields are wrong.
      position = %Portfolio.Position{
        symbol: "TESTCONS",
        currency: "USD",
        fx_rate: Decimal.new("0.85"),
        quantity: Decimal.new("100"),
        cost_price: Decimal.new("8.00"),
        price: Decimal.new("10.00"),
        value: Decimal.new("1000")
      }

      insert_test_dividend(
        "TESTCONS",
        "US0000000002",
        Date.new!(today.year, 1, 15),
        "120",
        "USD",
        per_share: Decimal.new("1.20")
      )

      result = Portfolio.compute_dividend_dashboard(today.year, nil, [position])
      per_sym = result.per_symbol["TESTCONS"]
      assert per_sym != nil

      # Invariant: projected_annual / (price × qty × pos_fx) ≈ current_yield / 100
      # This ensures yield and projected_annual use the same FX logic.
      pos_fx = position.fx_rate
      position_value = position.price |> Decimal.mult(position.quantity) |> Decimal.mult(pos_fx)

      yield_from_projected =
        per_sym.projected_annual
        |> Decimal.div(position_value)
        |> Decimal.round(4)

      yield_from_current =
        per_sym.current_yield
        |> Decimal.div(Decimal.new("100"))
        |> Decimal.round(4)

      assert Decimal.equal?(yield_from_projected, yield_from_current),
             "Yield mismatch: projected gives #{yield_from_projected}, " <>
               "current_yield gives #{yield_from_current}"
    end
  end

  describe "PIL dedup yield consistency" do
    test "should not double-count PIL/withholding split records in yield computation" do
      today = Date.utc_today()

      # Simulates TCPC-like scenario: quarterly BDC paying $0.25/quarter
      # with PIL split creating 2 records per pay date
      position = %Portfolio.Position{
        symbol: "TESTPIL",
        currency: "USD",
        fx_rate: Decimal.new("0.85"),
        quantity: Decimal.new("1000"),
        cost_price: Decimal.new("5.00"),
        price: Decimal.new("5.00"),
        value: Decimal.new("5000")
      }

      # Two pay dates, each with 2 records (PIL + withholding adjustment)
      for offset <- [-30, -120] do
        pay_date = Date.add(today, offset)

        # Main PIL payment
        insert_test_dividend("TESTPIL", "US0000PIL001", pay_date, "200", "USD",
          per_share: Decimal.new("0.25"),
          fx_rate: Decimal.new("0.85")
        )

        # Withholding tax adjustment (same per_share, negative net)
        insert_test_dividend("TESTPIL", "US0000PIL001", pay_date, "-30", "USD",
          per_share: Decimal.new("0.25"),
          fx_rate: Decimal.new("0.85")
        )
      end

      result = Portfolio.compute_dividend_dashboard(today.year, nil, [position])
      per_sym = result.per_symbol["TESTPIL"]
      assert per_sym != nil

      # Without dedup: 4 records × $0.25 = $1.00 TTM sum (wrong — 2 dates counted as 4 payments)
      # With dedup: 2 unique (date, $0.25) pairs → TTM sum $0.50, extrapolate quarterly: $0.50/2 × 4 = $1.00
      # yield = (1.00 × 0.85) / (5.00 × 0.85) × 100 = 20.00%
      # The key assertion: yield should NOT be ~40% (which would happen without dedup)
      assert Decimal.compare(per_sym.current_yield, Decimal.new("30")) == :lt,
             "Yield #{per_sym.current_yield}% is inflated — PIL dedup may be broken"
    end
  end

  describe "FX exposure (Feature 3)" do
    test "compute_fx_exposure/1 groups by currency with correct percentages" do
      # Build mock positions
      positions = [
        %Portfolio.Position{
          currency: "EUR",
          value: Decimal.new("21000"),
          fx_rate: Decimal.new("1"),
          symbol: "KESKOB"
        },
        %Portfolio.Position{
          currency: "USD",
          value: Decimal.new("15000"),
          fx_rate: Decimal.new("0.92"),
          symbol: "AAPL"
        }
      ]

      result = Portfolio.compute_fx_exposure(positions)

      assert length(result) == 2
      eur_entry = Enum.find(result, &(&1.currency == "EUR"))
      usd_entry = Enum.find(result, &(&1.currency == "USD"))

      assert eur_entry.holdings_count == 1
      assert Decimal.equal?(eur_entry.local_value, Decimal.new("21000"))
      assert usd_entry.holdings_count == 1
      # Total EUR: 21000 + 15000*0.92 = 21000 + 13800 = 34800
      total_eur = Decimal.add(Decimal.new("21000"), Decimal.new("13800"))

      expected_eur_pct =
        Decimal.new("21000")
        |> Decimal.div(total_eur)
        |> Decimal.mult(Decimal.new("100"))
        |> Decimal.round(1)

      assert Decimal.equal?(eur_entry.pct, expected_eur_pct)
    end
  end

  describe "dividend cash flow summary (Feature 5)" do
    test "dividend_cash_flow_summary/0 returns cumulative totals" do
      today = Date.utc_today()

      # EUR dividends: net_amount is the total EUR value
      insert_test_dividend("KESKOB", "FI0009000202", Date.new!(today.year, 1, 15), "100", "EUR")
      insert_test_dividend("KESKOB", "FI0009000202", Date.new!(today.year, 2, 10), "50", "EUR")

      result = Portfolio.dividend_cash_flow_summary()

      assert result != []
      # Verify cumulative: last entry's cumulative should equal sum of all incomes
      last = List.last(result)
      total = Enum.reduce(result, Decimal.new("0"), fn e, acc -> Decimal.add(acc, e.income) end)
      assert Decimal.equal?(last.cumulative, total)
    end
  end

  describe "compute_dividend_dashboard/2" do
    test "should return all dividend data in one pass" do
      today = Date.utc_today()

      # EUR dividends with total net amounts
      insert_test_dividend("KESKOB", "FI0009000202", Date.new!(today.year, 1, 15), "100", "EUR")
      insert_test_dividend("KESKOB", "FI0009000202", Date.new!(today.year, 2, 10), "50", "EUR")

      result = Portfolio.compute_dividend_dashboard(today.year, nil)

      # total_for_year: 100 + 50 = 150
      assert Decimal.equal?(result.total_for_year, Decimal.new("150"))
      assert %Decimal{} = result.projected_annual
      assert is_list(result.recent_with_income)
      assert length(result.recent_with_income) <= 5
      assert is_list(result.cash_flow_summary)
      assert is_list(result.by_month_full_range)
    end

    test "should return nil projected_annual for past years" do
      today = Date.utc_today()
      past_year = today.year - 1

      result = Portfolio.compute_dividend_dashboard(past_year, nil)

      assert is_nil(result.projected_annual)
      assert result.cash_flow_summary == []
    end

    test "should handle chart_date_range wider than year" do
      today = Date.utc_today()

      # EUR dividend with total net amount
      insert_test_dividend("KESKOB", "FI0009000202", Date.new!(today.year, 1, 15), "100", "EUR")

      chart_range = {Date.new!(today.year - 1, 1, 1), today}
      result = Portfolio.compute_dividend_dashboard(today.year, chart_range)

      assert is_list(result.by_month_full_range)
      assert Decimal.compare(result.total_for_year, Decimal.new("0")) == :gt
    end
  end

  defp insert_test_holding(snapshot_id, date, symbol, qty, fx_rate, currency \\ "EUR") do
    %Portfolio.Position{}
    |> Portfolio.Position.changeset(%{
      portfolio_snapshot_id: snapshot_id,
      date: date,
      symbol: symbol,
      currency: currency,
      quantity: qty,
      price: "10",
      value: "1000",
      cost_price: "10",
      cost_basis: "1000",
      weight: "50",
      exchange: "HEX",
      asset_class: "STK",
      fx_rate: fx_rate
    })
    |> Dividendsomatic.Repo.insert!()
  end

  defp get_or_create_instrument(symbol, isin) do
    case Repo.get_by(Instrument, isin: isin) do
      nil ->
        {:ok, instrument} =
          %Instrument{}
          |> Instrument.changeset(%{isin: isin, name: "#{symbol} Corp"})
          |> Repo.insert()

        {:ok, alias_record} =
          %InstrumentAlias{}
          |> InstrumentAlias.changeset(%{
            instrument_id: instrument.id,
            symbol: symbol,
            source: "test"
          })
          |> Repo.insert()

        {instrument, alias_record}

      instrument ->
        alias_record = Repo.get_by(InstrumentAlias, instrument_id: instrument.id, symbol: symbol)
        {instrument, alias_record}
    end
  end

  defp insert_test_dividend(symbol, isin, pay_date, net_amount, currency, opts \\ []) do
    {instrument, _alias} = get_or_create_instrument(symbol, isin)

    attrs = %{
      external_id: "test-div-#{System.unique_integer([:positive])}",
      instrument_id: instrument.id,
      pay_date: pay_date,
      gross_amount: Decimal.new(net_amount),
      net_amount: Decimal.new(net_amount),
      currency: currency
    }

    attrs = if opts[:fx_rate], do: Map.put(attrs, :fx_rate, opts[:fx_rate]), else: attrs
    attrs = if opts[:per_share], do: Map.put(attrs, :per_share, opts[:per_share]), else: attrs

    %DividendPayment{}
    |> DividendPayment.changeset(attrs)
    |> Repo.insert!()
  end
end
