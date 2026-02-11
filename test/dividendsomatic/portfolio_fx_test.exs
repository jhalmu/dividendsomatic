defmodule Dividendsomatic.PortfolioFxTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Portfolio

  describe "FX conversion in chart data" do
    test "should convert position values to base currency" do
      # Create snapshot with holdings in different currencies
      {:ok, snapshot} =
        %Portfolio.PortfolioSnapshot{}
        |> Portfolio.PortfolioSnapshot.changeset(%{report_date: ~D[2026-01-01]})
        |> Repo.insert()

      # EUR holding (fx_rate = 1.0)
      insert_holding(snapshot.id, "NESTE", 100, "10000", "1")
      # USD holding (fx_rate = 0.85)
      insert_holding(snapshot.id, "ARCC", 500, "10000", "0.85")

      chart_data = Portfolio.get_all_chart_data()
      assert length(chart_data) == 1

      point = hd(chart_data)
      # EUR: 10000 * 1.0 = 10000, USD: 10000 * 0.85 = 8500, total = 18500
      assert_in_delta point.value_float, 18_500.0, 0.01
    end

    test "should convert cost basis to base currency" do
      {:ok, snapshot} =
        %Portfolio.PortfolioSnapshot{}
        |> Portfolio.PortfolioSnapshot.changeset(%{report_date: ~D[2026-01-02]})
        |> Repo.insert()

      insert_holding_with_cost(snapshot.id, "TEST", "5000", "4000", "0.9")

      chart_data = Portfolio.get_all_chart_data()
      point = Enum.find(chart_data, &(&1.date == ~D[2026-01-02]))

      # cost_basis: 4000 * 0.9 = 3600
      assert_in_delta point.cost_basis_float, 3600.0, 0.01
    end
  end

  describe "get_growth_stats/1" do
    test "should compare first snapshot to given snapshot" do
      {:ok, snap1} = create_snapshot_with_value(~D[2026-01-01], "10000", "1")
      {:ok, _snap2} = create_snapshot_with_value(~D[2026-01-02], "11000", "1")
      {:ok, snap3} = create_snapshot_with_value(~D[2026-01-03], "12000", "1")

      # Load snap3 with holdings preloaded
      snap3 = Portfolio.get_snapshot_by_date(~D[2026-01-03])
      stats = Portfolio.get_growth_stats(snap3)

      assert stats.first_date == ~D[2026-01-01]
      assert stats.latest_date == ~D[2026-01-03]
      assert Decimal.compare(stats.absolute_change, Decimal.new("2000")) == :eq
    end

    test "should default to latest snapshot when nil" do
      {:ok, _snap1} = create_snapshot_with_value(~D[2026-01-04], "10000", "1")
      {:ok, _snap2} = create_snapshot_with_value(~D[2026-01-05], "15000", "1")

      stats = Portfolio.get_growth_stats()

      assert stats.latest_date == ~D[2026-01-05]
      assert Decimal.compare(stats.absolute_change, Decimal.new("5000")) == :eq
    end
  end

  defp insert_holding(snapshot_id, symbol, qty, value, fx_rate) do
    %Portfolio.Holding{}
    |> Portfolio.Holding.changeset(%{
      portfolio_snapshot_id: snapshot_id,
      report_date: Date.utc_today(),
      symbol: symbol,
      currency_primary: "USD",
      quantity: qty,
      mark_price: "10",
      position_value: value,
      cost_basis_price: "10",
      cost_basis_money: value,
      percent_of_nav: "50",
      listing_exchange: "NYSE",
      asset_class: "STK",
      fx_rate_to_base: fx_rate
    })
    |> Repo.insert!()
  end

  defp insert_holding_with_cost(snapshot_id, symbol, value, cost, fx_rate) do
    %Portfolio.Holding{}
    |> Portfolio.Holding.changeset(%{
      portfolio_snapshot_id: snapshot_id,
      report_date: Date.utc_today(),
      symbol: symbol,
      currency_primary: "USD",
      quantity: "100",
      mark_price: "50",
      position_value: value,
      cost_basis_price: "40",
      cost_basis_money: cost,
      percent_of_nav: "100",
      listing_exchange: "NYSE",
      asset_class: "STK",
      fx_rate_to_base: fx_rate
    })
    |> Repo.insert!()
  end

  defp create_snapshot_with_value(date, value, fx_rate) do
    {:ok, snapshot} =
      %Portfolio.PortfolioSnapshot{}
      |> Portfolio.PortfolioSnapshot.changeset(%{report_date: date})
      |> Repo.insert()

    insert_holding(snapshot.id, "TEST-#{date}", 100, value, fx_rate)
    {:ok, snapshot}
  end
end
