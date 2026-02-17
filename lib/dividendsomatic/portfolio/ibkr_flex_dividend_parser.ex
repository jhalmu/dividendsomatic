defmodule Dividendsomatic.Portfolio.IbkrFlexDividendParser do
  @moduledoc """
  Parses IBKR Flex dividend CSV reports.

  Format: "Symbol","PayDate","NetAmount","FXRateToBase","ISIN","CUSIP"
  These contain total net amounts (already after withholding tax).
  """

  @doc """
  Parses a Flex dividend CSV string into a list of maps.

  Returns `{:ok, records}` or `{:error, reason}`.
  """
  def parse(csv_string) when is_binary(csv_string) do
    lines =
      csv_string
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case lines do
      [_header | data_lines] ->
        records =
          data_lines
          |> Enum.map(&parse_line/1)
          |> Enum.reject(&is_nil/1)

        {:ok, records}

      _ ->
        {:error, :empty_csv}
    end
  end

  @doc """
  Parses a Flex dividend CSV file from disk.
  """
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_line(line) do
    fields =
      line
      |> String.split(",")
      |> Enum.map(&String.trim(&1, "\""))

    case fields do
      [symbol, pay_date, net_amount, fx_rate, isin, _cusip] ->
        build_record(symbol, pay_date, net_amount, fx_rate, isin)

      _ ->
        nil
    end
  end

  defp build_record(symbol, pay_date_str, net_amount_str, fx_rate_str, isin) do
    with {net_amount, _} <- Decimal.parse(net_amount_str),
         true <- Decimal.compare(net_amount, Decimal.new("0")) == :gt do
      %{
        symbol: symbol,
        pay_date: parse_date(pay_date_str),
        net_amount: net_amount,
        fx_rate: parse_decimal(fx_rate_str),
        isin: if(isin == "", do: nil, else: isin),
        amount_type: "total_net",
        source: "ibkr_flex_dividend"
      }
    else
      _ -> nil
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

  defp parse_decimal(str) do
    case Decimal.parse(str) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end
end
