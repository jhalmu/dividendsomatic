defmodule Dividendsomatic.DataIngestion do
  @moduledoc """
  Generic data ingestion for portfolio data from any source.

  Each source implements the `Source` behaviour, providing a consistent
  interface for listing available data and fetching CSV content.

  ## Sources

  - `Dividendsomatic.DataIngestion.CsvDirectory` - Local CSV files
  - `Dividendsomatic.DataIngestion.GmailAdapter` - Gmail CSV attachments

  ## Usage

      Dividendsomatic.DataIngestion.import_new_from_source(CsvDirectory)
  """

  require Logger

  alias Dividendsomatic.Portfolio

  @doc """
  Behaviour for data ingestion sources.

  Each source must implement:
  - `list_available/1` - List available data entries with dates
  - `fetch_data/1` - Fetch CSV content for a specific entry
  - `source_name/0` - Human-readable source name
  """
  @callback list_available(opts :: keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback fetch_data(source_ref :: term()) :: {:ok, String.t()} | {:error, term()}
  @callback source_name() :: String.t()

  @doc """
  Import all new data from a source, skipping dates that already have snapshots.

  Returns `{:ok, %{imported: n, skipped: n, failed: n}}`.
  """
  def import_new_from_source(adapter, opts \\ []) do
    source = adapter.source_name()
    Logger.info("DataIngestion: starting import from #{source}")

    case adapter.list_available(opts) do
      {:ok, entries} ->
        results =
          Enum.map(entries, fn entry ->
            import_entry(adapter, entry)
          end)

        imported = Enum.count(results, &(&1 == :ok))
        skipped = Enum.count(results, &(&1 == :skipped))
        failed = Enum.count(results, &(&1 == :error))

        Logger.info(
          "DataIngestion: #{source} complete - #{imported} imported, #{skipped} skipped, #{failed} failed"
        )

        {:ok, %{imported: imported, skipped: skipped, failed: failed}}

      {:error, reason} ->
        Logger.warning("DataIngestion: #{source} failed to list: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp import_entry(adapter, %{date: date, ref: ref}) do
    if Portfolio.get_snapshot_by_date(date) do
      :skipped
    else
      do_import(adapter, ref, date)
    end
  end

  defp do_import(adapter, ref, date) do
    with {:ok, csv_data} <- adapter.fetch_data(ref),
         {:ok, _snapshot} <- Portfolio.create_snapshot_from_csv(csv_data, date) do
      :ok
    else
      {:error, _} -> :error
    end
  end
end
