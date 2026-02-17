defmodule Dividendsomatic.Portfolio.YahooDividendParser do
  @moduledoc """
  Parses Yahoo Finance dividend JSON files.

  Format: JSON array of objects with keys:
  symbol, yahoo_symbol, exchange, isin, ex_date, amount, currency
  """

  @doc """
  Parses a Yahoo dividend JSON string into a list of maps.

  Returns `{:ok, records}` or `{:error, reason}`.
  """
  def parse(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, records} when is_list(records) ->
        parsed =
          records
          |> Enum.map(&parse_record/1)
          |> Enum.reject(&is_nil/1)

        {:ok, parsed}

      {:ok, _} ->
        {:error, :not_an_array}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parses a Yahoo dividend JSON file from disk.
  """
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_record(%{"ex_date" => ex_date, "amount" => amount} = record)
       when is_number(amount) and amount > 0 do
    %{
      symbol: record["symbol"],
      yahoo_symbol: record["yahoo_symbol"],
      exchange: record["exchange"],
      isin: record["isin"],
      ex_date: parse_date(ex_date),
      amount: Decimal.new(to_string(amount)),
      currency: record["currency"] || "USD",
      source: "yfinance"
    }
  end

  defp parse_record(_), do: nil

  defp parse_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil
end
