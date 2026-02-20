defmodule Dividendsomatic.DataIngestion.FlexImportOrchestratorTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.DataIngestion.FlexImportOrchestrator

  @moduletag :tmp_dir

  @cash_report_csv """
  "ClientAccountID","AccountAlias","Model","CurrencyPrimary","LevelOfDetail","FromDate","ToDate","StartingCash","Commissions","Deposits/Withdrawals","Dividends","BrokerInterest","OtherFees","EndingCash"
  "U7299935","","","EUR","BaseCurrency","2026-01-01","2026-02-19","-264532.12","-198.45","0","1234.56","-789.01","0","-264285.02"
  "U7299935","","","EUR","BASE_SUMMARY","2026-01-01","2026-02-19","-264532.12","-198.45","0","1234.56","-789.01","0","-264285.02"
  """

  describe "import_file/2" do
    test "should route cash report and extract BASE_SUMMARY", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "Actions.csv")
      File.write!(path, @cash_report_csv)

      assert {:ok, :cash_report, summary} = FlexImportOrchestrator.import_file(path)
      assert summary.level == "BASE_SUMMARY"
      assert summary.dividends == "1234.56"
      assert summary.interest == "-789.01"
      assert summary.starting_cash == "-264532.12"
      assert summary.ending_cash == "-264285.02"
    end

    test "should skip unknown CSV types", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "random.csv")
      File.write!(path, ~s("Foo","Bar","Baz"\n"1","2","3"))

      assert {:skipped, :unknown, _msg} = FlexImportOrchestrator.import_file(path)
    end

    test "should return error for unreadable file" do
      assert {:error, _msg} = FlexImportOrchestrator.import_file("/nonexistent/file.csv")
    end
  end

  describe "import_all/1" do
    test "should process all CSV files in directory", %{tmp_dir: tmp_dir} do
      # Write a cash report CSV (no DB needed)
      File.write!(Path.join(tmp_dir, "cash_report.csv"), @cash_report_csv)

      # Write an unknown CSV (should be skipped)
      File.write!(Path.join(tmp_dir, "unknown.csv"), ~s("Foo","Bar"\n"1","2"))

      assert {:ok, summary} = FlexImportOrchestrator.import_all(dir: tmp_dir)
      assert summary.cash_report == 1
      assert summary.skipped == 1
      assert summary.errors == 0
    end

    test "should return error for non-existent directory" do
      assert {:error, {:directory_not_found, _, _}} =
               FlexImportOrchestrator.import_all(dir: "/nonexistent/dir")
    end

    test "should handle empty directory", %{tmp_dir: tmp_dir} do
      assert {:ok, summary} = FlexImportOrchestrator.import_all(dir: tmp_dir)
      assert summary.portfolio == 0
      assert summary.skipped == 0
    end

    test "should ignore non-CSV files", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "notes.txt"), "not a csv")
      File.write!(Path.join(tmp_dir, "report.pdf"), "binary data")

      assert {:ok, summary} = FlexImportOrchestrator.import_all(dir: tmp_dir)
      assert summary.portfolio == 0
      assert summary.skipped == 0
    end
  end
end
