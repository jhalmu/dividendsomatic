defmodule Mix.Tasks.Import.Csv do
  @moduledoc """
  Import CSV file into database.

  Usage: mix import.csv path/to/file.csv
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio

  @shortdoc "Import portfolio CSV file"
  def run([file_path]) do
    Mix.Task.run("app.start")

    case File.read(file_path) do
      {:ok, csv_data} ->
        case extract_report_date(csv_data) do
          {:ok, report_date} ->
            import_csv(csv_data, report_date)

          {:error, reason} ->
            IO.puts("✗ Error extracting date: #{reason}")
        end

      {:error, reason} ->
        IO.puts("✗ Failed to read file: #{reason}")
    end
  end

  def run(_) do
    IO.puts("Usage: mix import.csv path/to/file.csv")
  end

  defp import_csv(csv_data, report_date) do
    IO.puts("Importing snapshot for #{report_date}...")

    case Portfolio.create_snapshot_from_csv(csv_data, report_date) do
      {:ok, snapshot} ->
        count =
          Dividendsomatic.Repo.aggregate(
            from(h in Dividendsomatic.Portfolio.Holding,
              where: h.portfolio_snapshot_id == ^snapshot.id
            ),
            :count
          )

        IO.puts("✓ Successfully imported #{count} holdings")

      {:error, changeset} ->
        IO.puts("✗ Error: #{inspect(changeset.errors)}")
    end
  end

  defp extract_report_date(csv_data) do
    lines = String.split(csv_data, "\n", trim: true)

    case Enum.drop(lines, 1) do
      [first_data_line | _] ->
        parse_date_from_line(first_data_line)

      [] ->
        {:error, "CSV has no data rows"}
    end
  end

  defp parse_date_from_line(line) do
    [date_str | _] = String.split(line, ",", parts: 2)
    date_str = String.trim(date_str, "\"")

    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        {:ok, date}

      {:error, _} ->
        {:error, "Invalid date format: #{date_str} (expected ISO8601 like 2026-01-28)"}
    end
  end
end
