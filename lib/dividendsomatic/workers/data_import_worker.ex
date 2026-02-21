defmodule Dividendsomatic.Workers.DataImportWorker do
  @moduledoc """
  Oban worker for automated data import from configured sources.

  Scheduled via cron: weekdays at 12:00 for CSV directory import.
  Uses `FlexImportOrchestrator` for multi-CSV type support.
  """
  use Oban.Worker, queue: :data_import, max_attempts: 3

  require Logger

  alias Dividendsomatic.DataIngestion.FlexImportOrchestrator
  alias Dividendsomatic.Portfolio.DividendValidator

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source" => "csv_directory"}}) do
    Logger.info("DataImportWorker: starting multi-CSV import")

    dir = Application.get_env(:dividendsomatic, :csv_import_dir, "csv_data")

    case FlexImportOrchestrator.import_all(dir: dir, archive: true) do
      {:ok, summary} ->
        Logger.info("DataImportWorker: #{inspect(summary)}")
        run_post_import_validation()
        :ok

      {:error, reason} ->
        Logger.warning("DataImportWorker: failed - #{inspect(reason)}")
        :ok
    end
  end

  def perform(%Oban.Job{args: args}) do
    Logger.warning("DataImportWorker: unknown source #{inspect(args)}")
    :ok
  end

  defp run_post_import_validation do
    report = DividendValidator.validate()

    if report.issue_count > 0 do
      Logger.warning(
        "Post-import validation: #{report.issue_count} issues #{inspect(report.by_severity)}"
      )
    end
  end
end
