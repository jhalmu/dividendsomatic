defmodule Dividendsomatic.Workers.DataImportWorker do
  @moduledoc """
  Oban worker for automated data import from configured sources.

  Scheduled via cron: weekdays at 12:00 for CSV directory import.
  Uses the generic DataIngestion context for source-agnostic imports.
  """
  use Oban.Worker, queue: :data_import, max_attempts: 3

  require Logger

  alias Dividendsomatic.DataIngestion
  alias Dividendsomatic.DataIngestion.CsvDirectory

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source" => "csv_directory"}}) do
    Logger.info("DataImportWorker: starting CSV directory import")

    dir = Application.get_env(:dividendsomatic, :csv_import_dir, "csv_data")

    case DataIngestion.import_new_from_source(CsvDirectory, dir: dir) do
      {:ok, summary} ->
        Logger.info("DataImportWorker: #{inspect(summary)}")
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
end
