defmodule Dividendsomatic.DataIngestion.FlexImportOrchestrator do
  @moduledoc """
  Orchestrates import of all IBKR Flex CSV types from a directory.

  Scans a directory, classifies each CSV by type using `FlexCsvRouter`,
  and routes to the appropriate import pipeline:

  - `:portfolio` → existing `DataIngestion.import_new_from_source(CsvDirectory)`
  - `:dividends` → skipped (legacy, use `mix import.activity`)
  - `:trades`    → skipped (legacy, use `mix import.activity`)
  - `:actions`   → `IntegrityChecker.run_all/1` (print report, no insert)

  Replaces `CsvDirectory` as the main import entry point for the worker.
  """

  require Logger

  alias Dividendsomatic.Portfolio
  alias Dividendsomatic.Portfolio.{FlexCsvRouter, IntegrityChecker}

  @default_dir "csv_data"

  @doc """
  Imports all CSV files from a directory, routing by type.

  Returns `{:ok, summary}` with per-type results.
  """
  @spec import_all(keyword()) :: {:ok, map()} | {:error, term()}
  def import_all(opts \\ []) do
    dir = Keyword.get(opts, :dir, @default_dir)
    archive? = Keyword.get(opts, :archive, false)

    case File.ls(dir) do
      {:ok, files} ->
        csv_files =
          files
          |> Enum.filter(&String.ends_with?(&1, ".csv"))
          |> Enum.sort()

        Logger.info("FlexImportOrchestrator: found #{length(csv_files)} CSV files in #{dir}/")

        results =
          Enum.map(csv_files, fn file ->
            path = Path.join(dir, file)
            result = import_file(path, file)
            maybe_archive(archive?, result, path, dir)
            result
          end)

        summary = build_summary(results)
        Logger.info("FlexImportOrchestrator: #{inspect(summary)}")
        {:ok, summary}

      {:error, reason} ->
        Logger.warning("FlexImportOrchestrator: cannot read #{dir}: #{inspect(reason)}")
        {:error, {:directory_not_found, dir, reason}}
    end
  end

  @doc """
  Imports a single CSV file, auto-detecting its type.
  """
  @spec import_file(String.t(), String.t()) ::
          {:ok, atom(), map()} | {:skipped, atom(), String.t()} | {:error, String.t()}
  def import_file(path, filename \\ nil) do
    filename = filename || Path.basename(path)

    case File.read(path) do
      {:ok, content} ->
        type = FlexCsvRouter.detect_csv_type(content)
        Logger.info("FlexImportOrchestrator: #{filename} → #{type}")
        route_import(type, content, path, filename)

      {:error, reason} ->
        Logger.warning("FlexImportOrchestrator: cannot read #{filename}: #{inspect(reason)}")
        {:error, "cannot read #{filename}"}
    end
  end

  defp route_import(:portfolio, content, _path, filename) do
    with {:ok, date} <- Portfolio.CsvParser.extract_report_date(content),
         nil <- Portfolio.get_snapshot_by_date(date),
         {:ok, snapshot} <- Portfolio.create_snapshot_from_csv(content, date) do
      Logger.info(
        "FlexImportOrchestrator: imported portfolio snapshot #{date} " <>
          "(#{snapshot.positions_count} positions)"
      )

      {:ok, :portfolio, %{date: date, positions: snapshot.positions_count}}
    else
      %Dividendsomatic.Portfolio.PortfolioSnapshot{date: date} ->
        Logger.info("FlexImportOrchestrator: portfolio #{date} already exists, skipping")
        {:skipped, :portfolio, "#{filename}: date #{date} exists"}

      {:error, reason} ->
        {:error, "portfolio import failed for #{filename}: #{inspect(reason)}"}
    end
  end

  defp route_import(:dividends, _content, _path, filename) do
    Logger.info(
      "FlexImportOrchestrator: #{filename} — legacy dividend import disabled, use mix import.activity"
    )

    {:skipped, :dividends, "#{filename}: legacy import disabled"}
  end

  defp route_import(:trades, _content, _path, filename) do
    Logger.info(
      "FlexImportOrchestrator: #{filename} — legacy trade import disabled, use mix import.activity"
    )

    {:skipped, :trades, "#{filename}: legacy import disabled"}
  end

  defp route_import(:actions, _content, path, filename) do
    case IntegrityChecker.run_all(path) do
      {:ok, checks} ->
        pass = Enum.count(checks, &(&1.status == :pass))
        fail = Enum.count(checks, &(&1.status == :fail))
        warn = Enum.count(checks, &(&1.status == :warn))

        Logger.info(
          "FlexImportOrchestrator: #{filename} integrity → #{pass} PASS, #{warn} WARN, #{fail} FAIL"
        )

        {:ok, :actions, %{pass: pass, warn: warn, fail: fail, checks: checks}}

      {:error, reason} ->
        {:error, "integrity check failed for #{filename}: #{inspect(reason)}"}
    end
  end

  defp route_import(:unknown, _content, _path, filename) do
    Logger.warning("FlexImportOrchestrator: #{filename} has unknown CSV type, skipping")
    {:skipped, :unknown, "#{filename}: unknown type"}
  end

  defp maybe_archive(true, result, path, dir) when elem(result, 0) != :error do
    archive_file(path, dir)
  end

  defp maybe_archive(_archive?, _result, _path, _dir), do: :noop

  defp archive_file(path, dir) do
    archive_dir = Path.join([dir, "archive", "flex"])

    with :ok <- File.mkdir_p(archive_dir) do
      dest = Path.join(archive_dir, Path.basename(path))
      File.rename(path, dest)
    end
  end

  defp build_summary(results) do
    %{
      portfolio:
        results
        |> Enum.filter(&match?({:ok, :portfolio, _}, &1))
        |> length(),
      dividends:
        results
        |> Enum.filter(&match?({:ok, :dividends, _}, &1))
        |> length(),
      trades:
        results
        |> Enum.filter(&match?({:ok, :trades, _}, &1))
        |> length(),
      actions:
        results
        |> Enum.filter(&match?({:ok, :actions, _}, &1))
        |> length(),
      skipped:
        results
        |> Enum.filter(&match?({:skipped, _, _}, &1))
        |> length(),
      errors:
        results
        |> Enum.filter(&match?({:error, _}, &1))
        |> length()
    }
  end
end
