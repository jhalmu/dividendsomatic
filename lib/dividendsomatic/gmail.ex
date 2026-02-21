defmodule Dividendsomatic.Gmail do
  @moduledoc """
  Gmail integration for fetching IBKR Flex CSV reports.

  Searches for 4 Flex report types and routes each through the appropriate
  import pipeline:

  - **Activity Flex** (daily) → portfolio snapshots
  - **Dividend Flex** (weekly) → dividend records
  - **Trades Flex** (weekly) → broker transactions
  - **Actions Flex** (monthly) → integrity checks

  Requires `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN`.
  """

  require Logger

  alias Dividendsomatic.DataIngestion.FlexImportOrchestrator
  alias Dividendsomatic.Portfolio.FlexCsvRouter

  @gmail_api_base "https://gmail.googleapis.com/gmail/v1/users/me"
  @ib_sender "donotreply@interactivebrokers.com"

  @flex_subjects [
    "Activity Flex",
    "Dividend Flex",
    "Trades Flex",
    "Actions Flex"
  ]

  # --- Public API ---

  @doc """
  Searches Gmail for all IBKR Flex report emails.

  Returns a flat list of `%{id, subject}` maps across all 4 Flex types.

  ## Options

  - `:max_results` - Max emails per type (default: 10)
  - `:days_back` - How many days back to search (default: 30)
  - `:subjects` - List of subject prefixes to search (default: all 4 types)
  """
  def search_flex_emails(opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 10)
    days_back = Keyword.get(opts, :days_back, 30)
    subjects = Keyword.get(opts, :subjects, @flex_subjects)

    case get_access_token() do
      {:ok, token} ->
        emails =
          Enum.flat_map(subjects, fn subject_prefix ->
            query = build_flex_query(subject_prefix, days_back)
            Logger.info("Gmail: searching #{subject_prefix} (#{days_back}d)")
            search_or_empty(token, query, max_results)
          end)

        {:ok, emails}

      {:error, :not_configured} ->
        Logger.warning("Gmail OAuth not configured - use manual import")
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Imports all new Flex reports from Gmail.

  Searches for all 4 Flex types, downloads CSV attachments, auto-detects type
  via FlexCsvRouter, and routes to the correct import pipeline.

  ## Options

  Same as `search_flex_emails/1`.
  """
  def import_all_new(opts \\ []) do
    case search_flex_emails(opts) do
      {:ok, emails} when emails != [] ->
        results =
          emails
          |> Enum.map(&import_flex_email/1)
          |> Enum.group_by(&elem(&1, 0))

        summary = %{
          imported: length(Map.get(results, :ok, [])),
          skipped: length(Map.get(results, :skipped, [])),
          errors: length(Map.get(results, :error, []))
        }

        Logger.info("Gmail import complete: #{inspect(summary)}")
        {:ok, summary}

      {:ok, []} ->
        Logger.info("No new Flex emails found")
        {:ok, %{imported: 0, skipped: 0, errors: 0}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Searches Gmail for Activity Flex emails only (backward-compatible).
  """
  def search_activity_flex_emails(opts \\ []) do
    search_flex_emails(Keyword.put(opts, :subjects, ["Activity Flex"]))
  end

  @doc """
  Downloads CSV attachment from a specific email.
  """
  def get_csv_from_email(email_id) do
    case get_access_token() do
      {:ok, token} ->
        fetch_email_attachment(token, email_id)

      {:error, :not_configured} ->
        Logger.warning("Gmail OAuth not configured - cannot fetch email: #{email_id}")
        {:error, :not_configured}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Extracts report date from email subject line.

  Subject format: "* Flex for MM/DD/YYYY" (IBKR US date format)

  ## Examples

      iex> Dividendsomatic.Gmail.extract_date_from_subject("Activity Flex for 01/28/2026")
      ~D[2026-01-28]

      iex> Dividendsomatic.Gmail.extract_date_from_subject("Dividend Flex for 02/14/2026")
      ~D[2026-02-14]
  """
  def extract_date_from_subject(subject) do
    case Regex.run(~r/Flex for (\d{2})\/(\d{2})\/(\d{4})/, subject) do
      [_, month, day, year] ->
        case Date.new(
               String.to_integer(year),
               String.to_integer(month),
               String.to_integer(day)
             ) do
          {:ok, date} ->
            date

          {:error, _} ->
            Logger.warning("Invalid date in subject: #{subject}, using today as fallback")
            Date.utc_today()
        end

      _ ->
        Logger.warning("Could not extract date from subject: #{subject}, using today as fallback")
        Date.utc_today()
    end
  end

  # --- Import routing ---

  defp import_flex_email(%{id: email_id, subject: subject}) do
    case get_csv_from_email(email_id) do
      {:ok, csv_data} ->
        csv_type = FlexCsvRouter.detect_csv_type(csv_data)
        Logger.info("Gmail: #{subject} → type=#{csv_type}")
        import_via_orchestrator(csv_data, subject)

      {:error, reason} ->
        Logger.error("Gmail: failed to fetch #{subject}: #{inspect(reason)}")
        {:error, {subject, reason}}
    end
  end

  defp import_via_orchestrator(csv_data, subject) do
    # Write to temp file so FlexImportOrchestrator can handle all types
    # (activity_statement and actions parsers need a file path)
    tmp_path = Path.join(System.tmp_dir!(), "gmail_#{:erlang.unique_integer([:positive])}.csv")

    try do
      File.write!(tmp_path, csv_data)

      case FlexImportOrchestrator.import_file(tmp_path, subject) do
        {:ok, type, details} ->
          Logger.info("Gmail: #{subject} imported as #{type}: #{inspect(details)}")
          {:ok, subject}

        {:skipped, type, reason} ->
          Logger.info("Gmail: #{subject} skipped (#{type}): #{reason}")
          {:skipped, subject}

        {:error, reason} ->
          Logger.error("Gmail: #{subject} import failed: #{inspect(reason)}")
          {:error, {subject, reason}}
      end
    after
      File.rm(tmp_path)
    end
  end

  defp search_or_empty(token, query, max_results) do
    case search_with_oauth(token, query, max_results) do
      {:ok, results} -> results
      {:error, _} -> []
    end
  end

  # --- Gmail API helpers ---

  defp build_flex_query(subject_prefix, days_back) do
    ~s(from:#{@ib_sender} subject:"#{subject_prefix}" has:attachment newer_than:#{days_back}d)
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
