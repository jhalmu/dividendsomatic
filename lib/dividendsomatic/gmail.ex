defmodule Dividendsomatic.Gmail do
  @moduledoc """
  Gmail integration for fetching CSV files from Interactive Brokers emails.

  This module provides functions to:
  - Search for Activity Flex emails
  - Download CSV attachments
  - Parse email data

  ## Usage

      # Search for recent Activity Flex emails
      {:ok, emails} = Dividendsomatic.Gmail.search_activity_flex_emails()
      
      # Get CSV data from an email
      {:ok, csv_data} = Dividendsomatic.Gmail.get_csv_from_email(email_id)
  """

  require Logger

  @doc """
  Searches Gmail for Activity Flex emails from Interactive Brokers.

  Returns list of email message IDs that contain CSV attachments.

  ## Options

  - `:max_results` - Maximum number of emails to fetch (default: 30)
  - `:days_back` - How many days back to search (default: 30)

  ## Examples

      iex> Dividendsomatic.Gmail.search_activity_flex_emails()
      {:ok, [%{id: "abc123", subject: "Activity Flex for 01/28/2026"}]}
  """
  def search_activity_flex_emails(opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 30)
    days_back = Keyword.get(opts, :days_back, 30)

    # Build Gmail search query
    # from:noreply@interactivebrokers.com 
    # subject:"Activity Flex"
    # has:attachment
    # newer_than:30d

    query = build_search_query(days_back)

    # TODO: Call Gmail MCP search_gmail_messages tool
    # For now, return placeholder

    Logger.info("Searching Gmail with query: #{query}")
    Logger.warning("Gmail MCP integration not yet connected - this is a placeholder")

    {:ok, []}
  end

  @doc """
  Downloads CSV attachment from a specific email.

  Returns the CSV data as a string.
  """
  def get_csv_from_email(email_id) do
    # TODO: Use read_gmail_thread or read_gmail_message to get email details
    # TODO: Extract CSV attachment
    # TODO: Decode base64 if needed
    # TODO: Return CSV string

    Logger.warning("get_csv_from_email not yet implemented for: #{email_id}")
    {:error, :not_implemented}
  end

  @doc """
  Extracts report date from email subject line.

  Subject format: "Activity Flex for MM/DD/YYYY"

  ## Examples

      iex> Dividendsomatic.Gmail.extract_date_from_subject("Activity Flex for 01/28/2026")
      ~D[2026-01-28]
  """
  def extract_date_from_subject(subject) do
    # Match pattern: "Activity Flex for MM/DD/YYYY"
    case Regex.run(~r/Activity Flex for (\d{2})\/(\d{2})\/(\d{4})/, subject) do
      [_, month, day, year] ->
        {:ok, date} =
          Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day))

        date

      _ ->
        Date.utc_today()
    end
  end

  # Private functions

  defp build_search_query(days_back) do
    """
    from:noreply@interactivebrokers.com \
    subject:"Activity Flex" \
    has:attachment \
    newer_than:#{days_back}d
    """
    |> String.replace("\n", " ")
    |> String.trim()
  end
end
