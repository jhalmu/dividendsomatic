defmodule Mix.Tasks.Import.Batch do
  @moduledoc """
  Batch import all CSV files from a directory.

  Imports files in date order, skipping dates that already have snapshots.

  Usage: mix import.batch [directory]

  Defaults to `csv_data/` directory if no path given.
  """
  use Mix.Task

  alias Dividendsomatic.Portfolio.CsvParser

  @shortdoc "Batch import CSV files from directory"
  def run(args) do
    Mix.Task.run("app.start")

    dir = List.first(args) || "csv_data"

    case File.ls(dir) do
      {:ok, files} ->
        csv_files =
          files
          |> Enum.filter(&String.ends_with?(&1, ".csv"))
          |> Enum.sort()

        IO.puts("Found #{length(csv_files)} CSV files in #{dir}/")

        results =
          Enum.map(csv_files, fn file ->
            path = Path.join(dir, file)
            import_file(path, file)
          end)

        imported = Enum.count(results, &(&1 == :ok))
        skipped = Enum.count(results, &(&1 == :skipped))
        failed = Enum.count(results, &(&1 == :error))

        IO.puts(
          "\nBatch import complete: #{imported} imported, #{skipped} skipped, #{failed} failed"
        )

      {:error, reason} ->
        IO.puts("Error reading directory #{dir}: #{reason}")
    end
  end

  defp import_file(path, filename) do
    case File.read(path) do
      {:ok, csv_data} -> import_csv_data(csv_data, filename)
      {:error, reason} -> fail(filename, reason)
    end
  end

  defp import_csv_data(csv_data, filename) do
    case CsvParser.extract_report_date(csv_data) do
      {:ok, report_date} -> import_for_date(csv_data, report_date, filename)
      {:error, reason} -> fail(filename, reason)
    end
  end

  defp import_for_date(csv_data, report_date, filename) do
    if Dividendsomatic.Portfolio.get_snapshot_by_date(report_date) do
      IO.puts("  skip #{filename} (#{report_date} already exists)")
      :skipped
    else
      case Dividendsomatic.Portfolio.create_snapshot_from_csv(csv_data, report_date) do
        {:ok, _snapshot} ->
          IO.puts("  ok   #{filename} (#{report_date})")
          :ok

        {:error, _} ->
          fail(filename, report_date)
      end
    end
  end

  defp fail(filename, reason) do
    IO.puts("  FAIL #{filename} (#{reason})")
    :error
  end
end
