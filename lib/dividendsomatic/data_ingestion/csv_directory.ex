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

  defp extract_date_from_file(path) do
    case File.read(path) do
      {:ok, csv_data} -> extract_report_date(csv_data)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def extract_report_date(csv_data) do
    lines = String.split(csv_data, "\n", trim: true)

    case Enum.drop(lines, 1) do
      [first_data_line | _] ->
        [date_str | _] = String.split(first_data_line, ",", parts: 2)
        date_str = String.trim(date_str, "\"")

        case Date.from_iso8601(date_str) do
          {:ok, date} -> {:ok, date}
          {:error, _} -> {:error, "invalid date: #{date_str}"}
        end

      [] ->
        {:error, "no data rows"}
    end
  end
end
