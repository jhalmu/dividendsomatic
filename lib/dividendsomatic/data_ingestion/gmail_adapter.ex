defmodule Dividendsomatic.DataIngestion.GmailAdapter do
  @moduledoc """
  Data ingestion source wrapping the existing Gmail integration.

  Searches Gmail for Activity Flex emails from Interactive Brokers
  and provides CSV attachments for import.
  """

  @behaviour Dividendsomatic.DataIngestion

  alias Dividendsomatic.Gmail

  @impl true
  def source_name, do: "Gmail"

  @impl true
  def list_available(opts \\ []) do
    case Gmail.search_activity_flex_emails(opts) do
      {:ok, emails} -> {:ok, Enum.flat_map(emails, &entry_from_email/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp entry_from_email(email) do
    case extract_date_from_subject(email[:subject] || "") do
      {:ok, date} -> [%{date: date, ref: email[:id], subject: email[:subject]}]
      {:error, _} -> []
    end
  end

  @impl true
  def fetch_data(email_id) do
    Gmail.get_csv_from_email(email_id)
  end

  defp extract_date_from_subject(subject) do
    # Pattern: "Activity Flex for MM/DD/YYYY" (IBKR US date format)
    case Regex.run(~r/(\d{2})\/(\d{2})\/(\d{4})/, subject) do
      [_, month, day, year] ->
        Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day))

      nil ->
        {:error, "no date in subject"}
    end
  end
end
