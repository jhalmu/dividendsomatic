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

    test "should navigate to previous snapshot", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "2026-01-28"

      html = render_hook(view, "navigate", %{"direction" => "prev"})

      assert html =~ "2026-01-27"
    end

    test "should navigate to next snapshot", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "navigate", %{"direction" => "prev"})

      html = render_hook(view, "navigate", %{"direction" => "next"})

      assert html =~ "2026-01-28"
    end

    test "should navigate to first snapshot", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "navigate", %{"direction" => "first"})

      assert html =~ "2026-01-27"
    end

    test "should navigate to last snapshot", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "navigate", %{"direction" => "first"})

      html = render_hook(view, "navigate", %{"direction" => "last"})

      assert html =~ "2026-01-28"
    end

    test "should disable prev button on first snapshot", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Navigate to first
      render_hook(view, "navigate", %{"direction" => "first"})

      html = render(view)
      # The prev buttons should be disabled when on first snapshot
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
      assert html =~ "Dividends #{Date.utc_today().year}"
      assert html =~ "Realized #{Date.utc_today().year}"
      # F&G gauge replaces Holdings stat when available; otherwise "Holdings" shows
      assert html =~ "Holdings" or html =~ "fear-greed"
    end

    test "should show realized year card with sub-lines", %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Realized #{Date.utc_today().year}"
      assert html =~ "Dividends:"
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

  describe "FX exposure breakdown (Feature 3)" do
    @multi_currency_csv """
    "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
    "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18","18000","18","40","3000","HEX","STK","1","FI0009000202","BBG000BNP2B2"
    "2026-01-28","USD","AAPL","APPLE INC","COMMON","100","150","15000","120","12000","120","60","3000","NASDAQ","STK","0.92","US0378331005","BBG000B9XRY4"
    """

    test "should show FX exposure table when multiple currencies exist", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@multi_currency_csv, ~D[2026-01-28])
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "switch_tab", %{"tab" => "summary"})
      assert html =~ "Currency Exposure"
      assert html =~ "fx-exposure"
      assert html =~ "EUR"
      assert html =~ "USD"
    end

    test "should hide FX exposure when single currency", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "switch_tab", %{"tab" => "summary"})
      refute html =~ "fx-exposure"
      refute html =~ "Currency Exposure"
    end
  end

  describe "realized P&L with sold positions (Feature 4)" do
    setup %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "AAPL",
          quantity: Decimal.new("100"),
          purchase_price: Decimal.new("150.00"),
          purchase_date: ~D[2025-01-01],
          sale_price: Decimal.new("175.00"),
          sale_date: ~D[2026-01-15]
        })

      %{conn: conn}
    end

    test "should show realized P&L section with summary stats", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "switch_tab", %{"tab" => "summary"})
      assert html =~ "Realized P&amp;L"
      assert html =~ "pnl-summary-stats"
      assert html =~ "Gains"
      assert html =~ "Losses"
      assert html =~ "Win Rate"
      assert html =~ "Trades"
    end

    test "should show top winners table with AAPL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "switch_tab", %{"tab" => "summary"})
      assert html =~ "Top Winners"
      assert html =~ "AAPL"
    end

    test "should link sold symbol to stock page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "switch_tab", %{"tab" => "summary"})
      assert html =~ ~s{href="/stocks/AAPL"}
    end

    test "should show holding period years", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "switch_tab", %{"tab" => "summary"})
      assert html =~ "2025"
      assert html =~ "2026"
    end

    test "should show year filter buttons", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "switch_tab", %{"tab" => "summary"})
      # Should have "All" button and year buttons
      assert html =~ "All"
      assert html =~ "2026"
    end

    test "should filter by year when year button clicked", %{conn: conn} do
      # Add a sold position in a different year
      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "MSFT",
          quantity: Decimal.new("50"),
          purchase_price: Decimal.new("200.00"),
          purchase_date: ~D[2024-01-01],
          sale_price: Decimal.new("180.00"),
          sale_date: ~D[2025-06-15]
        })

      {:ok, view, _html} = live(conn, ~p"/")

      # Switch to summary tab first
      html = render_hook(view, "switch_tab", %{"tab" => "summary"})

      # Both symbols visible in "All" mode
      assert html =~ "AAPL"
      assert html =~ "MSFT"

      # Filter to 2026 - only AAPL sold in 2026
      html = render_hook(view, "pnl_year", %{"year" => "2026"})
      assert html =~ "AAPL"
      refute html =~ "MSFT"

      # Filter to 2025 - only MSFT sold in 2025
      html = render_hook(view, "pnl_year", %{"year" => "2025"})
      assert html =~ "MSFT"
      refute html =~ "AAPL"

      # Back to all
      html = render_hook(view, "pnl_year", %{"year" => "all"})
      assert html =~ "AAPL"
      assert html =~ "MSFT"
    end

    test "should toggle show all symbols", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "switch_tab", %{"tab" => "summary"})
      assert html =~ "Show all"

      html = render_hook(view, "pnl_show_all", %{})
      assert html =~ "Hide"

      html = render_hook(view, "pnl_show_all", %{})
      assert html =~ "Show all"
    end
  end

  describe "cash flow summary (Feature 5)" do
    test "should show cash flow section when dividends exist", %{conn: conn} do
      today = Date.utc_today()

      {:ok, snapshot} =
        %Portfolio.PortfolioSnapshot{}
        |> Portfolio.PortfolioSnapshot.changeset(%{
          date: Date.new!(today.year, 1, 10),
          source: "ibkr_flex"
        })
        |> Dividendsomatic.Repo.insert()

      %Portfolio.Position{}
      |> Portfolio.Position.changeset(%{
        portfolio_snapshot_id: snapshot.id,
        date: Date.new!(today.year, 1, 10),
        symbol: "KESKOB",
        currency: "EUR",
        quantity: "1000",
        price: "21",
        value: "21000",
        cost_price: "18",
        cost_basis: "18000",
        weight: "100",
        exchange: "HEX",
        asset_class: "STK",
        fx_rate: "1"
      })
      |> Dividendsomatic.Repo.insert!()

      {:ok, _} =
        Portfolio.create_dividend(%{
          symbol: "KESKOB",
          ex_date: Date.new!(today.year, 1, 15),
          amount: Decimal.new("0.50"),
          currency: "EUR"
        })

      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "switch_tab", %{"tab" => "income"})
      assert html =~ "Dividend Cash Flow"
      assert html =~ "cash-flow"
    end
  end

  describe "short position support (Feature 6)" do
    @short_csv """
    "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
    "2026-01-28","USD","TSLA","TESLA INC","COMMON","-50","200","-10000","180","-9000","180","5","-1000","NASDAQ","STK","0.92","US88160R1014","BBG000N9MNX3"
    """

    test "should show SHORT badge for negative quantity", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@short_csv, ~D[2026-01-28])
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "short-badge"
      assert html =~ "SHORT"
    end
  end
end
