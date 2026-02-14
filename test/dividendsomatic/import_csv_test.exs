defmodule Mix.Tasks.Import.CsvTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Portfolio
  alias ExUnit.CaptureIO
  alias Mix.Tasks.Import.Csv

  @valid_csv_content """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  """

  defp write_temp_csv(content) do
    tmp_dir = System.tmp_dir!()
    path = Path.join(tmp_dir, "import_csv_test_#{System.unique_integer([:positive])}.csv")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "run/1" do
    test "should import a valid CSV file and create a snapshot" do
      path = write_temp_csv(@valid_csv_content)

      Csv.run([path])

      snapshot = Portfolio.get_snapshot_by_date(~D[2026-01-28])
      assert snapshot != nil
      assert snapshot.date == ~D[2026-01-28]

      positions = Repo.preload(snapshot, :positions).positions
      assert length(positions) == 1
      assert hd(positions).symbol == "KESKOB"
    end

    test "should print error message when file does not exist" do
      output =
        CaptureIO.capture_io(fn ->
          Csv.run(["/tmp/nonexistent_file_#{System.unique_integer()}.csv"])
        end)

      assert output =~ "Failed to read file"
    end

    test "should print usage message when no arguments are provided" do
      output =
        CaptureIO.capture_io(fn ->
          Csv.run([])
        end)

      assert output =~ "Usage: mix import.csv path/to/file.csv"
    end

    test "should print usage message when empty string argument is provided" do
      output =
        CaptureIO.capture_io(fn ->
          Csv.run([""])
        end)

      assert output =~ "Failed to read file"
    end

    test "should print error message when CSV has invalid date format" do
      invalid_csv = """
      "ReportDate","CurrencyPrimary","Symbol"
      "not-a-date","EUR","KESKOB"
      """

      path = write_temp_csv(invalid_csv)

      output =
        CaptureIO.capture_io(fn ->
          Csv.run([path])
        end)

      assert output =~ "Error extracting date"
      assert output =~ "invalid date"
    end
  end
end
