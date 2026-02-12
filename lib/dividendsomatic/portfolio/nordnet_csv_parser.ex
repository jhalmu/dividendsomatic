defmodule Dividendsomatic.Portfolio.NordnetCsvParser do
  @moduledoc """
  Parser for Nordnet transaction CSV exports.

  Handles UTF-16LE encoded, tab-delimited CSV files with Finnish column headers.
  Uses positional parsing because Nordnet has 5 columns named "Valuutta".
  """

  require Logger

  NimbleCSV.define(NordnetTsv, separator: "\t", escape: "\"")

  # Finnish transaction type → normalized type
  @type_map %{
    "OSTO" => "buy",
    "MYYNTI" => "sell",
    "OSINKO" => "dividend",
    "ENNAKKOPIDÄTYS" => "withholding_tax",
    "ULKOM. KUPONKIVERO" => "foreign_tax",
    "TALLETUS" => "deposit",
    "NOSTO" => "withdrawal",
    "VALUUTAN OSTO" => "fx_buy",
    "VALUUTAN MYYNTI" => "fx_sell",
    "LAINAKORKO" => "loan_interest",
    "PÄÄOMIT YLIT.KORKO" => "capital_interest",
    "DEBET KORON KORJ." => "interest_correction"
  }

  # Corporate action types (many variants)
  @corporate_action_types ~w(
    VAIHTO\ AP-JÄTTÖ VAIHTO\ AP-OTTO
    YHTIÖIT.\ IRR\ JÄTTÖ POISTO\ AP\ OTTO
    MERKINTÄ\ AP\ JÄTTÖ MERKINNÄN\ MAKSU
    JÄTTÖ\ SIIRTO MO\ OTTO\ EMISSION\ YHT
    AP\ OTTO
  )

  @doc """
  Parses a Nordnet CSV file from disk.

  Detects UTF-16LE encoding and converts to UTF-8 before parsing.
  Returns `{:ok, [transaction_map]}` or `{:error, reason}`.
  """
  def parse_file(path) do
    case File.read(path) do
      {:ok, binary} ->
        utf8 = decode_to_utf8(binary)
        parse(utf8)

      {:error, reason} ->
        {:error, "Failed to read file: #{reason}"}
    end
  end

  @doc """
  Parses a UTF-8 Nordnet CSV string into a list of transaction maps.

  Returns `{:ok, [transaction_map]}` or `{:error, reason}`.
  """
  def parse(utf8_string) when is_binary(utf8_string) do
    # Strip UTF-8 BOM if present
    cleaned = String.replace_prefix(utf8_string, "\uFEFF", "")

    case NordnetTsv.parse_string(cleaned, skip_headers: true) do
      [] ->
        {:ok, []}

      rows ->
        transactions =
          rows
          |> Enum.reject(&empty_row?/1)
          |> Enum.map(&row_to_transaction/1)

        {:ok, transactions}
    end
  rescue
    e ->
      {:error, "Parse error: #{Exception.message(e)}"}
  end

  @doc """
  Detects UTF-16LE BOM and converts to UTF-8. Passes through UTF-8 unchanged.
  """
  def decode_to_utf8(<<0xFF, 0xFE, rest::binary>>) do
    case :unicode.characters_to_binary(rest, {:utf16, :little}) do
      utf8 when is_binary(utf8) -> utf8
      _ -> rest
    end
  end

  def decode_to_utf8(binary), do: binary

  @doc """
  Normalizes a Finnish transaction type to an English type.
  """
  def normalize_type(finnish_type) do
    case Map.get(@type_map, finnish_type) do
      nil ->
        if finnish_type in @corporate_action_types do
          "corporate_action"
        else
          Logger.warning("Unknown Nordnet transaction type: #{finnish_type}")
          "corporate_action"
        end

      type ->
        type
    end
  end

  # Column positions (0-indexed) matching Nordnet CSV layout
  defp row_to_transaction(row) do
    raw_type = get_col(row, 5, "")

    %{
      external_id: get_col(row, 0),
      broker: "nordnet",
      transaction_type: normalize_type(raw_type),
      raw_type: raw_type,
      entry_date: parse_date(get_col(row, 1)),
      trade_date: parse_date(get_col(row, 2)),
      settlement_date: parse_date(get_col(row, 3)),
      portfolio_id: get_col(row, 4),
      security_name: get_col(row, 6),
      isin: get_col(row, 7),
      quantity: parse_decimal(get_col(row, 8)),
      price: parse_decimal(get_col(row, 9)),
      interest: parse_decimal(get_col(row, 10)),
      total_costs: parse_decimal(get_col(row, 11)),
      currency: get_col(row, 12) || get_col(row, 14),
      amount: parse_decimal(get_col(row, 13)),
      acquisition_value: parse_decimal(get_col(row, 15)),
      result: parse_decimal(get_col(row, 17)),
      total_quantity: parse_decimal(get_col(row, 19)),
      balance: parse_decimal(get_col(row, 20)),
      exchange_rate: parse_decimal(get_col(row, 21)),
      description: get_col(row, 22),
      confirmation_number: get_col(row, 25),
      commission: parse_decimal(get_col(row, 26)),
      reference_fx_rate: parse_decimal(get_col(row, 28))
    }
  end

  defp get_col(row, index, default \\ nil) do
    case Enum.at(row, index) do
      nil -> default
      "" -> default
      val -> String.trim(val)
    end
  end

  defp empty_row?(row) do
    Enum.all?(row, fn col -> col == nil || String.trim(col) == "" end)
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
  Parses a decimal string with comma as decimal separator.
  Returns nil for empty/nil values (not zero — semantic difference).
  """
  def parse_decimal(nil), do: nil
  def parse_decimal(""), do: nil

  def parse_decimal(str) when is_binary(str) do
    normalized = String.replace(str, ",", ".")

    case Decimal.parse(normalized) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end
end
