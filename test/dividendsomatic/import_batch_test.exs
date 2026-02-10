defmodule Mix.Tasks.Import.BatchTest do
  use Dividendsomatic.DataCase

  import ExUnit.CaptureIO

  alias Dividendsomatic.Portfolio
  alias Mix.Tasks.Import.Batch

  @csv_data """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  """

  @csv_data_alt """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-01-29","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","22","22000","18.26459","18264.59","18.26459","8.90","3735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  """

  setup do
    dir = Path.join(System.tmp_dir!(), "batch_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf!(dir) end)

    %{dir: dir}
  end

  describe "run/1" do
    test "should import CSV files from directory", %{dir: dir} do
      File.write!(Path.join(dir, "data1.csv"), @csv_data)

      output =
        capture_io(fn ->
          Batch.run([dir])
        end)

      assert output =~ "Found 1 CSV files"
      assert output =~ "1 imported"
      assert Portfolio.get_snapshot_by_date(~D[2026-01-28])
    end

    test "should import multiple CSV files", %{dir: dir} do
      File.write!(Path.join(dir, "data1.csv"), @csv_data)
      File.write!(Path.join(dir, "data2.csv"), @csv_data_alt)

      output =
        capture_io(fn ->
          Batch.run([dir])
        end)

      assert output =~ "Found 2 CSV files"
      assert output =~ "2 imported"
    end

    test "should skip existing snapshots", %{dir: dir} do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@csv_data, ~D[2026-01-28])
      File.write!(Path.join(dir, "data1.csv"), @csv_data)

      output =
        capture_io(fn ->
          Batch.run([dir])
        end)

      assert output =~ "1 skipped"
      assert output =~ "skip"
    end

    test "should handle empty directory", %{dir: dir} do
      output =
        capture_io(fn ->
          Batch.run([dir])
        end)

      assert output =~ "Found 0 CSV files"
      assert output =~ "0 imported, 0 skipped, 0 failed"
    end

    test "should handle nonexistent directory" do
      output =
        capture_io(fn ->
          Batch.run([
            "/tmp/nonexistent_batch_dir_#{System.unique_integer([:positive])}"
          ])
        end)

      assert output =~ "Error reading directory"
    end

    test "should handle CSV with invalid date", %{dir: dir} do
      File.write!(Path.join(dir, "bad.csv"), "Header\nnot-a-date,data")

      output =
        capture_io(fn ->
          Batch.run([dir])
        end)

      assert output =~ "FAIL"
    end

    test "should use default directory when no args given" do
      output =
        capture_io(fn ->
          Batch.run([])
        end)

      # csv_data directory may or may not exist, but should not crash
      assert is_binary(output)
    end
  end
end
