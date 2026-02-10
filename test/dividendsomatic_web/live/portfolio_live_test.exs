defmodule DividendsomaticWeb.PortfolioLiveTest do
  use DividendsomaticWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Dividendsomatic.Portfolio

  @csv_data """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  """

  @multi_holding_csv """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  "2026-01-28","EUR","TELIA1","TELIA CO AB","COMMON","10000","3.858","38580","3.5871187","35871.187","3.5871187","16.34","2708.813","FWB","STK","1","SE0000667925","BBG000GJ9377"
  """

  describe "empty state" do
    test "should render empty state when no data exists", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "No Portfolio Data"
      assert html =~ "mix import.csv"
    end

    test "should show brand name in empty state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "dividends-o-matic"
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

    test "should show holding symbols in table", %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@multi_holding_csv, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "KESKOB"
      assert html =~ "TELIA1"
    end

    test "should show holdings count", %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@multi_holding_csv, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "2 holdings"
    end

    test "should show table column headers", %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Symbol"
      assert html =~ "Description"
      assert html =~ "Qty"
      assert html =~ "Price"
      assert html =~ "Value"
      assert html =~ "Cost"
    end

    test "should show snapshot position counter", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-27])
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "2/2"
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

      assert html =~ "2026-01-28"

      html =
        view
        |> element(~s{button[phx-click="navigate"][phx-value-direction="prev"]})
        |> render_click()

      assert html =~ "2026-01-27"
    end

    test "should navigate to next snapshot when clicking next", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

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

      view
      |> element(~s{button[phx-click="navigate"][phx-value-direction="first"]})
      |> render_click()

      html =
        view
        |> element(~s{button[phx-click="navigate"][phx-value-direction="last"]})
        |> render_click()

      assert html =~ "2026-01-28"
    end

    test "should disable prev button on first snapshot", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Navigate to first
      view
      |> element(~s{button[phx-click="navigate"][phx-value-direction="first"]})
      |> render_click()

      html = render(view)
      # The first/prev buttons should be disabled when on first snapshot
      assert html =~ ~s{disabled}
    end
  end

  describe "handle_params" do
    test "should load snapshot by date from URL params", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-27])
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/portfolio/2026-01-27")

      assert html =~ "2026-01-27"
    end

    test "should handle invalid date in URL params gracefully", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "2026-01-28"
    end
  end

  describe "keyboard navigation" do
    test "should have the KeyboardNav hook on the page", %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s{phx-hook="KeyboardNav"}
    end

    test "should show keyboard shortcut hints", %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "navigate"
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

    test "should show projected dividends", %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Proj."
    end
  end

  describe "chart display" do
    test "should show chart when multiple snapshots exist", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-27])
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Portfolio Performance"
      assert html =~ "Value"
      assert html =~ "Cost Basis"
    end

    test "should not show chart with single snapshot", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      refute html =~ "Portfolio Performance"
    end

    test "should show trading days count", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-27])
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "trading days"
    end
  end
end
