defmodule Dividendsomatic.Portfolio.IbkrCsvParser do
  @moduledoc """
  Parser for IBKR Transaction History CSV exports.

  Handles the section-based CSV format with Statement, Summary, and
  Transaction History sections. All amounts are in EUR (base currency).
  Extracts ISINs from dividend/tax descriptions where available.
  """

  require Logger

  NimbleCSV.define(IbkrCsv, separator: ",", escape: "\"")

  # IBKR transaction type → normalized type
  @type_map %{
    "Buy" => "buy",
    "Sell" => "sell",
    "Dividend" => "dividend",
    "Payment in Lieu" => "dividend",
    "Foreign Tax Withholding" => "foreign_tax",
    "Adjustment" => "corporate_action",
    "Deposit" => "deposit",
    "Withdrawal" => "withdrawal",
    "Debit Interest" => "loan_interest",
    "Other Fee" => "corporate_action",
    "Sales Tax" => "corporate_action",
    "Forex Trade Component" => "fx_buy",
    "Transaction Fee" => "corporate_action"
  }

  # ISIN: 2 uppercase letters + 10 alphanumeric chars
  @isin_regex ~r/\(([A-Z]{2}[A-Z0-9]{10})\)/

  @doc """
  Parses an IBKR Transaction History CSV file from disk.

  Returns `{:ok, [transaction_map]}` or `{:error, reason}`.
  """
  def parse_file(path) do
    case File.read(path) do
      {:ok, binary} -> parse(binary)
      {:error, reason} -> {:error, "Failed to read file: #{reason}"}
    end
  end

  @doc """
  Parses an IBKR Transaction History CSV string.

  Filters for "Transaction History,Data," rows, parses CSV, and maps to
  BrokerTransaction-compatible attribute maps.

  Returns `{:ok, [transaction_map]}` or `{:error, reason}`.
  """
  def parse(csv_string) when is_binary(csv_string) do
    data_lines = extract_data_lines(csv_string)
    parse_data_lines(data_lines)
  rescue
    e -> {:error, "Parse error: #{Exception.message(e)}"}
  end

  @doc """
  Normalizes an IBKR transaction type to an internal type.
  """
  def normalize_type(ibkr_type) do
    case Map.get(@type_map, ibkr_type) do
      nil ->
        Logger.warning("Unknown IBKR transaction type: #{ibkr_type}")
        "corporate_action"

      type ->
        type
    end
  end

  # Extract Transaction History data lines from the section-based CSV
  defp extract_data_lines(csv_string) do
    csv_string
    |> String.split(~r/\r?\n/)
    |> Enum.filter(&String.starts_with?(&1, "Transaction History,Data,"))
  end

  defp parse_data_lines([]), do: {:ok, []}

  defp parse_data_lines(data_lines) do
    csv_body = Enum.join(data_lines, "\n")

    transactions =
      csv_body
      |> IbkrCsv.parse_string(skip_headers: false)
      |> Enum.map(&row_to_transaction/1)
      |> assign_external_ids()

    {:ok, transactions}
  end

  # Map a parsed CSV row to a BrokerTransaction-compatible map.
  #
  # Columns (0-indexed): 0=Section, 1=RowType, 2=Date, 3=Account,
  # 4=Description, 5=TransactionType, 6=Symbol, 7=Quantity, 8=Price,
  # 9=PriceCurrency, 10=GrossAmount, 11=Commission,
  # 12=NetAmount, 13=Multiplier, 14=ExchangeRate
  defp row_to_transaction(row) do
    raw_type = get_col(row, 5, "")
    description = get_col(row, 4)
    quantity = parse_decimal(get_col(row, 7))

    %{
      broker: "ibkr",
      transaction_type: resolve_type(raw_type, quantity),
      raw_type: raw_type,
      trade_date: parse_date(get_col(row, 2)),
      entry_date: parse_date(get_col(row, 2)),
      security_name: extract_security_name(description, raw_type),
      isin: extract_isin(description),
      quantity: quantity,
      price: parse_decimal(get_col(row, 8)),
      currency: get_col(row, 9),
      amount: parse_decimal(get_col(row, 12)),
      commission: parse_decimal(get_col(row, 11)),
      exchange_rate: parse_decimal(get_col(row, 14)),
      description: description,
      raw_data: %{
        "account" => get_col(row, 3),
        "symbol" => get_col(row, 6),
        "gross_amount" => get_col(row, 10),
        "multiplier" => get_col(row, 13)
      }
    }
  end

  # For forex trades, distinguish buy/sell by quantity sign
  defp resolve_type("Forex Trade Component", quantity) when not is_nil(quantity) do
    if Decimal.negative?(quantity), do: "fx_sell", else: "fx_buy"
  end

  defp resolve_type(raw_type, _quantity), do: normalize_type(raw_type)

  # Extract clean security name from description.
  # Buy/Sell: "CORNERSTONE STRATEGIC VALUE" → as-is (company name)
  # Dividend/Tax: "ARCC (US04010L1035) Cash Dividend..." → "ARCC" (ticker)
  defp extract_security_name(nil, _), do: nil
  defp extract_security_name(desc, type) when type in ["Buy", "Sell"], do: desc

  defp extract_security_name(desc, type)
       when type in ["Dividend", "Payment in Lieu", "Foreign Tax Withholding"] do
    case Regex.run(~r/^([A-Z0-9.]+)[\s(]/, desc) do
      [_, name] -> name
      _ -> nil
    end
  end

  defp extract_security_name(_desc, _type), do: nil

  @doc """
  Extracts an ISIN from a description string.

  Matches patterns like "ARCC (US04010L1035)" or "ZIM(IL0065100930)".
  Returns nil if no valid ISIN found.
  """
  def extract_isin(nil), do: nil

  def extract_isin(description) do
    case Regex.run(@isin_regex, description) do
      [_, isin] -> isin
      _ -> nil
    end
  end

  @doc """
  Assigns deterministic external_ids with sequence counters for duplicate rows.

  Rows with identical (date, type, symbol, amount) get incrementing sequences,
  ensuring re-imports produce the same IDs for deduplication.

  Shared by both CSV and PDF parsers.
  """
  def assign_external_ids(transactions) do
    {result, _counts} =
      Enum.reduce(transactions, {[], %{}}, fn txn, {acc, counts} ->
        key = dedup_key(txn)
        seq = Map.get(counts, key, 0)

        hash =
          :crypto.hash(:sha256, "#{key}:#{seq}")
          |> Base.encode16(case: :lower)
          |> String.slice(0, 16)

        new_txn = Map.put(txn, :external_id, "ibkr_#{hash}")
        {[new_txn | acc], Map.put(counts, key, seq + 1)}
      end)

    Enum.reverse(result)
  end

  defp dedup_key(txn) do
    amount_str = if txn.amount, do: Decimal.to_string(txn.amount), else: "nil"
    symbol = get_in(txn, [:raw_data, "symbol"]) || "-"
    "ibkr:#{txn.trade_date}:#{txn.raw_type}:#{symbol}:#{amount_str}"
  end

  defp get_col(row, index, default \\ nil) do
    case Enum.at(row, index) do
      nil -> default
      "-" -> default
      "" -> default
      val -> String.trim(val)
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  @doc """
  Parses a decimal string. Handles scientific notation (e.g., "7.335E-6")
  and strips thousands separators.

  Returns nil for empty/nil values.
  """
  def parse_decimal(nil), do: nil
  def parse_decimal(""), do: nil

  def parse_decimal(str) when is_binary(str) do
    normalized = String.replace(str, ",", "")

    case Decimal.parse(normalized) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end
end
