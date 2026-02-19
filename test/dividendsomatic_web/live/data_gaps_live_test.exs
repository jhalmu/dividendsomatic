defmodule DividendsomaticWeb.DataGapsLiveTest do
  use DividendsomaticWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Dividendsomatic.Portfolio.{
    DividendPayment,
    Instrument,
    InstrumentAlias,
    PortfolioSnapshot,
    Position,
    Trade
  }

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
      # Insert an IBKR snapshot with position
      {:ok, snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{date: ~D[2026-01-28], source: "ibkr_flex"})
        |> Dividendsomatic.Repo.insert()

      %Position{}
      |> Position.changeset(%{
        portfolio_snapshot_id: snapshot.id,
        date: ~D[2026-01-28],
        symbol: "KESKOB",
        currency: "EUR",
        quantity: Decimal.new("100"),
        price: Decimal.new("21"),
        value: Decimal.new("2100"),
        cost_price: Decimal.new("18"),
        cost_basis: Decimal.new("1800"),
        weight: Decimal.new("10"),
        fx_rate: Decimal.new("1"),
        isin: "FI0009000202",
        exchange: "HEX",
        asset_class: "STK"
      })
      |> Dividendsomatic.Repo.insert!()

      # Insert a trade for IBKR trade coverage
      {instrument, _alias} = get_or_create_instrument("KESKOB", "FI0009000202")

      %Trade{}
      |> Trade.changeset(%{
        external_id: "test-trade-cov-1",
        instrument_id: instrument.id,
        trade_date: ~D[2021-03-06],
        quantity: Decimal.new("100"),
        price: Decimal.new("18"),
        amount: Decimal.new("-1800"),
        currency: "EUR"
      })
      |> Dividendsomatic.Repo.insert!()

      {:ok, _view, html} = live(conn, ~p"/data/gaps")

      assert html =~ "IBKR"
      # Trade data shows in the broker timeline
      assert html =~ "2021-03-06"
    end

    test "should toggle dividend gaps section visibility", %{conn: conn} do
      # Insert dividend payments with a >400 day gap to trigger the section
      {instrument, _alias} = get_or_create_instrument("TESTCO", "FI9999999999")

      insert_dividend_payment(instrument.id, ~D[2020-01-15], "100")
      insert_dividend_payment(instrument.id, ~D[2022-01-15], "150")

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

  defp get_or_create_instrument(symbol, isin) do
    case Dividendsomatic.Repo.get_by(Instrument, isin: isin) do
      nil ->
        {:ok, instrument} =
          %Instrument{}
          |> Instrument.changeset(%{isin: isin, name: "#{symbol} Corp"})
          |> Dividendsomatic.Repo.insert()

        {:ok, alias_record} =
          %InstrumentAlias{}
          |> InstrumentAlias.changeset(%{
            instrument_id: instrument.id,
            symbol: symbol,
            source: "test"
          })
          |> Dividendsomatic.Repo.insert()

        {instrument, alias_record}

      instrument ->
        alias_record =
          Dividendsomatic.Repo.get_by(InstrumentAlias,
            instrument_id: instrument.id,
            symbol: symbol
          )

        {instrument, alias_record}
    end
  end

  defp insert_dividend_payment(instrument_id, pay_date, amount) do
    %DividendPayment{}
    |> DividendPayment.changeset(%{
      external_id: "test-div-#{System.unique_integer([:positive])}",
      instrument_id: instrument_id,
      pay_date: pay_date,
      gross_amount: Decimal.new(amount),
      net_amount: Decimal.new(amount),
      currency: "EUR"
    })
    |> Dividendsomatic.Repo.insert!()
  end
end
