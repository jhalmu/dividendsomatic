defmodule DividendsomaticWeb.E2E.AccessibilityTest do
  @moduledoc """
  Accessibility audit tests using axe-core via a11y_audit.

  Run: mix test --include playwright test/dividendsomatic_web/e2e/accessibility_test.exs
  Debug: PW_HEADLESS=false mix test --include playwright test/dividendsomatic_web/e2e/accessibility_test.exs
  """
  use PhoenixTest.Playwright.Case, async: false
  use DividendsomaticWeb, :verified_routes

  import DividendsomaticWeb.PlaywrightJsHelper

  alias Dividendsomatic.Portfolio

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

  @csv_data """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  "2026-01-28","EUR","TELIA1","TELIA CO AB","COMMON","10000","3.858","38580","3.5871187","35871.187","3.5871187","16.34","2708.813","FWB","STK","1","SE0000667925","BBG000GJ9377"
  """

  describe "Empty State Accessibility" do
    @tag :playwright
    test "should have no accessibility violations on empty state", %{conn: conn} do
      conn
      |> visit(~p"/")
      |> assert_has("#portfolio-view")
      |> assert_no_violations()
    end
  end

  describe "Portfolio Page Accessibility" do
    @tag :playwright
    test "should have no accessibility violations with data", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      conn
      |> visit(~p"/")
      |> assert_has("#portfolio-view")
      |> assert_no_violations()
    end

    @tag :playwright
    test "should have no accessibility violations on date route", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      conn
      |> visit(~p"/portfolio/2026-01-28")
      |> assert_has("#portfolio-view")
      |> assert_no_violations()
    end
  end

  describe "Contrast and ARIA" do
    @tag :playwright
    test "should report specific color-contrast violations if any", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      conn
      |> visit(~p"/")
      |> assert_has("#portfolio-view")
      |> then(fn session ->
        {session, results} = audit_page(session)

        contrast_violations =
          Enum.filter(results.violations, fn v -> v.id == "color-contrast" end)

        if contrast_violations != [] do
          IO.puts("\nColor Contrast Violations Found:")

          Enum.each(contrast_violations, fn violation ->
            IO.puts("  Issue: #{violation.description}")
            IO.puts("  Impact: #{violation.impact}")
          end)
        end

        A11yAudit.Assertions.assert_no_violations(results)
        session
      end)
    end
  end
end
