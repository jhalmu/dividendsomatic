defmodule Mix.Tasks.Import.Reimport do
  @moduledoc """
  One-time re-import tool: drops all snapshots and holdings, then re-imports
  from csv_data/ using the header-based CSV parser.

  Required after switching from positional to header-based parsing to ensure
  all historical data is correctly mapped.

  After re-import, snapshots are immutable historical records (append-only).

  Usage: mix import.reimport [directory]

  Defaults to `csv_data/` directory if no path given.
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio
  alias Dividendsomatic.Portfolio.{CsvParser, PortfolioSnapshot, Position}
  alias Dividendsomatic.Repo

  @shortdoc "Re-import all CSV data with header-based parser"
  def run(args) do
    Mix.Task.run("app.start")

    dir = List.first(args) || "csv_data"

    case File.ls(dir) do
      {:ok, files} ->
        csv_files =
          files
          |> Enum.filter(&String.ends_with?(&1, ".csv"))
          |> Enum.sort()

        count = length(csv_files)
        IO.puts("Re-import: found #{count} CSV files in #{dir}/")
        IO.puts("This will DELETE all existing snapshots and holdings.")
        IO.puts("")

        delete_all_data()
        import_all(csv_files, dir)

      {:error, reason} ->
        IO.puts("Error reading directory #{dir}: #{reason}")
    end
  end

  defp delete_all_data do
    {positions_count, _} = Repo.delete_all(Position)
    {snapshots_count, _} = Repo.delete_all(PortfolioSnapshot)
    IO.puts("Deleted #{snapshots_count} snapshots and #{positions_count} positions.")
    IO.puts("")
  end

  defp import_all(csv_files, dir) do
    results =
      Enum.map(csv_files, fn file ->
        path = Path.join(dir, file)
        import_file(path, file)
      end)

    imported = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 == :error))

    IO.puts("")
    IO.puts("Re-import complete: #{imported} imported, #{failed} failed")
  end

  defp import_file(path, filename) do
    case File.read(path) do
      {:ok, csv_data} ->
        case CsvParser.extract_report_date(csv_data) do
          {:ok, report_date} ->
            import_for_date(csv_data, report_date, filename)

          {:error, reason} ->
            IO.puts("  FAIL #{filename} (#{reason})")
            :error
        end

      {:error, reason} ->
        IO.puts("  FAIL #{filename} (#{reason})")
        :error
    end
  end

  defp import_for_date(csv_data, report_date, filename) do
    case Portfolio.create_snapshot_from_csv(csv_data, report_date) do
      {:ok, snapshot} ->
        count =
          Repo.aggregate(
            from(p in Position, where: p.portfolio_snapshot_id == ^snapshot.id),
            :count
          )

        IO.puts("  ok   #{filename} (#{report_date}, #{count} positions)")
        :ok

      {:error, _} ->
        IO.puts("  FAIL #{filename} (#{report_date})")
        :error
    end
  end
end
