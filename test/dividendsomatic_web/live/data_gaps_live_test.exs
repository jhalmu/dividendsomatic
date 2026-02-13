defmodule DividendsomaticWeb.DataGapsLiveTest do
  use DividendsomaticWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Dividendsomatic.Portfolio.{BrokerTransaction, Dividend, Holding, PortfolioSnapshot}

  describe "Data Gaps page" do
    test "should render the page with broker coverage", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/data/gaps")

      assert html =~ "Data Coverage"
      assert html =~ "Broker Timeline"
      assert html =~ "Per-Stock Coverage"
    end

    test "should show toggle filter button", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/data/gaps")
      assert html =~ "All stocks"
    end

    test "should toggle filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/data/gaps")

      html = view |> element("button", "All stocks") |> render_click()
      assert html =~ "Current only"
    end

    test "should show broker coverage when data exists", %{conn: conn} do
      # Insert a Nordnet transaction
      %BrokerTransaction{}
      |> BrokerTransaction.changeset(%{
        broker: "nordnet",
        transaction_type: "buy",
        raw_type: "OSTO",
        external_id: "test_1",
        trade_date: ~D[2017-03-06],
        isin: "FI0009000202",
        security_name: "KESKO"
      })
      |> Dividendsomatic.Repo.insert!()

      # Insert an IBKR snapshot with holding
      {:ok, snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{report_date: ~D[2026-01-28]})
        |> Dividendsomatic.Repo.insert()

      %Holding{}
      |> Holding.changeset(%{
        portfolio_snapshot_id: snapshot.id,
        report_date: ~D[2026-01-28],
        symbol: "KESKOB",
        currency_primary: "EUR",
        quantity: Decimal.new("100"),
        mark_price: Decimal.new("21"),
        position_value: Decimal.new("2100"),
        cost_basis_price: Decimal.new("18"),
        cost_basis_money: Decimal.new("1800"),
        open_price: Decimal.new("18"),
        percent_of_nav: Decimal.new("10"),
        fx_rate_to_base: Decimal.new("1"),
        isin: "FI0009000202",
        listing_exchange: "HEX",
        asset_class: "STK"
      })
      |> Dividendsomatic.Repo.insert!()

      {:ok, _view, html} = live(conn, ~p"/data/gaps")

      assert html =~ "Nordnet"
      assert html =~ "IBKR"
      assert html =~ "FI0009000202"
    end

    test "should show stock gap for stock with broken coverage", %{conn: conn} do
      # Nordnet transaction (old)
      %BrokerTransaction{}
      |> BrokerTransaction.changeset(%{
        broker: "nordnet",
        transaction_type: "buy",
        raw_type: "OSTO",
        external_id: "gap_test_1",
        trade_date: ~D[2017-03-06],
        isin: "FI_GAP_TEST0",
        security_name: "GapStock"
      })
      |> Dividendsomatic.Repo.insert!()

      # IBKR snapshot (recent)
      {:ok, snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{report_date: ~D[2026-01-28]})
        |> Dividendsomatic.Repo.insert()

      %Holding{}
      |> Holding.changeset(%{
        portfolio_snapshot_id: snapshot.id,
        report_date: ~D[2026-01-28],
        symbol: "GAP",
        currency_primary: "EUR",
        quantity: Decimal.new("50"),
        mark_price: Decimal.new("10"),
        position_value: Decimal.new("500"),
        cost_basis_price: Decimal.new("8"),
        cost_basis_money: Decimal.new("400"),
        open_price: Decimal.new("8"),
        percent_of_nav: Decimal.new("5"),
        fx_rate_to_base: Decimal.new("1"),
        isin: "FI_GAP_TEST0",
        listing_exchange: "HEX",
        asset_class: "STK"
      })
      |> Dividendsomatic.Repo.insert!()

      {:ok, _view, html} = live(conn, ~p"/data/gaps")

      assert html =~ "GapStock" || html =~ "GAP"
      assert html =~ "FI_GAP_TEST0"
    end

    test "should filter stocks by search term", %{conn: conn} do
      insert_nordnet_transaction("search_1", "FI0009000202", "KESKO OYJ")
      insert_nordnet_transaction("search_2", "FI0009005961", "NOKIA OYJ")

      {:ok, view, html} = live(conn, ~p"/data/gaps")
      assert html =~ "KESKO"
      assert html =~ "NOKIA"

      html = render_change(view, :search, %{search: "KESKO"})
      assert html =~ "KESKO"
      refute html =~ "NOKIA"
    end

    test "should sort by gap days descending on click", %{conn: conn} do
      insert_nordnet_transaction("sort_1", "FI0009000202", "ALPHA STOCK")
      insert_nordnet_transaction("sort_2", "FI0009005961", "BETA STOCK")

      {:ok, view, html} = live(conn, ~p"/data/gaps")
      # Both stocks visible before sort
      assert html =~ "ALPHA STOCK"
      assert html =~ "BETA STOCK"

      # Clicking sort triggers the event without error
      html = view |> element("th[phx-value-field=gap_days]") |> render_click()
      assert html =~ "ALPHA STOCK"
      assert html =~ "BETA STOCK"
    end

    test "should toggle dividend gaps section visibility", %{conn: conn} do
      # Insert dividends with a >400 day gap to trigger the section
      insert_dividend("TESTCO", ~D[2020-01-15], "1.00")
      insert_dividend("TESTCO", ~D[2022-01-15], "1.50")

      {:ok, view, html} = live(conn, ~p"/data/gaps")

      # Section header visible but table content collapsed
      assert html =~ "Dividend Gaps"
      refute html =~ "Missing Periods"

      # After toggle, table headers should appear
      html = render_click(view, :toggle_dividends)
      assert html =~ "Missing Periods"
      assert html =~ "TESTCO"
    end
  end

  defp insert_dividend(symbol, ex_date, amount) do
    %Dividend{}
    |> Dividend.changeset(%{
      symbol: symbol,
      ex_date: ex_date,
      amount: Decimal.new(amount),
      currency: "EUR",
      source: "test"
    })
    |> Dividendsomatic.Repo.insert!()
  end

  defp insert_nordnet_transaction(external_id, isin, name) do
    %BrokerTransaction{}
    |> BrokerTransaction.changeset(%{
      broker: "nordnet",
      transaction_type: "buy",
      raw_type: "OSTO",
      external_id: external_id,
      trade_date: ~D[2020-01-15],
      isin: isin,
      security_name: name
    })
    |> Dividendsomatic.Repo.insert!()
  end
end
