defmodule Dividendsomatic.DataIngestionTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.DataIngestion
  alias Dividendsomatic.DataIngestion.CsvDirectory
  alias Dividendsomatic.DataIngestion.GmailAdapter
  alias Dividendsomatic.Portfolio

  @valid_csv_content """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-01-28","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  """

  @valid_csv_content_jan29 """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-01-29","EUR","TELIA1","TELIA CO AB","COMMON","10000","3.858","38580","3.5871187","35871.187","3.5871187","16.34","2708.813","FWB","STK","1","SE0000667925","BBG000GJ9377"
  """

  @valid_csv_multi_holding """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-01-30","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","1000","21","21000","18.26459","18264.59","18.26459","8.90","2735.41","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  "2026-01-30","EUR","TELIA1","TELIA CO AB","COMMON","10000","3.858","38580","3.5871187","35871.187","3.5871187","16.34","2708.813","FWB","STK","1","SE0000667925","BBG000GJ9377"
  """

  # Helper to create a temporary directory with CSV files for testing
  defp setup_csv_dir(files) do
    tmp_base = System.tmp_dir!()

    dir =
      Path.join(tmp_base, "data_ingestion_test_#{System.unique_integer([:positive, :monotonic])}")

    File.mkdir_p!(dir)

    Enum.each(files, fn {filename, content} ->
      File.write!(Path.join(dir, filename), content)
    end)

    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # ──────────────────────────────────────────────────────────────────────
  # CsvDirectory - extract_report_date/1
  # ──────────────────────────────────────────────────────────────────────

  describe "CsvDirectory.extract_report_date/1" do
    test "should extract a valid ISO 8601 date from the first data row" do
      assert {:ok, ~D[2026-01-28]} = CsvDirectory.extract_report_date(@valid_csv_content)
    end

    test "should extract date from CSV with multiple data rows" do
      assert {:ok, ~D[2026-01-30]} = CsvDirectory.extract_report_date(@valid_csv_multi_holding)
    end

    test "should return error for CSV with only a header row" do
      header_only = ~s("ReportDate","Symbol","Quantity"\n)
      assert {:error, "no data rows"} = CsvDirectory.extract_report_date(header_only)
    end

    test "should return error for an empty string" do
      assert {:error, "no data rows"} = CsvDirectory.extract_report_date("")
    end

    test "should return error for an invalid date format in the first column" do
      invalid_csv = """
      "ReportDate","Symbol"
      "not-a-date","KESKOB"
      """

      assert {:error, "invalid date: " <> _} = CsvDirectory.extract_report_date(invalid_csv)
    end

    test "should return error for a non-ISO date format like DD/MM/YYYY" do
      non_iso_csv = """
      "ReportDate","Symbol"
      "28/01/2026","KESKOB"
      """

      assert {:error, "invalid date: " <> _} = CsvDirectory.extract_report_date(non_iso_csv)
    end

    test "should handle date without surrounding quotes" do
      unquoted_csv = """
      ReportDate,Symbol
      2026-02-15,KESKOB
      """

      assert {:ok, ~D[2026-02-15]} = CsvDirectory.extract_report_date(unquoted_csv)
    end

    test "should handle CSV with Windows-style line endings" do
      windows_csv = "\"ReportDate\",\"Symbol\"\r\n\"2026-03-01\",\"KESKOB\"\r\n"
      assert {:ok, ~D[2026-03-01]} = CsvDirectory.extract_report_date(windows_csv)
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # CsvDirectory - list_available/1
  # ──────────────────────────────────────────────────────────────────────

  describe "CsvDirectory.list_available/1" do
    test "should return entries for valid CSV files in the directory" do
      dir = setup_csv_dir([{"report_jan28.csv", @valid_csv_content}])

      assert {:ok, entries} = CsvDirectory.list_available(dir: dir)
      assert length(entries) == 1

      [entry] = entries
      assert entry.date == ~D[2026-01-28]
      assert entry.filename == "report_jan28.csv"
      assert entry.ref == Path.join(dir, "report_jan28.csv")
    end

    test "should return multiple entries sorted by filename" do
      dir =
        setup_csv_dir([
          {"b_jan29.csv", @valid_csv_content_jan29},
          {"a_jan28.csv", @valid_csv_content}
        ])

      assert {:ok, entries} = CsvDirectory.list_available(dir: dir)
      assert length(entries) == 2

      # Files should be sorted alphabetically
      assert Enum.at(entries, 0).filename == "a_jan28.csv"
      assert Enum.at(entries, 1).filename == "b_jan29.csv"
    end

    test "should return an empty list for a directory with no CSV files" do
      dir = setup_csv_dir([{"readme.txt", "not a csv"}, {"data.json", "{}"}])

      assert {:ok, []} = CsvDirectory.list_available(dir: dir)
    end

    test "should return an empty list for an empty directory" do
      dir = setup_csv_dir([])

      assert {:ok, []} = CsvDirectory.list_available(dir: dir)
    end

    test "should skip CSV files with invalid date content" do
      invalid_csv = """
      "ReportDate","Symbol"
      "not-a-date","KESKOB"
      """

      dir =
        setup_csv_dir([
          {"valid.csv", @valid_csv_content},
          {"invalid.csv", invalid_csv}
        ])

      assert {:ok, entries} = CsvDirectory.list_available(dir: dir)
      assert length(entries) == 1
      assert hd(entries).filename == "valid.csv"
    end

    test "should skip CSV files with only a header row" do
      header_only = ~s("ReportDate","Symbol","Quantity"\n)

      dir =
        setup_csv_dir([
          {"valid.csv", @valid_csv_content},
          {"header_only.csv", header_only}
        ])

      assert {:ok, entries} = CsvDirectory.list_available(dir: dir)
      assert length(entries) == 1
      assert hd(entries).filename == "valid.csv"
    end

    test "should only include .csv files, ignoring other extensions" do
      dir =
        setup_csv_dir([
          {"data.csv", @valid_csv_content},
          {"data.csv.bak", @valid_csv_content},
          {"data.txt", @valid_csv_content}
        ])

      assert {:ok, entries} = CsvDirectory.list_available(dir: dir)
      assert length(entries) == 1
      assert hd(entries).filename == "data.csv"
    end

    test "should return error when directory does not exist" do
      nonexistent = "/tmp/nonexistent_dir_#{System.unique_integer([:positive])}"

      assert {:error, {:directory_not_found, dir, _reason}} =
               CsvDirectory.list_available(dir: nonexistent)

      assert dir == nonexistent
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # CsvDirectory - fetch_data/1
  # ──────────────────────────────────────────────────────────────────────

  describe "CsvDirectory.fetch_data/1" do
    test "should return CSV file contents as a string" do
      dir = setup_csv_dir([{"data.csv", @valid_csv_content}])
      path = Path.join(dir, "data.csv")

      assert {:ok, content} = CsvDirectory.fetch_data(path)
      assert content == @valid_csv_content
    end

    test "should return error for a nonexistent file path" do
      assert {:error, :enoent} =
               CsvDirectory.fetch_data("/tmp/nonexistent_#{System.unique_integer()}.csv")
    end

    test "should return the exact file contents preserving whitespace" do
      csv_with_spaces = "  \"ReportDate\",\"Symbol\"  \n  \"2026-01-28\",\"KESKOB\"  \n"
      dir = setup_csv_dir([{"spaced.csv", csv_with_spaces}])
      path = Path.join(dir, "spaced.csv")

      assert {:ok, ^csv_with_spaces} = CsvDirectory.fetch_data(path)
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # CsvDirectory - source_name/0
  # ──────────────────────────────────────────────────────────────────────

  describe "CsvDirectory.source_name/0" do
    test "should return 'CSV Directory'" do
      assert CsvDirectory.source_name() == "CSV Directory"
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # GmailAdapter - source_name/0
  # ──────────────────────────────────────────────────────────────────────

  describe "GmailAdapter.source_name/0" do
    test "should return 'Gmail'" do
      assert GmailAdapter.source_name() == "Gmail"
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # GmailAdapter - list_available/1
  # ──────────────────────────────────────────────────────────────────────

  describe "GmailAdapter.list_available/1" do
    test "should return an empty list when Gmail OAuth is not configured" do
      # Gmail OAuth is not configured in test, so search_activity_flex_emails
      # returns {:ok, []} which means list_available also returns {:ok, []}
      assert {:ok, []} = GmailAdapter.list_available()
    end

    test "should accept options and still return empty list without OAuth" do
      assert {:ok, []} = GmailAdapter.list_available(max_results: 5, days_back: 7)
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # DataIngestion - import_new_from_source/2
  # ──────────────────────────────────────────────────────────────────────

  describe "DataIngestion.import_new_from_source/2 with CsvDirectory" do
    test "should import a single new CSV file and create a snapshot" do
      dir = setup_csv_dir([{"jan28.csv", @valid_csv_content}])

      assert {:ok, result} = DataIngestion.import_new_from_source(CsvDirectory, dir: dir)
      assert result.imported == 1
      assert result.skipped == 0
      assert result.failed == 0

      snapshot = Portfolio.get_snapshot_by_date(~D[2026-01-28])
      assert snapshot != nil
      assert snapshot.report_date == ~D[2026-01-28]
    end

    test "should import multiple CSV files from a directory" do
      dir =
        setup_csv_dir([
          {"jan28.csv", @valid_csv_content},
          {"jan29.csv", @valid_csv_content_jan29}
        ])

      assert {:ok, result} = DataIngestion.import_new_from_source(CsvDirectory, dir: dir)
      assert result.imported == 2
      assert result.skipped == 0
      assert result.failed == 0

      assert Portfolio.get_snapshot_by_date(~D[2026-01-28]) != nil
      assert Portfolio.get_snapshot_by_date(~D[2026-01-29]) != nil
    end

    test "should skip dates that already have existing snapshots" do
      # Pre-create a snapshot for jan28
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv_content, ~D[2026-01-28])

      dir =
        setup_csv_dir([
          {"jan28.csv", @valid_csv_content},
          {"jan29.csv", @valid_csv_content_jan29}
        ])

      assert {:ok, result} = DataIngestion.import_new_from_source(CsvDirectory, dir: dir)
      assert result.imported == 1
      assert result.skipped == 1
      assert result.failed == 0
    end

    test "should skip all entries when all dates already have snapshots" do
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv_content, ~D[2026-01-28])
      {:ok, _} = Portfolio.create_snapshot_from_csv(@valid_csv_content_jan29, ~D[2026-01-29])

      dir =
        setup_csv_dir([
          {"jan28.csv", @valid_csv_content},
          {"jan29.csv", @valid_csv_content_jan29}
        ])

      assert {:ok, result} = DataIngestion.import_new_from_source(CsvDirectory, dir: dir)
      assert result.imported == 0
      assert result.skipped == 2
      assert result.failed == 0
    end

    test "should return zero counts for an empty directory" do
      dir = setup_csv_dir([])

      assert {:ok, result} = DataIngestion.import_new_from_source(CsvDirectory, dir: dir)
      assert result.imported == 0
      assert result.skipped == 0
      assert result.failed == 0
    end

    test "should return error when directory does not exist" do
      nonexistent = "/tmp/nonexistent_ingestion_dir_#{System.unique_integer([:positive])}"

      assert {:error, {:directory_not_found, ^nonexistent, _}} =
               DataIngestion.import_new_from_source(CsvDirectory, dir: nonexistent)
    end

    test "should create snapshot with correct holdings from imported CSV" do
      dir = setup_csv_dir([{"multi.csv", @valid_csv_multi_holding}])

      assert {:ok, %{imported: 1}} = DataIngestion.import_new_from_source(CsvDirectory, dir: dir)

      snapshot = Portfolio.get_snapshot_by_date(~D[2026-01-30])
      assert snapshot != nil

      holdings = Repo.preload(snapshot, :holdings).holdings
      assert length(holdings) == 2

      symbols = Enum.map(holdings, & &1.symbol) |> Enum.sort()
      assert symbols == ["KESKOB", "TELIA1"]
    end
  end

  describe "DataIngestion.import_new_from_source/2 with GmailAdapter" do
    test "should return zero counts when Gmail is not configured" do
      assert {:ok, result} = DataIngestion.import_new_from_source(GmailAdapter)
      assert result.imported == 0
      assert result.skipped == 0
      assert result.failed == 0
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # DataIngestion - import_new_from_source/2 with a stub adapter
  # ──────────────────────────────────────────────────────────────────────

  describe "DataIngestion.import_new_from_source/2 with stub adapter" do
    defmodule FailingAdapter do
      @behaviour Dividendsomatic.DataIngestion

      @impl true
      def source_name, do: "Failing Adapter"

      @impl true
      def list_available(_opts), do: {:error, :connection_refused}

      @impl true
      def fetch_data(_ref), do: {:error, :fetch_failed}
    end

    defmodule EmptyAdapter do
      @behaviour Dividendsomatic.DataIngestion

      @impl true
      def source_name, do: "Empty Adapter"

      @impl true
      def list_available(_opts), do: {:ok, []}

      @impl true
      def fetch_data(_ref), do: {:error, :no_data}
    end

    defmodule BadFetchAdapter do
      @behaviour Dividendsomatic.DataIngestion

      @impl true
      def source_name, do: "Bad Fetch Adapter"

      @impl true
      def list_available(_opts) do
        {:ok, [%{date: ~D[2026-02-01], ref: "bad_ref"}]}
      end

      @impl true
      def fetch_data(_ref), do: {:error, :fetch_failed}
    end

    test "should return error when adapter's list_available fails" do
      assert {:error, :connection_refused} =
               DataIngestion.import_new_from_source(FailingAdapter)
    end

    test "should return zero counts when adapter returns empty list" do
      assert {:ok, result} = DataIngestion.import_new_from_source(EmptyAdapter)
      assert result.imported == 0
      assert result.skipped == 0
      assert result.failed == 0
    end

    test "should count as failed when fetch_data returns an error" do
      assert {:ok, result} = DataIngestion.import_new_from_source(BadFetchAdapter)
      assert result.imported == 0
      assert result.skipped == 0
      assert result.failed == 1
    end
  end
end
