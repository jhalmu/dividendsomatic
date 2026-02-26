defmodule Dividendsomatic.Portfolio.FlexCsvRouter do
  @moduledoc """
  Detects IBKR Flex CSV type from headers and filters duplicate header rows.

  IBKR Flex reports include duplicate header rows mid-file. This module
  classifies the CSV type and provides cleaned content for downstream parsers.

  ## Supported types

  - `:portfolio` — Portfolio positions (has MarkPrice + PositionValue)
  - `:dividends` — Dividend records (has GrossRate + NetAmount)
  - `:trades` — Trade executions (has TradeID + Buy/Sell)
  - `:actions` — Account activity (has ActivityCode + TransactionID)
  - `:portfolio_with_accruals` — Portfolio + Dividend Accruals (has MarkPrice section + GrossRate section)
  - `:activity_statement` — IBKR Activity Statement (multi-section, starts with "Statement,")
  - `:cash_report` — Cash Report summary (has ClientAccountID + StartingCash + EndingCash)
  """

  @type csv_type ::
          :portfolio
          | :portfolio_with_accruals
          | :dividends
          | :trades
          | :actions
          | :activity_statement
          | :cash_report
          | :unknown

  @doc """
  Detects the CSV type from the first header row.

  Returns the CSV type atom or `:unknown`.
  """
  @spec detect_csv_type(String.t()) :: csv_type()
  def detect_csv_type(csv_string) when is_binary(csv_string) do
    type =
      csv_string
      |> first_header_line()
      |> classify_headers()

    # A portfolio CSV that also contains a second header with GrossRate
    # is a combined portfolio+accruals file
    if type == :portfolio and has_accruals_section?(csv_string) do
      :portfolio_with_accruals
    else
      type
    end
  end

  @doc """
  Detects CSV type from a file path.
  """
  @spec detect_csv_type_from_file(String.t()) :: {:ok, csv_type()} | {:error, term()}
  def detect_csv_type_from_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, detect_csv_type(content)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes duplicate header rows that IBKR inserts mid-file.

  Returns cleaned CSV string with only the first header row retained.
  """
  @spec strip_duplicate_headers(String.t()) :: String.t()
  def strip_duplicate_headers(csv_string) when is_binary(csv_string) do
    lines = String.split(csv_string, ~r/\r?\n/)

    case lines do
      [] ->
        csv_string

      [header | rest] ->
        trimmed_header = String.trim(header)

        filtered =
          Enum.reject(rest, fn line ->
            String.trim(line) == trimmed_header
          end)

        Enum.join([header | filtered], "\n")
    end
  end

  @doc """
  Detects type and returns cleaned CSV content.

  Returns `{type, cleaned_csv}` or `{:unknown, original_csv}`.
  """
  @spec classify_and_clean(String.t()) :: {csv_type(), String.t()}
  def classify_and_clean(csv_string) do
    type = detect_csv_type(csv_string)
    cleaned = strip_duplicate_headers(csv_string)
    {type, cleaned}
  end

  # Extract the first non-empty line, stripping BOM if present
  defp first_header_line(csv_string) do
    csv_string
    |> String.replace_prefix("\uFEFF", "")
    |> String.split(~r/\r?\n/, parts: 2)
    |> List.first("")
    |> String.trim()
  end

  # Classify based on distinctive header columns
  defp classify_headers(""), do: :unknown

  defp classify_headers(header_line) do
    # Order matters: activity statement must be checked first (multi-section format),
    # then actions before trades (actions header also contains "Buy/Sell")
    cond do
      String.starts_with?(header_line, "Statement,") -> :activity_statement
      has_headers?(header_line, ["MarkPrice", "PositionValue"]) -> :portfolio
      has_headers?(header_line, ["GrossRate", "NetAmount"]) -> :dividends
      has_headers?(header_line, ["ClientAccountID", "StartingCash", "EndingCash"]) -> :cash_report
      has_headers?(header_line, ["ActivityCode", "TransactionID"]) -> :actions
      has_headers?(header_line, ["TradeID", "Buy/Sell"]) -> :trades
      true -> :unknown
    end
  end

  defp has_headers?(header_line, required) do
    Enum.all?(required, &String.contains?(header_line, &1))
  end

  # Checks if a portfolio CSV also contains a second header row with accruals columns
  defp has_accruals_section?(csv_string) do
    csv_string
    |> String.split(~r/\r?\n/)
    |> Enum.drop(1)
    |> Enum.any?(fn line ->
      trimmed = String.trim(line)
      has_headers?(trimmed, ["GrossRate", "ExDate"])
    end)
  end
end
