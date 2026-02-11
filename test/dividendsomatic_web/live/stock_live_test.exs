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

      assert html =~ "terminal-stock-symbol"
      assert html =~ "KESKOB"
    end

    test "should show back to portfolio link", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Back to portfolio"
      assert html =~ ~s{href="/"}
    end

    test "should show position summary card", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Position"
      assert html =~ "Shares"
      assert html =~ "Avg Cost"
      assert html =~ "Current Value"
      assert html =~ "Unrealized P&amp;L"
      assert html =~ "Weight"
    end

    test "should show data date in position card", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Data as of 2026-01-28"
    end

    test "should show shares held count", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "1,000"
    end

    test "should show editable investment notes section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Investment Notes"
      assert html =~ "Investment Thesis"
      assert html =~ "phx-blur=\"save_thesis\""
      assert html =~ "phx-blur=\"save_notes\""
      refute html =~ "Coming soon"
    end

    test "should show external links for HEX exchange stock", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Yahoo Finance"
      assert html =~ "finance.yahoo.com/quote/KESKOB.HE"
      assert html =~ "Google Finance"
      assert html =~ "google.com/finance/quote/KESKOB:HEL"
      assert html =~ "Nordnet"
      assert html =~ "nordnet.fi/markkina/osakkeet/FI0009000202"
    end

    test "should not show SeekingAlpha link for HEX exchange stock", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

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

      assert html =~ "NONEXISTENT"
    end

    test "should show back link for unknown symbol", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/NONEXISTENT")

      assert html =~ "Back to portfolio"
    end

    test "should still show Yahoo Finance link for unknown symbol", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/NONEXISTENT")

      assert html =~ "Yahoo Finance"
      assert html =~ "finance.yahoo.com/quote/NONEXISTENT"
    end

    test "should not show position card for unknown symbol", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/NONEXISTENT")

      refute html =~ "terminal-info-label\">Shares"
      refute html =~ "Avg Cost"
    end

    test "should not show investment notes for unknown symbol (no ISIN)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/NONEXISTENT")

      refute html =~ "Investment Thesis"
      refute html =~ "Coming soon"
    end
  end

  describe "investment notes" do
    setup %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])
      %{conn: conn}
    end

    test "should save thesis on blur", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/stocks/KESKOB")

      view |> element("#note-thesis") |> render_blur(%{value: "Great dividend stock"})

      # Re-render should show the saved text
      html = render(view)
      assert html =~ "Great dividend stock"
      assert html =~ "Saved"
    end

    test "should save notes on blur", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/stocks/KESKOB")

      view |> element("#note-markdown") |> render_blur(%{value: "Key metrics: P/E 12"})

      html = render(view)
      assert html =~ "Key metrics: P/E 12"
    end

    test "should persist notes to database", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/stocks/KESKOB")

      view |> element("#note-thesis") |> render_blur(%{value: "Long-term hold"})

      # Verify persisted
      note = Dividendsomatic.Stocks.get_company_note_by_isin("FI0009000202")
      assert note.thesis == "Long-term hold"
      assert note.symbol == "KESKOB"
    end

    test "should show asset-type-specific placeholder", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      # Default stock placeholder
      assert html =~ "Growth potential"
    end
  end

  describe "dividend display" do
    setup %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      # Dividend ex_date must be >= first holding date (2026-01-28) to show
      {:ok, _} =
        Portfolio.create_dividend(%{
          symbol: "KESKOB",
          ex_date: ~D[2026-02-05],
          amount: Decimal.new("0.50"),
          currency: "EUR"
        })

      %{conn: conn}
    end

    test "should show dividends received section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Dividends Received"
      assert html =~ "(1)"
      assert html =~ "Per Share"
      assert html =~ "Income"
    end

    test "should show computed dividend income", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      # 0.50 * 1000 * 1.0 = 500.00 EUR
      assert html =~ "500"
      assert html =~ "Total:"
    end

    test "should show dividend analytics section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Dividend Analytics"
      assert html =~ "TTM Per Share"
    end

    test "should filter out dividends before ownership", %{conn: conn} do
      # Add a dividend before the holding date - should not appear
      {:ok, _} =
        Portfolio.create_dividend(%{
          symbol: "KESKOB",
          ex_date: ~D[2025-12-01],
          amount: Decimal.new("0.30"),
          currency: "EUR"
        })

      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      # Should still show only 1 dividend (the one from setup), not the pre-ownership one
      assert html =~ "Dividends Received"
      assert html =~ "(1)"
    end
  end

  describe "dividend analytics calculations" do
    test "should detect quarterly frequency" do
      divs = [
        %{
          dividend: %{ex_date: ~D[2025-03-15], amount: Decimal.new("0.50")},
          income: Decimal.new("500")
        },
        %{
          dividend: %{ex_date: ~D[2025-06-15], amount: Decimal.new("0.50")},
          income: Decimal.new("500")
        },
        %{
          dividend: %{ex_date: ~D[2025-09-15], amount: Decimal.new("0.50")},
          income: Decimal.new("500")
        },
        %{
          dividend: %{ex_date: ~D[2025-12-15], amount: Decimal.new("0.50")},
          income: Decimal.new("500")
        }
      ]

      assert DividendsomaticWeb.StockLive.detect_dividend_frequency(divs) == "quarterly"
    end

    test "should detect annual frequency" do
      divs = [
        %{
          dividend: %{ex_date: ~D[2024-06-01], amount: Decimal.new("1.00")},
          income: Decimal.new("1000")
        },
        %{
          dividend: %{ex_date: ~D[2025-06-01], amount: Decimal.new("1.10")},
          income: Decimal.new("1100")
        }
      ]

      assert DividendsomaticWeb.StockLive.detect_dividend_frequency(divs) == "annual"
    end

    test "should detect semi-annual frequency" do
      divs = [
        %{
          dividend: %{ex_date: ~D[2025-01-15], amount: Decimal.new("0.50")},
          income: Decimal.new("500")
        },
        %{
          dividend: %{ex_date: ~D[2025-07-15], amount: Decimal.new("0.50")},
          income: Decimal.new("500")
        }
      ]

      assert DividendsomaticWeb.StockLive.detect_dividend_frequency(divs) == "semi-annual"
    end

    test "should return unknown for single dividend" do
      divs = [
        %{
          dividend: %{ex_date: ~D[2025-06-01], amount: Decimal.new("1.00")},
          income: Decimal.new("1000")
        }
      ]

      assert DividendsomaticWeb.StockLive.detect_dividend_frequency(divs) == "unknown"
    end
  end
end
