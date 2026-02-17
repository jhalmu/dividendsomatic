defmodule Dividendsomatic.Portfolio.FlexTradesCsvParser do
  @moduledoc """
  Parses IBKR Flex Trades CSV reports (14-column format).

  Format: ISIN, FIGI, CUSIP, Conid, Symbol, CurrencyPrimary, FXRateToBase,
          TradeID, TradeDate, Quantity, TradePrice, Taxes, Buy/Sell, ListingExchange

  TradeDate is in YYYYMMDD format (not ISO8601).
  FX trades have empty ISIN and Symbol contains "." (e.g., "EUR.SEK").
  """

  alias Dividendsomatic.Portfolio.FlexCsvRouter

  @doc """
  Parses a Flex trades CSV string into a list of broker transaction maps.

  Returns `{:ok, transactions}` or `{:error, reason}`.
  """
  @spec parse(String.t()) :: {:ok, [map()]} | {:error, term()}
  def parse(csv_string) when is_binary(csv_string) do
    cleaned = FlexCsvRouter.strip_duplicate_headers(csv_string)

    lines =
      cleaned
      |> String.split(~r/\r?\n/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case lines do
      [_header | data_lines] when data_lines != [] ->
        transactions =
          data_lines
          |> Enum.map(&parse_line/1)
          |> Enum.reject(&is_nil/1)
          |> assign_external_ids()

        {:ok, transactions}

      [_header] ->
        {:ok, []}

      _ ->
        {:error, :empty_csv}
    end
  end

  @doc """
  Parses a Flex trades CSV file from disk.
  """
  @spec parse_file(String.t()) :: {:ok, [map()]} | {:error, term()}
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, reason} -> {:error, reason}
    end
  end

  # Parse a single CSV line (14 fields)
  defp parse_line(line) do
    fields =
      line
      |> String.split(",")
      |> Enum.map(&String.trim(&1, "\""))

    case fields do
      [
        isin,
        figi,
        _cusip,
        _conid,
        symbol,
        currency,
        fx_rate,
        trade_id,
        trade_date,
        quantity,
        price,
        taxes,
        buy_sell,
        exchange
      ] ->
        raw = %{
          isin: isin,
          figi: figi,
          symbol: symbol,
          currency: currency,
          fx_rate: fx_rate,
          trade_id: trade_id,
          trade_date: trade_date,
          quantity: quantity,
          price: price,
          taxes: taxes,
          buy_sell: buy_sell,
          exchange: exchange
        }

        build_transaction(raw)

      _ ->
        nil
    end
  end

  defp build_transaction(raw) do
    quantity = parse_decimal(raw.quantity)
    is_fx = String.contains?(raw.symbol, ".") and blank?(raw.isin)
    transaction_type = resolve_transaction_type(raw.buy_sell, is_fx, quantity)
    price = parse_decimal(raw.price)

    %{
      broker: "ibkr",
      transaction_type: transaction_type,
      raw_type: raw.buy_sell,
      trade_date: parse_trade_date(raw.trade_date),
      entry_date: parse_trade_date(raw.trade_date),
      security_name: raw.symbol,
      isin: blank_to_nil(raw.isin),
      quantity: quantity,
      price: price,
      amount: compute_amount(quantity, price),
      currency: blank_to_nil(raw.currency),
      exchange_rate: parse_decimal(raw.fx_rate),
      commission: parse_decimal(raw.taxes),
      description: "#{raw.buy_sell} #{raw.quantity} #{raw.symbol} @ #{raw.price}",
      raw_data: %{
        "symbol" => raw.symbol,
        "figi" => blank_to_nil(raw.figi),
        "trade_id" => raw.trade_id,
        "exchange" => blank_to_nil(raw.exchange),
        "fx_rate" => raw.fx_rate,
        "is_fx_trade" => is_fx
      }
    }
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(val), do: val

  defp resolve_transaction_type(buy_sell, true = _is_fx, quantity) do
    cond do
      quantity && Decimal.negative?(quantity) -> "fx_sell"
      buy_sell == "SELL" -> "fx_sell"
      true -> "fx_buy"
    end
  end

  defp resolve_transaction_type(buy_sell, false = _is_fx, _quantity) do
    case String.upcase(buy_sell) do
      "BUY" -> "buy"
      "SELL" -> "sell"
      _ -> "corporate_action"
    end
  end

  defp compute_amount(nil, _price), do: nil
  defp compute_amount(_qty, nil), do: nil

  defp compute_amount(quantity, price) do
    Decimal.mult(quantity, price) |> Decimal.negate()
  end

  defp assign_external_ids(transactions) do
    {result, _counts} =
      Enum.reduce(transactions, {[], %{}}, fn txn, {acc, counts} ->
        key = dedup_key(txn)
        seq = Map.get(counts, key, 0)

        hash =
          :crypto.hash(:sha256, "#{key}:#{seq}")
          |> Base.encode16(case: :lower)
          |> String.slice(0, 16)

        new_txn = Map.put(txn, :external_id, "ibkr_flex_#{hash}")
        {[new_txn | acc], Map.put(counts, key, seq + 1)}
      end)

    Enum.reverse(result)
  end

  defp dedup_key(txn) do
    trade_id = get_in(txn, [:raw_data, "trade_id"]) || "-"
    "ibkr_flex:#{txn.trade_date}:#{txn.raw_type}:#{txn.security_name}:#{trade_id}"
  end

  # IBKR Flex uses YYYYMMDD format for TradeDate
  defp parse_trade_date(nil), do: nil
  defp parse_trade_date(""), do: nil

  defp parse_trade_date(str) when byte_size(str) == 10 do
    # Already ISO format
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_trade_date(str) when byte_size(str) == 8 do
    <<year::binary-4, month::binary-2, day::binary-2>> = str

    case Date.new(
           String.to_integer(year),
           String.to_integer(month),
           String.to_integer(day)
         ) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_trade_date(_), do: nil

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
