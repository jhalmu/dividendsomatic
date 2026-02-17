defmodule Dividendsomatic.Portfolio.FlexDividendCsvParser do
  @moduledoc """
  Parses IBKR Flex Dividend CSV reports (11-column format).

  Format: Symbol, ISIN, FIGI, AssetClass, CurrencyPrimary, FXRateToBase,
          ExDate, PayDate, Quantity, GrossRate, NetAmount

  NetAmount is the total net dividend payment (post-withholding tax).
  GrossRate is the per-share gross rate (before tax).
  Duplicate header rows mid-file are automatically stripped.
  """

  alias Dividendsomatic.Portfolio.FlexCsvRouter

  @isin_currency_map %{
    "US" => "USD",
    "CA" => "CAD",
    "SE" => "SEK",
    "FI" => "EUR",
    "DE" => "EUR",
    "FR" => "EUR",
    "NL" => "EUR",
    "BE" => "EUR",
    "JP" => "JPY",
    "GB" => "GBP",
    "HK" => "HKD",
    "IL" => "ILS",
    "NO" => "NOK",
    "DK" => "DKK",
    "AU" => "AUD"
  }

  @doc """
  Parses a Flex dividend CSV string into a list of dividend attribute maps.

  Returns `{:ok, records}` or `{:error, reason}`.
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
        records =
          data_lines
          |> Enum.map(&parse_line/1)
          |> Enum.reject(&is_nil/1)

        {:ok, records}

      [_header] ->
        {:ok, []}

      _ ->
        {:error, :empty_csv}
    end
  end

  @doc """
  Parses a Flex dividend CSV file from disk.
  """
  @spec parse_file(String.t()) :: {:ok, [map()]} | {:error, term()}
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, reason} -> {:error, reason}
    end
  end

  # Parse a single CSV line (11 fields)
  defp parse_line(line) do
    fields =
      line
      |> String.split(",")
      |> Enum.map(&String.trim(&1, "\""))

    case fields do
      [
        symbol,
        isin,
        figi,
        _asset_class,
        currency,
        fx_rate,
        ex_date,
        pay_date,
        quantity,
        gross_rate,
        net_amount
      ] ->
        raw = %{
          symbol: symbol,
          isin: isin,
          figi: figi,
          currency: currency,
          fx_rate: fx_rate,
          ex_date: ex_date,
          pay_date: pay_date,
          quantity: quantity,
          gross_rate: gross_rate,
          net_amount: net_amount
        }

        build_record(raw)

      _ ->
        nil
    end
  end

  defp build_record(raw) do
    net_amount = parse_decimal(raw.net_amount)
    abs_net = if net_amount, do: Decimal.abs(net_amount), else: nil

    if abs_net && Decimal.compare(abs_net, Decimal.new("0")) == :gt do
      %{
        symbol: raw.symbol,
        isin: blank_to_nil(raw.isin),
        figi: blank_to_nil(raw.figi),
        currency: resolve_currency(raw.currency, raw.isin, raw.fx_rate),
        fx_rate: parse_decimal(raw.fx_rate),
        ex_date: parse_date(raw.ex_date),
        pay_date: parse_date(raw.pay_date),
        quantity_at_record: parse_decimal(raw.quantity),
        gross_rate: parse_decimal(raw.gross_rate),
        net_amount: abs_net,
        amount: abs_net,
        amount_type: "total_net",
        source: "ibkr_flex_dividend"
      }
    else
      nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(val), do: val

  defp resolve_currency(currency, isin, fx_rate_str) do
    cond do
      currency != "" and currency != nil -> currency
      isin != "" and isin != nil -> Map.get(@isin_currency_map, String.slice(isin, 0, 2), "EUR")
      fx_rate_str == "1" -> "EUR"
      true -> "EUR"
    end
  end

  defp parse_date(""), do: nil
  defp parse_date(nil), do: nil

  defp parse_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(str) do
    case Decimal.parse(str) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end
end
