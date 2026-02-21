defmodule Dividendsomatic.DataIngestion.CsvDirectory do
  @moduledoc """
  Data ingestion source for local CSV files in a directory.

  Scans a directory for CSV files, extracts report dates from the first
  data row, and provides them for import.

  ## Filename pattern

  Interactive Brokers Flex files:
  `flex.ACCOUNT.PortfolioForWww.YYYYMMDD.YYYYMMDD.csv`

  The date is also extracted from the CSV content (first data row, first column).
  """

  @behaviour Dividendsomatic.DataIngestion

  alias Dividendsomatic.Portfolio.CsvParser

  @default_dir "csv_data"

  @impl true
  def source_name, do: "CSV Directory"

  @impl true
  def list_available(opts \\ []) do
    dir = Keyword.get(opts, :dir, @default_dir)

    case File.ls(dir) do
      {:ok, files} ->
        entries =
          files
          |> Enum.filter(&String.ends_with?(&1, ".csv"))
          |> Enum.sort()
          |> Enum.flat_map(&entry_from_file(dir, &1))

        {:ok, entries}

      {:error, reason} ->
        {:error, {:directory_not_found, dir, reason}}
    end
  end

  defp entry_from_file(dir, filename) do
    path = Path.join(dir, filename)

    case extract_date_from_file(path) do
      {:ok, date} -> [%{date: date, ref: path, filename: filename}]
      {:error, _} -> []
    end
  end

  @impl true
  def fetch_data(path) when is_binary(path) do
    File.read(path)
  end

  @doc """
  Moves a processed CSV file to the archive directory.

  Files are archived to `data_archive/flex/` to keep the inbox clean.
  Returns `:ok` or `{:error, reason}`.
  """
  def archive_file(path, _opts \\ []) do
    archive_dir = Path.join([File.cwd!(), "data_archive", "flex"])

    with :ok <- File.mkdir_p(archive_dir) do
      dest = Path.join(archive_dir, Path.basename(path))
      File.rename(path, dest)
    end
  end

  @doc """
  Extracts the report date from CSV content using header-based parsing.

  Delegates to `CsvParser.extract_report_date/1`.
  """
  defdelegate extract_report_date(csv_data), to: CsvParser

  defp extract_date_from_file(path) do
    case File.read(path) do
      {:ok, csv_data} -> CsvParser.extract_report_date(csv_data)
      {:error, reason} -> {:error, reason}
    end
  end
end
