defmodule Dividendsomatic.Workers.GmailImportWorker do
  @moduledoc """
  Oban worker for automatically importing portfolio CSV files from Gmail.

  This worker:
  1. Searches Gmail for "Activity Flex" emails from Interactive Brokers
  2. Downloads CSV attachments from those emails
  3. Imports them into the database using Portfolio.create_snapshot_from_csv/2

  ## Usage

  Manual trigger:
      %{}
      |> Dividendsomatic.Workers.GmailImportWorker.new()
      |> Oban.insert()

  ## Configuration

  Scheduled to run daily at 8 AM via Oban.Plugins.Cron in config.exs

  ## Gmail MCP Integration

  This worker uses the Gmail MCP to:
  - Search for emails: "from:noreply@interactivebrokers.com subject:Activity Flex"
  - Fetch email attachments (flex*.csv files)
  - Parse and import the CSV data

  ## Error Handling

  - Retries 3 times with exponential backoff
  - Logs all import attempts
  - Skips duplicate snapshots (unique constraint on report_date)
  """

  use Oban.Worker,
    queue: :gmail_import,
    max_attempts: 3

  require Logger

  # alias Dividendsomatic.Portfolio  # TODO: Uncomment when Gmail MCP is implemented

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting Gmail CSV import")

    # TODO: Implement Gmail MCP integration
    # For now, this is a placeholder that shows the intended flow

    {:ok, emails} = search_gmail_for_csv_emails()

    import_results =
      emails
      |> Enum.map(&download_and_import_csv/1)
      |> Enum.filter(fn {status, _} -> status == :ok end)

    Logger.info("Gmail import completed: #{length(import_results)} snapshots imported")
    {:ok, %{imported_count: length(import_results)}}
  end

  # Private functions

  defp search_gmail_for_csv_emails do
    # TODO: Use Gmail MCP to search for emails
    # Query: "from:noreply@interactivebrokers.com subject:Activity Flex has:attachment"

    # Example implementation (when Gmail MCP is available):
    # case GmailMCP.search(
    #   query: "from:noreply@interactivebrokers.com subject:Activity Flex has:attachment",
    #   max_results: 30
    # ) do
    #   {:ok, results} -> {:ok, results}
    #   {:error, reason} -> {:error, reason}
    # end

    # For now, return empty list
    Logger.warning("Gmail MCP not yet implemented - returning empty results")
    {:ok, []}
  end

  defp download_and_import_csv(email) do
    # TODO: Download CSV attachment from email
    # Extract CSV data and report date
    # Import using Portfolio.create_snapshot_from_csv/2

    # Example implementation:
    # with {:ok, attachment} <- fetch_csv_attachment(email),
    #      {:ok, csv_data} <- decode_attachment(attachment),
    #      report_date <- extract_report_date(csv_data),
    #      {:ok, {:ok, _snapshot}} <- Portfolio.create_snapshot_from_csv(csv_data, report_date) do
    #   Logger.info("Successfully imported snapshot for #{report_date}")
    #   {:ok, report_date}
    # else
    #   {:error, %Ecto.Changeset{errors: [report_date: {"has already been taken", _}]}} ->
    #     Logger.info("Snapshot already exists, skipping")
    #     {:skipped, :duplicate}
    #   {:error, reason} ->
    #     Logger.error("Failed to import: #{inspect(reason)}")
    #     {:error, reason}
    # end

    Logger.warning("CSV import not yet implemented for email: #{inspect(email)}")
    {:skipped, :not_implemented}
  end

  # TODO: Use when Gmail MCP is implemented
  defp _extract_report_date(csv_data) do
    # Parse first data row to get ReportDate
    [_header | [first_row | _]] = String.split(csv_data, "\n", trim: true)
    [date_str | _] = String.split(first_row, ",", parts: 2)

    case Date.from_iso8601(String.trim(date_str, "\"")) do
      {:ok, date} -> date
      _ -> Date.utc_today()
    end
  end
end
