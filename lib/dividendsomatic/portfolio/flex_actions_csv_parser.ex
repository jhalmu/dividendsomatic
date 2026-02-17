defmodule Dividendsomatic.Portfolio.FlexActionsCsvParser do
  @moduledoc """
  Parses IBKR Flex Actions CSV reports for integrity checking.

  Actions.csv has multiple sections with different header rows:
  1. Account summary (BASE_SUMMARY + per-currency rows) — wide format, 150+ cols
  2. Transaction detail (ActivityCode-based) — 44 columns
  3. Open/closed lot sections — ignored

  Only section 2 (transaction details) is parsed. In-memory only, no table needed.
  """

  @doc """
  Parses an Actions CSV string, extracting transaction details.

  Returns `{:ok, %{transactions: [...], summary: %{...}}}` or `{:error, reason}`.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(csv_string) when is_binary(csv_string) do
    lines =
      csv_string
      |> String.split(~r/\r?\n/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case lines do
      [] ->
        {:error, :empty_csv}

      _ ->
        {summary, transactions} = extract_sections(lines)
        {:ok, %{transactions: transactions, summary: summary}}
    end
  end

  @doc """
  Parses an Actions CSV file from disk.
  """
  @spec parse_file(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, reason} -> {:error, reason}
    end
  end

  # Extract summary section and transaction detail section
  defp extract_sections(lines) do
    # Find the transaction detail header (contains ActivityCode and TransactionID)
    {summary_lines, txn_lines} = split_at_transaction_header(lines)

    summary = parse_summary(summary_lines)
    transactions = parse_transactions(txn_lines)

    {summary, transactions}
  end

  defp split_at_transaction_header(lines) do
    idx =
      Enum.find_index(lines, fn line ->
        String.contains?(line, "ActivityCode") and String.contains?(line, "TransactionID")
      end)

    case idx do
      nil -> {lines, []}
      i -> Enum.split(lines, i)
    end
  end

  # Parse the BASE_SUMMARY section for key totals
  defp parse_summary(lines) do
    # Find the base summary line (contains "BASE_SUMMARY")
    base_line = Enum.find(lines, &String.contains?(&1, "BASE_SUMMARY"))

    case base_line do
      nil ->
        %{}

      line ->
        fields = parse_csv_fields(line)
        extract_summary_fields(fields)
    end
  end

  # Extract key summary values from the BASE_SUMMARY row
  # The summary has 150+ columns. We extract the ones we need by position.
  defp extract_summary_fields(fields) when length(fields) < 10, do: %{}

  defp extract_summary_fields(fields) do
    %{
      from_date: parse_date(Enum.at(fields, 5)),
      to_date: parse_date(Enum.at(fields, 6)),
      starting_cash: parse_decimal(Enum.at(fields, 7)),
      dividends: parse_decimal(Enum.at(fields, 61)),
      payment_in_lieu: parse_decimal(Enum.at(fields, 100)),
      commissions: parse_decimal(Enum.at(fields, 14)),
      net_trades_purchases: parse_decimal(Enum.at(fields, 91)),
      net_trades_sales: parse_decimal(Enum.at(fields, 88)),
      withholding_tax: parse_decimal(Enum.at(fields, 109)),
      ending_cash: parse_decimal(Enum.at(fields, 139))
    }
  end

  # Parse the transaction detail section
  # Stops at section boundaries (new header rows from open/closed lot sections)
  defp parse_transactions([]), do: []

  defp parse_transactions([header | data_lines]) do
    # Build header index map
    headers =
      header
      |> parse_csv_fields()
      |> Enum.with_index()
      |> Map.new()

    data_lines
    |> Enum.take_while(&(not section_header?(&1)))
    |> Enum.reject(&header_row?(&1, header))
    |> Enum.map(&parse_transaction_row(&1, headers))
    |> Enum.reject(&is_nil/1)
  end

  defp header_row?(line, header) do
    String.trim(line) == String.trim(header)
  end

  # Detect new section headers (open/closed lots, trade confirmations, etc.)
  defp section_header?(line) do
    stripped = String.trim_leading(line, "\"")
    String.starts_with?(stripped, "ClientAccountID")
  end

  defp parse_transaction_row(line, headers) do
    fields = parse_csv_fields(line)

    activity_code = get_field(fields, headers, "ActivityCode")
    # Skip non-transaction rows (balance adjustments, empty codes)
    if activity_code && activity_code != "" && activity_code != "ADJ" do
      %{
        activity_code: activity_code,
        activity_description: get_field(fields, headers, "ActivityDescription"),
        symbol: get_field(fields, headers, "Symbol"),
        isin: get_field(fields, headers, "ISIN"),
        currency: get_field(fields, headers, "CurrencyPrimary"),
        date: parse_date(get_field(fields, headers, "Date")),
        settle_date: parse_date(get_field(fields, headers, "SettleDate")),
        amount: parse_decimal(get_field(fields, headers, "Amount")),
        debit: parse_decimal(get_field(fields, headers, "Debit")),
        credit: parse_decimal(get_field(fields, headers, "Credit")),
        trade_quantity: parse_decimal(get_field(fields, headers, "TradeQuantity")),
        trade_price: parse_decimal(get_field(fields, headers, "TradePrice")),
        trade_id: get_field(fields, headers, "TradeID"),
        transaction_id: get_field(fields, headers, "TransactionID"),
        buy_sell: get_field(fields, headers, "Buy/Sell"),
        fx_rate: parse_decimal(get_field(fields, headers, "FXRateToBase"))
      }
    else
      nil
    end
  end

  defp get_field(fields, headers, name) do
    case Map.get(headers, name) do
      nil -> nil
      idx -> Enum.at(fields, idx)
    end
  end

  # Parse CSV fields respecting quoted commas
  defp parse_csv_fields(line) do
    line
    |> String.split(",")
    |> Enum.map(&String.trim(&1, "\""))
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(str) do
    normalized = String.replace(str, ",", "")

    case Decimal.parse(normalized) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end
end
