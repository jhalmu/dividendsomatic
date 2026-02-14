defmodule Dividendsomatic.PortfolioFxTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Portfolio

  describe "FX conversion in chart data" do
    test "should convert position values to base currency" do
      # EUR: 10000 * 1.0 = 10000, USD: 10000 * 0.85 = 8500, total = 18500
      {:ok, snapshot} =
        %Portfolio.PortfolioSnapshot{}
        |> Portfolio.PortfolioSnapshot.changeset(%{
          date: ~D[2026-01-01],
          source: "test",
          total_value: Decimal.new("18500"),
          total_cost: Decimal.new("18500")
        })
        |> Repo.insert()

      # EUR position (fx_rate = 1.0)
      insert_position(snapshot.id, "NESTE", 100, "10000", "1")
      # USD position (fx_rate = 0.85)
      insert_position(snapshot.id, "ARCC", 500, "10000", "0.85")

      chart_data = Portfolio.get_all_chart_data()
      assert length(chart_data) == 1

      point = hd(chart_data)
      assert_in_delta point.value_float, 18_500.0, 0.01
    end

    test "should convert cost basis to base currency" do
      # cost_basis: 4000 * 0.9 = 3600
      {:ok, snapshot} =
        %Portfolio.PortfolioSnapshot{}
        |> Portfolio.PortfolioSnapshot.changeset(%{
          date: ~D[2026-01-02],
          source: "test",
          total_value: Decimal.new("4500"),
          total_cost: Decimal.new("3600")
        })
        |> Repo.insert()

      insert_position_with_cost(snapshot.id, "TEST", "5000", "4000", "0.9")

      chart_data = Portfolio.get_all_chart_data()
      point = Enum.find(chart_data, &(&1.date == ~D[2026-01-02]))

      assert_in_delta point.cost_basis_float, 3600.0, 0.01
    end
  end

  describe "get_growth_stats/1" do
    test "should compare first snapshot to given snapshot" do
      {:ok, _snap1} = create_snapshot_with_value(~D[2026-01-01], "10000", "1")
      {:ok, _snap2} = create_snapshot_with_value(~D[2026-01-02], "11000", "1")
      {:ok, _snap3} = create_snapshot_with_value(~D[2026-01-03], "12000", "1")

      # Load snap3 with positions preloaded
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

  defp insert_position(snapshot_id, symbol, qty, value, fx_rate) do
    %Portfolio.Position{}
    |> Portfolio.Position.changeset(%{
      portfolio_snapshot_id: snapshot_id,
      date: Date.utc_today(),
      symbol: symbol,
      currency: "USD",
      quantity: qty,
      price: "10",
      value: value,
      cost_price: "10",
      cost_basis: value,
      weight: "50",
      exchange: "NYSE",
      asset_class: "STK",
      fx_rate: fx_rate
    })
    |> Repo.insert!()
  end

  defp insert_position_with_cost(snapshot_id, symbol, value, cost, fx_rate) do
    %Portfolio.Position{}
    |> Portfolio.Position.changeset(%{
      portfolio_snapshot_id: snapshot_id,
      date: Date.utc_today(),
      symbol: symbol,
      currency: "USD",
      quantity: "100",
      price: "50",
      value: value,
      cost_price: "40",
      cost_basis: cost,
      weight: "100",
      exchange: "NYSE",
      asset_class: "STK",
      fx_rate: fx_rate
    })
    |> Repo.insert!()
  end

  defp create_snapshot_with_value(date, value, fx_rate) do
    {:ok, snapshot} =
      %Portfolio.PortfolioSnapshot{}
      |> Portfolio.PortfolioSnapshot.changeset(%{date: date, source: "test"})
      |> Repo.insert()

    insert_position(snapshot.id, "TEST-#{date}", 100, value, fx_rate)
    {:ok, snapshot}
  end
end
