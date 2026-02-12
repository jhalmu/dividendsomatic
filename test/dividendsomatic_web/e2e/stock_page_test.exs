defmodule DividendsomaticWeb.E2E.StockPageTest do
  @moduledoc """
  Playwright E2E tests for stock detail pages.

  Run: mix test --include playwright test/dividendsomatic_web/e2e/stock_page_test.exs
  Debug: PW_HEADLESS=false mix test --include playwright test/dividendsomatic_web/e2e/stock_page_test.exs
  """
  use PhoenixTest.Playwright.Case, async: false
  use DividendsomaticWeb, :verified_routes

  import DividendsomaticWeb.PlaywrightJsHelper

  alias Dividendsomatic.{Portfolio, Repo}
  alias Dividendsomatic.Stocks.{CompanyProfile, StockMetric}

  @csv_data """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  """

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp insert_profile(symbol, attrs \\ %{}) do
    defaults = %{
      symbol: symbol,
      name: "Test Corp",
      industry: "Technology",
      country: "US",
      exchange: "NASDAQ",
      fetched_at: now()
    }

    Repo.insert!(struct(CompanyProfile, Map.merge(defaults, attrs)))
  end

  defp insert_metrics(symbol, attrs \\ %{}) do
    defaults = %{
      symbol: symbol,
      pe_ratio: Decimal.new("18.50"),
      roe: Decimal.new("22.30"),
      net_margin: Decimal.new("15.40"),
      beta: Decimal.new("1.10"),
      payout_ratio: Decimal.new("45.00"),
      fetched_at: now()
    }

    Repo.insert!(struct(StockMetric, Map.merge(defaults, attrs)))
  end

  describe "Stock Page Structure" do
    @tag :playwright
    test "should render stock page with symbol and back link", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      conn
      |> visit(~p"/stocks/KESKOB")
      |> assert_has("h1", text: "KESKOB")
      |> assert_has("a", text: "Portfolio")
    end

    @tag :playwright
    test "should show position summary with holding data", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      conn
      |> visit(~p"/stocks/KESKOB")
      |> assert_has("div", text: "Position")
      |> assert_has("div", text: "Shares")
      |> assert_has("div", text: "1,000")
    end
  end

  describe "Sector Badge in Header" do
    @tag :playwright
    test "should show sector badge when company profile exists", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      insert_profile("KESKOB", %{
        name: "Kesko Oyj",
        industry: "Retail",
        country: "FI",
        exchange: "HEX"
      })

      conn
      |> visit(~p"/stocks/KESKOB")
      |> assert_has("[data-testid='sector-badge']", text: "Retail")
    end

    @tag :playwright
    test "should not show sector badge for unknown symbol", %{conn: conn} do
      conn
      |> visit(~p"/stocks/UNKNOWN")
      |> refute_has("[data-testid='sector-badge']")
    end
  end

  describe "Financial Metrics Card" do
    @tag :playwright
    test "should show key metrics card when data exists", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])
      insert_metrics("KESKOB")

      conn
      |> visit(~p"/stocks/KESKOB")
      |> assert_has("[data-testid='financial-metrics']")
      |> assert_has("div", text: "Key Metrics")
      |> assert_has("div", text: "P/E")
      |> assert_has("div", text: "18.50")
      |> assert_has("div", text: "ROE")
      |> assert_has("div", text: "22.30")
    end

    @tag :playwright
    test "should not show metrics card when no data exists", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      conn
      |> visit(~p"/stocks/KESKOB")
      |> refute_has("[data-testid='financial-metrics']")
    end

    @tag :playwright
    test "should skip nil metric fields", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])
      insert_metrics("KESKOB", %{roe: nil, net_margin: nil, beta: nil, payout_ratio: nil})

      conn
      |> visit(~p"/stocks/KESKOB")
      |> assert_has("[data-testid='financial-metrics']")
      |> assert_has("div", text: "P/E")
      |> refute_has("[data-testid='financial-metrics'] div", text: "ROE")
    end

    @tag :playwright
    test "should show updated date in metrics header", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])
      insert_metrics("KESKOB")

      conn
      |> visit(~p"/stocks/KESKOB")
      |> assert_has("[data-testid='financial-metrics']", text: "Updated")
    end
  end

  describe "Stock Page Accessibility" do
    @tag :playwright
    test "should have no accessibility violations on stock page", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])
      insert_profile("KESKOB", %{name: "Kesko Oyj", industry: "Retail", country: "FI"})
      insert_metrics("KESKOB")

      conn
      |> visit(~p"/stocks/KESKOB")
      |> assert_has("h1", text: "KESKOB")
      |> assert_no_violations()
    end
  end

  # --- Accessibility helpers ---

  defp audit_page(session) do
    session = run_js(session, A11yAudit.JS.axe_core())
    {session, axe_result} = execute_js(session, A11yAudit.JS.await_audit_results())
    results = A11yAudit.Results.from_json(axe_result)
    {session, results}
  end

  defp assert_no_violations(session) do
    {session, results} = audit_page(session)
    A11yAudit.Assertions.assert_no_violations(results)
    session
  end
end
