defmodule Dividendsomatic.Gmail do
  @moduledoc """
  Gmail integration for fetching CSV files from Interactive Brokers emails.

  This module provides functions to:
  - Search for Activity Flex emails
  - Download CSV attachments
  - Parse email data

  ## Integration Options

  1. **Gmail MCP** (Preferred when available):
     - Uses Claude's Gmail MCP tools for direct access
     - Requires MCP session with Gmail scope

  2. **Google OAuth** (Production):
     - Full API access with credentials stored in config
     - Requires `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN`

  3. **Manual Import** (Fallback):
     - Use `mix import.csv path/to/file.csv`

  ## Usage

      # Search for recent Activity Flex emails
      {:ok, emails} = Dividendsomatic.Gmail.search_activity_flex_emails()

      # Get CSV data from an email
      {:ok, csv_data} = Dividendsomatic.Gmail.get_csv_from_email(email_id)
  """

  require Logger

  @gmail_api_base "https://gmail.googleapis.com/gmail/v1/users/me"
  @ib_sender "noreply@interactivebrokers.com"

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

    query = build_search_query(days_back)
    Logger.info("Searching Gmail with query: #{query}")

    case get_access_token() do
      {:ok, token} ->
        search_with_oauth(token, query, max_results)

      {:error, :not_configured} ->
        Logger.warning("Gmail OAuth not configured - use manual import")
        {:ok, []}
    end
  end

  @doc """
  Downloads CSV attachment from a specific email.

  Returns the CSV data as a string.
  """
  def get_csv_from_email(email_id) do
    case get_access_token() do
      {:ok, token} ->
        fetch_email_attachment(token, email_id)

      {:error, :not_configured} ->
        Logger.warning("Gmail OAuth not configured - cannot fetch email: #{email_id}")
        {:error, :not_configured}
    end
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
        case Date.new(
               String.to_integer(year),
               String.to_integer(month),
               String.to_integer(day)
             ) do
          {:ok, date} ->
            date

          {:error, _} ->
            Logger.warning("Invalid date in subject: #{subject}, using today's date as fallback")

            Date.utc_today()
        end

      _ ->
        Logger.warning(
          "Could not extract date from subject: #{subject}, using today's date as fallback"
        )

        Date.utc_today()
    end
  end

  @doc """
  Imports all new CSV files from Gmail.

  Searches for recent emails and imports any that haven't been imported yet.
  Returns a summary of the import operation.

  ## Examples

      iex> Dividendsomatic.Gmail.import_all_new()
      {:ok, %{imported: 3, skipped: 2, errors: 0}}
  """
  def import_all_new(opts \\ []) do
    case search_activity_flex_emails(opts) do
      {:ok, emails} when emails != [] ->
        results =
          emails
          |> Enum.map(&import_email/1)
          |> Enum.group_by(&elem(&1, 0))

        summary = %{
          imported: length(Map.get(results, :ok, [])),
          skipped: length(Map.get(results, :skipped, [])),
          errors: length(Map.get(results, :error, []))
        }

        Logger.info("Gmail import complete: #{inspect(summary)}")
        {:ok, summary}

      {:ok, []} ->
        Logger.info("No new emails found")
        {:ok, %{imported: 0, skipped: 0, errors: 0}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp import_email(%{id: email_id, subject: subject}) do
    report_date = extract_date_from_subject(subject)

    if Dividendsomatic.Portfolio.get_snapshot_by_date(report_date) do
      Logger.info("Snapshot already exists for #{report_date}, skipping")
      {:skipped, report_date}
    else
      import_new_snapshot(email_id, report_date)
    end
  end

  defp import_new_snapshot(email_id, report_date) do
    with {:ok, csv_data} <- get_csv_from_email(email_id),
         {:ok, _snapshot} <-
           Dividendsomatic.Portfolio.create_snapshot_from_csv(csv_data, report_date) do
      Logger.info("Successfully imported snapshot for #{report_date}")
      {:ok, report_date}
    else
      {:error, reason} ->
        Logger.error("Failed to import for #{report_date}: #{inspect(reason)}")
        {:error, {report_date, reason}}
    end
  end

  # Private functions

  defp build_search_query(days_back) do
    "from:#{@ib_sender} subject:\"Activity Flex\" has:attachment newer_than:#{days_back}d"
  end

  defp get_access_token do
    client_id = Application.get_env(:dividendsomatic, :google_client_id)
    client_secret = Application.get_env(:dividendsomatic, :google_client_secret)
    refresh_token = Application.get_env(:dividendsomatic, :google_refresh_token)

    if is_nil(client_id) or is_nil(client_secret) or is_nil(refresh_token) do
      {:error, :not_configured}
    else
      refresh_access_token(client_id, client_secret, refresh_token)
    end
  end

  defp refresh_access_token(client_id, client_secret, refresh_token) do
    case Req.post("https://oauth2.googleapis.com/token",
           form: [
             client_id: client_id,
             client_secret: client_secret,
             refresh_token: refresh_token,
             grant_type: "refresh_token"
           ]
         ) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Token refresh failed: #{status} - #{inspect(body)}")
        {:error, :token_refresh_failed}

      {:error, reason} ->
        Logger.error("Token refresh request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp search_with_oauth(token, query, max_results) do
    url = "#{@gmail_api_base}/messages"

    case Req.get(url,
           params: [q: query, maxResults: max_results],
           headers: [{"Authorization", "Bearer #{token}"}]
         ) do
      {:ok, %{status: 200, body: %{"messages" => messages}}} ->
        {:ok, fetch_email_subjects(token, messages)}

      {:ok, %{status: 200, body: _}} ->
        {:ok, []}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Gmail search failed: #{status} - #{inspect(body)}")
        {:error, :search_failed}

      {:error, reason} ->
        Logger.error("Gmail search request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_email_subjects(token, messages) do
    messages
    |> Enum.map(&fetch_single_email_subject(token, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_single_email_subject(token, %{"id" => id}) do
    case fetch_message_headers(token, id) do
      {:ok, subject} -> %{id: id, subject: subject}
      {:error, _} -> nil
    end
  end

  defp fetch_message_headers(token, message_id) do
    url = "#{@gmail_api_base}/messages/#{message_id}"

    case Req.get(url,
           params: [format: "metadata", metadataHeaders: "Subject"],
           headers: [{"Authorization", "Bearer #{token}"}]
         ) do
      {:ok, %{status: 200, body: %{"payload" => %{"headers" => headers}}}} ->
        subject =
          headers
          |> Enum.find(fn %{"name" => name} -> name == "Subject" end)
          |> case do
            %{"value" => value} -> value
            _ -> ""
          end

        {:ok, subject}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to fetch message headers: #{status} - #{inspect(body)}")
        {:error, :fetch_failed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_email_attachment(token, message_id) do
    url = "#{@gmail_api_base}/messages/#{message_id}"

    case Req.get(url,
           params: [format: "full"],
           headers: [{"Authorization", "Bearer #{token}"}]
         ) do
      {:ok, %{status: 200, body: %{"payload" => payload}}} ->
        extract_csv_attachment(token, message_id, payload)

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to fetch message: #{status} - #{inspect(body)}")
        {:error, :fetch_failed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_csv_attachment(token, message_id, payload) do
    parts = get_in(payload, ["parts"]) || []

    csv_part =
      parts
      |> Enum.find(fn part ->
        filename = get_in(part, ["filename"]) || ""
        String.ends_with?(String.downcase(filename), ".csv")
      end)

    case csv_part do
      nil ->
        Logger.warning("No CSV attachment found in message #{message_id}")
        {:error, :no_csv_attachment}

      %{"body" => %{"attachmentId" => attachment_id}} ->
        fetch_attachment_data(token, message_id, attachment_id)

      %{"body" => %{"data" => data}} ->
        decode_base64url(data)
    end
  end

  defp fetch_attachment_data(token, message_id, attachment_id) do
    url = "#{@gmail_api_base}/messages/#{message_id}/attachments/#{attachment_id}"

    case Req.get(url, headers: [{"Authorization", "Bearer #{token}"}]) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        decode_base64url(data)

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to fetch attachment: #{status} - #{inspect(body)}")
        {:error, :attachment_fetch_failed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_base64url(data) do
    data
    |> String.replace("-", "+")
    |> String.replace("_", "/")
    |> Base.decode64(padding: false)
    |> case do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :decode_failed}
    end
  end
end
