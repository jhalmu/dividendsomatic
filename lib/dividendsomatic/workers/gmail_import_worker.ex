defmodule Dividendsomatic.Workers.GmailImportWorker do
  @moduledoc """
  Oban worker for importing portfolio CSV files from Gmail.

  Cron-scheduled Mon-Sat at 12:00 UTC (before DataImportWorker at 13:00).

  This worker:
  1. Searches Gmail for "Activity Flex" emails from Interactive Brokers
  2. Downloads CSV attachments from those emails
  3. Imports them into the database via `Gmail.import_all_new/1`

  ## Usage

  Manual trigger:
      %{}
      |> Dividendsomatic.Workers.GmailImportWorker.new()
      |> Oban.insert()

  ## Configuration

  Required environment variables:
  - `GOOGLE_CLIENT_ID` - Google OAuth client ID
  - `GOOGLE_CLIENT_SECRET` - Google OAuth client secret
  - `GOOGLE_REFRESH_TOKEN` - Long-lived refresh token

  ## Error Handling

  - Retries 3 times with exponential backoff
  - Gracefully skips if OAuth not configured
  """

  use Oban.Worker,
    queue: :gmail_import,
    max_attempts: 3

  require Logger

  alias Dividendsomatic.Gmail

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("Starting Gmail CSV import")

    days_back = Map.get(args, "days_back", 30)
    max_results = Map.get(args, "max_results", 30)

    case Gmail.import_all_new(days_back: days_back, max_results: max_results) do
      {:ok, summary} ->
        Logger.info("Gmail import completed: #{inspect(summary)}")
        {:ok, summary}

      {:error, :not_configured} ->
        Logger.warning("Gmail OAuth not configured - skipping import")
        {:ok, %{skipped: true, reason: :not_configured}}

      {:error, reason} ->
        Logger.error("Gmail import failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
