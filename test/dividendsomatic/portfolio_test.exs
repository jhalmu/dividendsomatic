defmodule Dividendsomatic.PortfolioTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Portfolio

  describe "portfolio snapshots" do
    @valid_csv """
    "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
    "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
    "2026-01-28","EUR","TELIA1","TELIA CO AB","COMMON","10000","3.858","38580","3.5871187","35871.187","3.5871187","16.34","2708.813","FWB","STK","1","SE0000667925","BBG000GJ9377"
    """

    @valid_date ~D[2026-01-28]

    test "create_snapshot_from_csv/2 creates snapshot with holdings" do
      assert {:ok, {:ok, snapshot}} = Portfolio.create_snapshot_from_csv(@valid_csv, @valid_date)
      assert snapshot.report_date == @valid_date
      assert length(Repo.preload(snapshot, :holdings).holdings) == 2
    end

    test "get_latest_snapshot/0 returns most recent snapshot" do
      {:ok, {:ok, _}} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-27])
      {:ok, {:ok, latest}} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      result = Portfolio.get_latest_snapshot()
      assert result.report_date == latest.report_date
    end

    test "get_snapshot_by_date/1 finds specific snapshot" do
      {:ok, {:ok, snapshot}} = Portfolio.create_snapshot_from_csv(@valid_csv, @valid_date)

      result = Portfolio.get_snapshot_by_date(@valid_date)
      assert result.id == snapshot.id
    end

    test "get_previous_snapshot/1 returns earlier snapshot" do
      {:ok, {:ok, earlier}} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-27])
      {:ok, {:ok, _later}} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      result = Portfolio.get_previous_snapshot(~D[2026-01-28])
      assert result.id == earlier.id
    end

    test "get_next_snapshot/1 returns later snapshot" do
      {:ok, {:ok, _earlier}} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-27])
      {:ok, {:ok, later}} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      result = Portfolio.get_next_snapshot(~D[2026-01-27])
      assert result.id == later.id
    end

    test "get_previous_snapshot/1 returns nil when no earlier snapshot" do
      {:ok, {:ok, _}} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      result = Portfolio.get_previous_snapshot(~D[2026-01-28])
      assert is_nil(result)
    end

    test "get_next_snapshot/1 returns nil when no later snapshot" do
      {:ok, {:ok, _}} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])

      result = Portfolio.get_next_snapshot(~D[2026-01-28])
      assert is_nil(result)
    end
  end

  describe "holdings" do
    @valid_csv """
    "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
    "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
    """

    test "holdings have correct decimal values" do
      {:ok, {:ok, snapshot}} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])
      [holding] = Repo.preload(snapshot, :holdings).holdings

      assert Decimal.equal?(holding.quantity, Decimal.new("1000"))
      assert Decimal.equal?(holding.mark_price, Decimal.new("21"))
      assert Decimal.equal?(holding.position_value, Decimal.new("21000"))
      assert Decimal.equal?(holding.fifo_pnl_unrealized, Decimal.new("2735.41"))
    end

    test "holdings have correct string values" do
      {:ok, {:ok, snapshot}} = Portfolio.create_snapshot_from_csv(@valid_csv, ~D[2026-01-28])
      [holding] = Repo.preload(snapshot, :holdings).holdings

      assert holding.symbol == "KESKOB"
      assert holding.description == "KESKO OYJ-B SHS"
      assert holding.currency_primary == "EUR"
      assert holding.asset_class == "STK"
    end
  end
end
