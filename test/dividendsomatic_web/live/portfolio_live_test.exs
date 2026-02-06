defmodule DividendsomaticWeb.PortfolioLiveTest do
  use DividendsomaticWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Dividendsomatic.Portfolio

  @csv_data """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  """

  describe "empty state" do
    test "should render empty state when no data exists", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "No Portfolio Data"
      assert html =~ "mix import.csv"
    end
  end

  describe "with snapshot data" do
    test "should show the snapshot date", %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "2026-01-28"
    end

    test "should show holdings table with Positions header", %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Positions"
    end

    test "should show portfolio value stat", %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Portfolio Value"
    end
  end

  describe "navigation" do
    setup %{conn: conn} do
      {:ok, _first} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-27])
      {:ok, _second} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      %{conn: conn}
    end

    test "should navigate to previous snapshot when clicking prev", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      # LiveView mounts with the latest snapshot (2026-01-28)
      assert html =~ "2026-01-28"

      html =
        view
        |> element(~s{button[phx-click="navigate"][phx-value-direction="prev"]})
        |> render_click()

      assert html =~ "2026-01-27"
    end

    test "should navigate to next snapshot when clicking next", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Navigate to the first snapshot first
      view
      |> element(~s{button[phx-click="navigate"][phx-value-direction="prev"]})
      |> render_click()

      html =
        view
        |> element(~s{button[phx-click="navigate"][phx-value-direction="next"]})
        |> render_click()

      assert html =~ "2026-01-28"
    end

    test "should navigate to first snapshot when clicking first", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> element(~s{button[phx-click="navigate"][phx-value-direction="first"]})
        |> render_click()

      assert html =~ "2026-01-27"
    end

    test "should navigate to last snapshot when clicking last", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Navigate to first snapshot first
      view
      |> element(~s{button[phx-click="navigate"][phx-value-direction="first"]})
      |> render_click()

      html =
        view
        |> element(~s{button[phx-click="navigate"][phx-value-direction="last"]})
        |> render_click()

      assert html =~ "2026-01-28"
    end
  end

  describe "keyboard navigation" do
    test "should have the KeyboardNav hook on the page", %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s{phx-hook="KeyboardNav"}
    end
  end

  describe "stats display" do
    test "should show all stats cards", %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Portfolio Value"
      assert html =~ "Unrealized P&amp;L"
      assert html =~ "Dividends YTD"
      assert html =~ "Holdings"
    end
  end
end
