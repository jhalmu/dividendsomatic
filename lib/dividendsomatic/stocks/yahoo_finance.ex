defmodule Dividendsomatic.Stocks.YahooFinance do
  @moduledoc """
  Yahoo Finance adapter for historical OHLCV price data.

  Uses the unofficial Yahoo Finance chart API (v8) which returns JSON with
  daily candle data. No API key required.

  Symbol conversion follows the same conventions as `tools/yfinance_fetch.py`.
  """

  require Logger

  @base_url "https://query1.finance.yahoo.com/v8/finance/chart"

  # Yahoo Finance needs specific User-Agent or returns 403
  @headers [{"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}]

  # Finnhub/internal symbol → Yahoo symbol overrides for tickers that differ
  @yahoo_overrides %{
    # Helsinki primary listing preferred over Frankfurt
    "TELIA1.F" => "TELIA1.HE",
    "RAUA.F" => "RAUTE.HE",
    # IB short codes → correct Yahoo tickers
    "OUTA.HE" => "OUT1V.HE"
  }

  @doc """
  Fetches daily OHLCV candle data from Yahoo Finance.

  Returns `{:ok, [%{date, open, high, low, close, volume}]}` or `{:error, reason}`.
  """
  def fetch_candles(yahoo_symbol, from_date, to_date) do
    from_ts = date_to_unix(from_date)
    to_ts = date_to_unix(Date.add(to_date, 1))

    url = "#{@base_url}/#{URI.encode(yahoo_symbol)}"

    case Req.get(url,
           params: [period1: from_ts, period2: to_ts, interval: "1d"],
           headers: @headers
         ) do
      {:ok, %{status: 200, body: body}} ->
        parse_chart_response(body)

      {:ok, %{status: 404, body: _}} ->
        {:error, :not_found}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        error = get_in(body, ["chart", "error", "description"]) || "HTTP #{status}"
        Logger.warning("Yahoo Finance error for #{yahoo_symbol}: #{error}")
        {:error, {:api_error, error}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Yahoo Finance request failed: #{Exception.message(e)}")
      {:error, :request_failed}
  end

  @doc """
  Fetches daily forex rate data from Yahoo Finance.

  Pair format: "EURUSD=X" for EUR/USD. Returns same format as `fetch_candles/3`.
  """
  def fetch_forex(pair, from_date, to_date) do
    fetch_candles(pair, from_date, to_date)
  end

  @doc """
  Converts a Finnhub-style symbol to Yahoo Finance format.

  Most symbols are already in Yahoo format (e.g., "NOKIA.HE", "MAIN").
  Applies overrides for tickers that differ between Finnhub and Yahoo.
  """
  def to_yahoo_symbol(symbol) do
    symbol
    |> then(&Map.get(@yahoo_overrides, &1, &1))
    |> String.replace(" ", "-")
  end

  @doc """
  Converts an OANDA-style forex pair to Yahoo Finance format.

  "OANDA:EUR_USD" → "EURUSD=X"
  """
  def forex_to_yahoo(oanda_pair) do
    case Regex.run(~r/OANDA:(\w+)_(\w+)/, oanda_pair) do
      [_, base, quote_currency] -> "#{base}#{quote_currency}=X"
      _ -> oanda_pair
    end
  end

  # Parse Yahoo Finance chart API response
  defp parse_chart_response(%{"chart" => %{"result" => [result | _]}}) do
    timestamps = result["timestamp"] || []
    indicators = get_in(result, ["indicators", "quote", Access.at(0)]) || %{}

    opens = indicators["open"] || []
    highs = indicators["high"] || []
    lows = indicators["low"] || []
    closes = indicators["close"] || []
    volumes = indicators["volume"] || []

    records =
      timestamps
      |> Enum.with_index()
      |> Enum.map(fn {ts, i} ->
        %{
          date: unix_to_date(ts),
          open: Enum.at(opens, i),
          high: Enum.at(highs, i),
          low: Enum.at(lows, i),
          close: Enum.at(closes, i),
          volume: Enum.at(volumes, i)
        }
      end)
      |> Enum.reject(fn r -> is_nil(r.close) end)

    {:ok, records}
  end

  defp parse_chart_response(%{"chart" => %{"error" => %{"description" => desc}}}) do
    {:error, {:api_error, desc}}
  end

  defp parse_chart_response(_), do: {:error, :invalid_response}

  defp date_to_unix(date) do
    date
    |> Date.to_iso8601()
    |> then(&(&1 <> "T00:00:00Z"))
    |> DateTime.from_iso8601()
    |> elem(1)
    |> DateTime.to_unix()
  end

  defp unix_to_date(timestamp) do
    timestamp
    |> DateTime.from_unix!()
    |> DateTime.to_date()
  end
end
