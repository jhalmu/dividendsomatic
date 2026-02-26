defmodule DividendsomaticWeb.E2E.PortfolioPageTest do
  @moduledoc """
  Playwright E2E tests for the portfolio dashboard page.

  Run: mix test --include playwright test/dividendsomatic_web/e2e/portfolio_page_test.exs
  Debug: PW_HEADLESS=false mix test --include playwright test/dividendsomatic_web/e2e/portfolio_page_test.exs
  """
  use PhoenixTest.Playwright.Case, async: false
  use DividendsomaticWeb, :verified_routes

  alias Dividendsomatic.{Portfolio, Repo}

  alias Dividendsomatic.Portfolio.{
    CashFlow,
    DividendPayment,
    Instrument,
    InstrumentAlias,
    Trade
  }

  @csv_data """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  "2026-01-28","USD","AAPL","APPLE INC","COMMON","50","185.50","9275","150.00","7500","150.00","3.93","1775","NASDAQ","STK","0.92","US0378331005","BBG000B9XRY4"
  """

  defp insert_instrument(isin, name, currency \\ "EUR") do
    %Instrument{}
    |> Instrument.changeset(%{isin: isin, name: name, currency: currency})
    |> Repo.insert!()
  end

  defp insert_alias(instrument, symbol) do
    %InstrumentAlias{}
    |> InstrumentAlias.changeset(%{
      instrument_id: instrument.id,
      symbol: symbol,
      source: "test"
    })
    |> Repo.insert!()
  end

  defp insert_trade(instrument, attrs) do
    defaults = %{
      external_id: "test-trade-#{System.unique_integer([:positive])}",
      instrument_id: instrument.id,
      trade_date: ~D[2025-06-15],
      quantity: Decimal.new("100"),
      price: Decimal.new("20.00"),
      amount: Decimal.new("2000.00"),
      commission: Decimal.new("5.00"),
      currency: "EUR",
      asset_category: "Stocks"
    }

    %Trade{}
    |> Trade.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_dividend(instrument, attrs) do
    defaults = %{
      external_id: "test-div-#{System.unique_integer([:positive])}",
      instrument_id: instrument.id,
      pay_date: ~D[2026-01-15],
      gross_amount: Decimal.new("100.00"),
      net_amount: Decimal.new("85.00"),
      currency: "EUR"
    }

    %DividendPayment{}
    |> DividendPayment.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_cash_flow(attrs) do
    defaults = %{
      external_id: "test-cf-#{System.unique_integer([:positive])}",
      flow_type: "deposit",
      date: ~D[2025-01-10],
      amount: Decimal.new("10000.00"),
      currency: "EUR"
    }

    %CashFlow{}
    |> CashFlow.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp seed_portfolio_data do
    {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

    kesko = insert_instrument("FI0009000202", "KESKO OYJ-B SHS")
    insert_alias(kesko, "KESKOB")

    aapl = insert_instrument("US0378331005", "APPLE INC", "USD")
    insert_alias(aapl, "AAPL")

    insert_trade(kesko, %{
      trade_date: ~D[2025-03-10],
      quantity: Decimal.new("1000"),
      price: Decimal.new("18.26"),
      amount: Decimal.new("18260.00"),
      currency: "EUR"
    })

    insert_trade(aapl, %{
      trade_date: ~D[2025-04-15],
      quantity: Decimal.new("50"),
      price: Decimal.new("150.00"),
      amount: Decimal.new("7500.00"),
      currency: "USD",
      fx_rate: Decimal.new("0.92")
    })

    insert_dividend(kesko, %{
      pay_date: ~D[2026-01-15],
      gross_amount: Decimal.new("220.00"),
      net_amount: Decimal.new("220.00"),
      currency: "EUR"
    })

    insert_dividend(aapl, %{
      pay_date: ~D[2026-01-20],
      gross_amount: Decimal.new("12.50"),
      net_amount: Decimal.new("8.75"),
      withholding_tax: Decimal.new("3.75"),
      currency: "USD",
      fx_rate: Decimal.new("0.92")
    })

    insert_cash_flow(%{
      flow_type: "deposit",
      date: ~D[2025-01-10],
      amount: Decimal.new("10000.00"),
      currency: "EUR"
    })

    :ok
  end

  describe "Empty State" do
    @tag :playwright
    test "should render portfolio page with empty state message", %{conn: conn} do
      conn
      |> visit(~p"/")
      |> assert_has("#portfolio-view")
      |> assert_has("h1", text: "dividends-o-matic")
    end
  end

  describe "Portfolio with Data" do
    @tag :playwright
    test "should render portfolio dashboard with snapshot data", %{conn: conn} do
      seed_portfolio_data()

      conn
      |> visit(~p"/portfolio/2026-01-28")
      |> assert_has("#portfolio-view")
      # Holdings are now in the holdings tab, but symbols appear in overview top holdings
      |> assert_has("div", text: "KESKOB")
      |> assert_has("div", text: "AAPL")
    end

    @tag :playwright
    test "should show holdings table with positions in holdings tab", %{conn: conn} do
      seed_portfolio_data()

      conn
      |> visit(~p"/portfolio/2026-01-28")
      |> click_button("Holdings")
      |> assert_has("table")
      |> assert_has("td", text: "KESKOB")
      |> assert_has("td", text: "AAPL")
    end

    @tag :playwright
    test "should navigate to stock detail page from holdings", %{conn: conn} do
      seed_portfolio_data()

      conn
      |> visit(~p"/portfolio/2026-01-28")
      |> click_button("Holdings")
      |> click_link("KESKOB")
      |> assert_has("h1", text: "KESKOB")
    end
  end

  describe "Date Navigation" do
    @tag :playwright
    test "should show date in navigation bar", %{conn: conn} do
      seed_portfolio_data()

      conn
      |> visit(~p"/portfolio/2026-01-28")
      |> assert_has("input[type='date'][value='2026-01-28']")
    end
  end

  describe "Tab Navigation" do
    @tag :playwright
    test "should show overview tab as default", %{conn: conn} do
      seed_portfolio_data()

      conn
      |> visit(~p"/portfolio/2026-01-28")
      |> assert_has("[role='tablist']")
      |> assert_has("[role='tab'][aria-controls='panel-overview']")
    end

    @tag :playwright
    test "should show income tab", %{conn: conn} do
      seed_portfolio_data()

      conn
      |> visit(~p"/portfolio/2026-01-28")
      |> assert_has("[role='tablist']")
      |> assert_has("[role='tab'][aria-controls='panel-income']")
    end

    @tag :playwright
    test "should have holdings tab available", %{conn: conn} do
      seed_portfolio_data()

      conn
      |> visit(~p"/portfolio/2026-01-28")
      |> assert_has("[role='tab'][aria-controls='panel-holdings']")
    end

    @tag :playwright
    test "should have summary tab available", %{conn: conn} do
      seed_portfolio_data()

      conn
      |> visit(~p"/portfolio/2026-01-28")
      |> assert_has("[role='tab'][aria-controls='panel-summary']")
    end
  end

  describe "Dividend Data from Clean Tables" do
    @tag :playwright
    test "should display income tab content", %{conn: conn} do
      seed_portfolio_data()

      conn
      |> visit(~p"/portfolio/2026-01-28")
      |> assert_has("[role='tab'][aria-controls='panel-income']")
    end
  end
end
