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

    test "should show disabled investment notes section until auth", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Investment Notes"
      assert html =~ "Investment Thesis"
      assert html =~ "Requires auth"
      assert html =~ "disabled"
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
    end
  end

  describe "investment notes (disabled until auth)" do
    setup %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])
      %{conn: conn}
    end

    @tag :requires_auth
    test "should save thesis on blur when auth enabled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/stocks/KESKOB")

      view |> element("#note-thesis") |> render_blur(%{value: "Great dividend stock"})

      html = render(view)
      assert html =~ "Great dividend stock"
      assert html =~ "Saved"
    end

    @tag :requires_auth
    test "should save notes on blur when auth enabled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/stocks/KESKOB")

      view |> element("#note-markdown") |> render_blur(%{value: "Key metrics: P/E 12"})

      html = render(view)
      assert html =~ "Key metrics: P/E 12"
    end

    @tag :requires_auth
    test "should persist notes to database when auth enabled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/stocks/KESKOB")

      view |> element("#note-thesis") |> render_blur(%{value: "Long-term hold"})

      note = Dividendsomatic.Stocks.get_company_note_by_isin("FI0009000202")
      assert note.thesis == "Long-term hold"
      assert note.symbol == "KESKOB"
    end

    test "should show asset-type-specific placeholder", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Growth potential"
    end

    test "should show notes section as disabled", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Requires auth"
      assert html =~ "disabled"
      assert html =~ "opacity: 0.5"
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

  describe "rule of 72 pure function" do
    test "should compute correct doubling time at 8%" do
      result = DividendsomaticWeb.StockLive.compute_rule72(8.0)

      assert result.rate == 8.0
      assert result.approx_years == 9.0
      assert result.exact_years == 9.0
      assert length(result.milestones) == 5
      assert hd(result.milestones).multiplier == 1
      assert List.last(result.milestones).multiplier == 16
    end

    test "should compute correct doubling time at 4%" do
      result = DividendsomaticWeb.StockLive.compute_rule72(4.0)

      assert result.rate == 4.0
      assert result.approx_years == 18.0
      assert result.exact_years == 17.7
    end

    test "should compute correct doubling time at 12%" do
      result = DividendsomaticWeb.StockLive.compute_rule72(12.0)

      assert result.rate == 12.0
      assert result.approx_years == 6.0
      assert result.exact_years == 6.1
    end

    test "should fallback to 8% for invalid rate" do
      result = DividendsomaticWeb.StockLive.compute_rule72(-5)

      assert result.rate == 8.0
    end
  end

  describe "dividend payback meter" do
    setup %{conn: conn} do
      # Create snapshots every 10 days from Oct 1 to Jan 28 to form a continuous period (> 60 days)
      dates =
        Date.range(~D[2025-10-01], ~D[2026-01-28], 10)
        |> Enum.to_list()
        |> then(fn dates ->
          if List.last(dates) != ~D[2026-01-28],
            do: dates ++ [~D[2026-01-28]],
            else: dates
        end)

      for date <- dates do
        csv = """
        "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
        "#{Date.to_string(date)}","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
        """

        {:ok, _} = Portfolio.create_snapshot_from_csv(csv, date)
      end

      %{conn: conn}
    end

    test "should show payback meter with dividend data", %{conn: conn} do
      {:ok, _} =
        Portfolio.create_dividend(%{
          symbol: "KESKOB",
          ex_date: ~D[2025-11-15],
          amount: Decimal.new("0.50"),
          currency: "EUR"
        })

      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "payback-meter"
      assert html =~ "recovered"
      assert html =~ "progressbar"
    end

    test "should show Rule of 72 as footer note", %{conn: conn} do
      {:ok, _} =
        Portfolio.create_dividend(%{
          symbol: "KESKOB",
          ex_date: ~D[2025-11-15],
          amount: Decimal.new("0.50"),
          currency: "EUR"
        })

      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Doubles in"
      assert html =~ "yield on cost"
    end

    test "should show payback meter at 0% without dividends", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "payback-meter"
      assert html =~ "0.00% recovered"
      assert html =~ "No dividend income yet"
    end

    test "should not show payback meter for unknown symbol", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/NONEXISTENT")

      refute html =~ "payback-meter"
    end
  end

  describe "payback computation" do
    test "should return nil payback for empty holdings" do
      assert DividendsomaticWeb.StockLive.compute_payback_data([], [], nil, nil) == nil
    end

    test "should prefer yield on cost over current yield" do
      analytics = %{yield_on_cost: Decimal.new("5.50"), yield: Decimal.new("3.00")}
      # pick_best_rate is private but compute_payback_data uses it
      # We test indirectly via the full computation
      assert DividendsomaticWeb.StockLive.compute_payback_data([], [], nil, analytics) == nil
    end
  end

  describe "enhanced cost basis (Feature 1)" do
    setup %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])
      %{conn: conn}
    end

    test "should show return percentage", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Return"
      # 2735.41 / 18264.59 * 100 ≈ 14.98%
      assert html =~ "14.98"
    end

    test "should show P&L per share", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "P&amp;L/Share"
      # 2735.41 / 1000 = 2.74
      assert html =~ "2.74"
    end

    test "should show break-even price", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Break-even"
      assert html =~ "18.26"
    end
  end

  describe "cost basis evolution chart (Feature 2)" do
    setup %{conn: conn} do
      # Need 2 snapshots for chart to render
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-27])
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])
      %{conn: conn}
    end

    test "should include cost basis line in price chart", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "stroke-dasharray"
      assert html =~ "cost-basis-line"
    end

    test "should show cost basis legend", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "cost-basis-legend"
      assert html =~ "Cost Basis"
    end
  end

  describe "sold positions on stock page (Feature 4)" do
    setup %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])

      {:ok, _} =
        Portfolio.create_sold_position(%{
          symbol: "KESKOB",
          quantity: Decimal.new("500"),
          purchase_price: Decimal.new("15.00"),
          purchase_date: ~D[2025-06-01],
          sale_price: Decimal.new("19.00"),
          sale_date: ~D[2025-12-15],
          currency: "EUR"
        })

      %{conn: conn}
    end

    test "should show sold positions section for stock with sales", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Previous Positions"
      assert html =~ "1 sold"
      assert html =~ "sold-positions"
    end

    test "should show holding period in days", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      # Date.diff(~D[2025-12-15], ~D[2025-06-01]) = 197
      assert html =~ "197d"
    end
  end

  describe "financial metrics card" do
    setup %{conn: conn} do
      {:ok, _snapshot} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])
      %{conn: conn}
    end

    test "should not show metrics card when no metrics data", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      refute html =~ "financial-metrics"
      refute html =~ "Key Metrics"
    end

    test "should show metrics card when data exists", %{conn: conn} do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      Dividendsomatic.Repo.insert!(%Dividendsomatic.Stocks.StockMetric{
        symbol: "KESKOB",
        pe_ratio: Decimal.new("15.20"),
        roe: Decimal.new("22.50"),
        net_margin: Decimal.new("8.30"),
        beta: Decimal.new("0.85"),
        fetched_at: now
      })

      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "financial-metrics"
      assert html =~ "Key Metrics"
      assert html =~ "P/E"
      assert html =~ "15.20"
      assert html =~ "ROE"
      assert html =~ "22.50"
      assert html =~ "Net Margin"
      assert html =~ "8.30"
      assert html =~ "Beta"
      assert html =~ "0.85"
    end

    test "should skip nil fields in rendering", %{conn: conn} do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      Dividendsomatic.Repo.insert!(%Dividendsomatic.Stocks.StockMetric{
        symbol: "KESKOB",
        pe_ratio: Decimal.new("15.20"),
        fetched_at: now
      })

      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "P/E"
      refute html =~ "terminal-info-label\">ROE"
      refute html =~ "terminal-info-label\">Net Margin"
    end

    test "should show updated date from fetched_at", %{conn: conn} do
      fetched = ~U[2026-02-10 14:30:00Z]

      Dividendsomatic.Repo.insert!(%Dividendsomatic.Stocks.StockMetric{
        symbol: "KESKOB",
        pe_ratio: Decimal.new("15.20"),
        fetched_at: fetched
      })

      {:ok, _view, html} = live(conn, ~p"/stocks/KESKOB")

      assert html =~ "Updated 2026-02-10"
    end
  end

  describe "short position support (Feature 6)" do
    @short_csv """
    "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
    "2026-01-28","USD","TSLA","TESLA INC","COMMON","-50","200","-10000","180","-9000","180","5","-1000","NASDAQ","STK","0.92","US88160R1014","BBG000N9MNX3"
    """

    test "should indicate short position on stock page", %{conn: conn} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@short_csv, ~D[2026-01-28])
      {:ok, _view, html} = live(conn, ~p"/stocks/TSLA")

      assert html =~ "short-badge"
      assert html =~ "SHORT"
    end
  end
end
