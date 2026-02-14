defmodule Mix.Tasks.Import.Csv do
  @moduledoc """
  Import CSV file into database.

  Usage: mix import.csv path/to/file.csv
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio
  alias Dividendsomatic.Portfolio.CsvParser

  @shortdoc "Import portfolio CSV file"
  def run([file_path]) do
    Mix.Task.run("app.start")

    case File.read(file_path) do
      {:ok, csv_data} ->
        case CsvParser.extract_report_date(csv_data) do
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
            from(p in Dividendsomatic.Portfolio.Position,
              where: p.portfolio_snapshot_id == ^snapshot.id
            ),
            :count
          )

        IO.puts("✓ Successfully imported #{count} positions")

      {:error, changeset} ->
        IO.puts("✗ Error: #{inspect(changeset.errors)}")
    end
  end
end
