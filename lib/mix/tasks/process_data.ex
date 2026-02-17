defmodule Mix.Tasks.Process.Data do
  @moduledoc """
  Orchestrator task for the full data processing pipeline.

  ## Usage

      mix process.data --scan       # Report what would be processed
      mix process.data --all        # Run full pipeline
      mix process.data --archive    # Move processed files to data_archive/

  ## Pipeline order (--all)

  1. Import Yahoo dividends (per-share reference data)
  2. Re-run DividendProcessor (now with total_net fallback)
  3. Import Flex dividend reports
  4. Import archive flex snapshots
  """
  use Mix.Task

  require Logger

  alias Dividendsomatic.Portfolio.BrokerTransaction
  alias Dividendsomatic.Portfolio.Dividend
  alias Dividendsomatic.Portfolio.PortfolioSnapshot
  alias Dividendsomatic.Portfolio.Processors.DividendProcessor
  alias Dividendsomatic.Repo

  @shortdoc "Run full data processing pipeline"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    cond do
      "--scan" in args -> scan()
      "--all" in args -> run_all()
      "--archive" in args -> archive()
      true -> Mix.shell().info("Usage: mix process.data [--scan | --all | --archive]")
    end
  end

  defp scan do
    Mix.shell().info("=== Data Processing Scan ===\n")

    yahoo_dir = "csv_data/archive/dividends"
    flex_div_dir = "csv_data/Dividends-2019-2024"
    flex_snap_dir = "csv_data/archive/flex"

    scan_dir(yahoo_dir, "Yahoo dividend JSONs", ".json")
    scan_dir(flex_div_dir, "IBKR Flex dividend CSVs", ".csv")
    scan_dir(flex_snap_dir, "Archive flex snapshot CSVs", ".csv")

    # Count existing data
    dividend_count = Repo.aggregate(Dividend, :count)
    snapshot_count = Repo.aggregate(PortfolioSnapshot, :count)
    txn_count = Repo.aggregate(BrokerTransaction, :count)

    Mix.shell().info("\n=== Current Database ===")
    Mix.shell().info("  Dividends:     #{dividend_count}")
    Mix.shell().info("  Snapshots:     #{snapshot_count}")
    Mix.shell().info("  Transactions:  #{txn_count}")
  end

  defp scan_dir(dir, label, ext) do
    case File.ls(dir) do
      {:ok, files} ->
        count = files |> Enum.filter(&String.ends_with?(&1, ext)) |> length()
        Mix.shell().info("  #{label}: #{count} files in #{dir}/")

      {:error, _} ->
        Mix.shell().info("  #{label}: directory not found (#{dir}/)")
    end
  end

  defp run_all do
    Mix.shell().info("=== Running Full Data Pipeline ===\n")

    Mix.shell().info("--- Step 1: Import Yahoo dividends ---")
    Mix.Task.run("import.yahoo_dividends")

    Mix.shell().info("\n--- Step 2: Re-run DividendProcessor ---")
    {:ok, count} = DividendProcessor.process()
    Mix.shell().info("DividendProcessor created #{count} new dividends")

    Mix.shell().info("\n--- Step 3: Import Flex dividend reports ---")
    Mix.Task.rerun("import.flex_dividends")

    Mix.shell().info("\n--- Step 4: Import archive flex snapshots ---")
    Mix.Task.rerun("import.batch", ["csv_data/archive/flex"])

    Mix.shell().info("\n=== Pipeline Complete ===")
    dividend_count = Repo.aggregate(Dividend, :count)
    Mix.shell().info("Total dividends in database: #{dividend_count}")
  end

  defp archive do
    archive_dir = "data_archive"
    File.mkdir_p!(archive_dir)

    moves = [
      {"csv_data/Dividends-2019-2024", "data_archive/Dividends-2019-2024"}
    ]

    Enum.each(moves, fn {src, dst} -> archive_directory(src, dst) end)
  end

  defp archive_directory(src, dst) do
    if File.dir?(src) do
      File.mkdir_p!(dst)
      copy_directory_files(src, dst)
    else
      Mix.shell().info("Skipping #{src} (not found)")
    end
  end

  defp copy_directory_files(src, dst) do
    case File.ls(src) do
      {:ok, files} ->
        Enum.each(files, fn file ->
          File.cp!(Path.join(src, file), Path.join(dst, file))
        end)

        Mix.shell().info("Archived #{src} → #{dst}")

      {:error, reason} ->
        Mix.shell().error("Failed to read #{src}: #{reason}")
    end
  end
end
