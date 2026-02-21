defmodule Mix.Tasks.Check.Sqlite do
  @moduledoc """
  Check SQLite databases for historical data not yet in PostgreSQL.

  ## Usage

      mix check.sqlite               # Check db/*.db files
      mix check.sqlite --export      # Export unique records to data_revisited/
  """
  use Mix.Task

  @shortdoc "Check SQLite databases for unique historical data"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    db_dir = "db"

    case File.ls(db_dir) do
      {:ok, files} ->
        db_files = Enum.filter(files, &String.ends_with?(&1, ".db"))
        Mix.shell().info("Found #{length(db_files)} SQLite databases in #{db_dir}/")

        Enum.each(db_files, fn file ->
          path = Path.join(db_dir, file)
          check_database(path, file)
        end)

        if "--export" in args, do: export_findings()

      {:error, _} ->
        Mix.shell().info("No db/ directory found")
    end
  end

  defp check_database(path, filename) do
    Mix.shell().info("\n=== #{filename} ===")

    # List tables and counts
    case System.cmd("sqlite3", [path, ".tables"], stderr_to_stdout: true) do
      {output, 0} ->
        tables = output |> String.split() |> Enum.reject(&(&1 == ""))
        Mix.shell().info("Tables: #{Enum.join(tables, ", ")}")

        Enum.each(tables, fn table ->
          count_rows(path, table)
        end)

        # Check dividend date ranges
        if "dividends" in tables do
          check_dividends(path)
        end

      {error, _} ->
        Mix.shell().error("  Error reading #{filename}: #{error}")
    end
  end

  defp count_rows(path, table) do
    case System.cmd("sqlite3", [path, "SELECT COUNT(*) FROM #{table}"], stderr_to_stdout: true) do
      {count, 0} ->
        Mix.shell().info("  #{table}: #{String.trim(count)} rows")

      _ ->
        :ok
    end
  end

  defp check_dividends(path) do
    case System.cmd("sqlite3", [path, "SELECT MIN(ex_date), MAX(ex_date) FROM dividends"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        Mix.shell().info("  Dividend range: #{String.trim(output)}")

        # Compare with PostgreSQL
        pg_count =
          Dividendsomatic.Repo.aggregate(Dividendsomatic.Portfolio.DividendPayment, :count)

        Mix.shell().info("  PostgreSQL dividend_payments: #{pg_count}")

      _ ->
        :ok
    end
  end

  defp export_findings do
    dir = "data_revisited"
    File.mkdir_p!(dir)

    # Export SQLite dividends as JSON
    db_path = "db/dividendsomatic_dev.db"

    if File.exists?(db_path) do
      case System.cmd(
             "sqlite3",
             [db_path, "-json", "SELECT * FROM dividends"],
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          path = Path.join(dir, "sqlite_unique.json")
          File.write!(path, output)
          Mix.shell().info("Exported SQLite data to #{path}")

        _ ->
          Mix.shell().info("No data to export from SQLite")
      end
    end
  end
end
