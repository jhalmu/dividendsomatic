defmodule DividendsomaticWeb.StockLiveTest do
  use DividendsomaticWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Dividendsomatic.Portfolio

  @csv_data """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  """

  describe "stock page with snapshot data" do
    setup %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])
      %{conn: conn}
    end

    test "should render stock page with symbol", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "KESKOB"
    end

    test "should show symbol in header", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      # The symbol appears in the h1 header element
      assert html =~ "terminal-stock-symbol"
      assert html =~ "KESKOB"
    end

    test "should show back to portfolio link", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Back to portfolio"
      assert html =~ ~s{href="/"}
    end

    test "should show external links for HEX exchange stock", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      # Yahoo Finance with .HE suffix for HEX exchange
      assert html =~ "Yahoo Finance"
      assert html =~ "finance.yahoo.com/quote/KESKOB.HE"

      # Google Finance with HEL exchange code for HEX
      assert html =~ "Google Finance"
      assert html =~ "google.com/finance/quote/KESKOB:HEL"

      # Nordnet link using ISIN for HEX exchange stocks
      assert html =~ "Nordnet"
      assert html =~ "nordnet.fi/markkina/osakkeet/FI0009000202"
    end

    test "should not show SeekingAlpha link for HEX exchange stock", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      # SeekingAlpha is only shown for NYSE, NASDAQ, ARCA exchanges
      refute html =~ "SeekingAlpha"
    end

    test "should show External Links section label", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "External Links"
    end

    test "should open external links in new window", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ ~s{target="_blank"}
      assert html =~ ~s{rel="noopener noreferrer"}
    end
  end

  describe "stock page for unknown symbol" do
    test "should render page for unknown symbol without crashing", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/NONEXISTENT")

      # Page should render with the symbol even if no data exists
      assert html =~ "NONEXISTENT"
    end

    test "should show back link for unknown symbol", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/NONEXISTENT")

      assert html =~ "Back to portfolio"
    end

    test "should still show Yahoo Finance link for unknown symbol", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/NONEXISTENT")

      # Yahoo Finance link is always generated (without exchange suffix when unknown)
      assert html =~ "Yahoo Finance"
      assert html =~ "finance.yahoo.com/quote/NONEXISTENT"
    end
  end
end
