defmodule Dividendsomatic.MarketData.Providers.Eodhd do
  @moduledoc """
  EODHD market data provider.

  Supports quotes, historical candles, forex, and company profiles.
  API key from EODHD_API_KEY env var. Symbol format: TICKER.EXCHANGE.
  """

  @behaviour Dividendsomatic.MarketData.Provider

  require Logger

  @base_url "https://eodhd.com/api"

  # --- Behaviour callbacks ---

  @impl true
  def get_quote(symbol), do: do_get_quote(symbol, [])

  def get_quote(symbol, opts), do: do_get_quote(symbol, opts)

  @impl true
  def get_candles(symbol, from_date, to_date, opts) do
    api_key_opts = if is_list(opts), do: opts, else: []

    with {:ok, api_key} <- resolve_api_key(api_key_opts) do
      eodhd_symbol = symbol_to_eodhd(symbol)

      build_req()
      |> Req.get(
        url: "/eod/#{eodhd_symbol}",
        params: [
          api_token: api_key,
          fmt: "json",
          period: "d",
          from: Date.to_iso8601(from_date),
          to: Date.to_iso8601(to_date)
        ]
      )
      |> handle_candles_response()
    end
  end

  @impl true
  def get_forex_candles(pair, from_date, to_date),
    do: do_get_forex_candles(pair, from_date, to_date, [])

  def get_forex_candles(pair, from_date, to_date, opts),
    do: do_get_forex_candles(pair, from_date, to_date, opts)

  @impl true
  def get_company_profile(symbol), do: do_get_company_profile(symbol, [])

  def get_company_profile(symbol, opts), do: do_get_company_profile(symbol, opts)

  # --- Implementation ---

  defp do_get_quote(symbol, opts) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      eodhd_symbol = symbol_to_eodhd(symbol)

      build_req()
      |> Req.get(url: "/real-time/#{eodhd_symbol}", params: [api_token: api_key, fmt: "json"])
      |> handle_quote_response()
    end
  end

  defp do_get_forex_candles(pair, from_date, to_date, opts) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      eodhd_pair = oanda_to_eodhd(pair)

      build_req()
      |> Req.get(
        url: "/eod/#{eodhd_pair}",
        params: [
          api_token: api_key,
          fmt: "json",
          period: "d",
          from: Date.to_iso8601(from_date),
          to: Date.to_iso8601(to_date)
        ]
      )
      |> handle_candles_response()
    end
  end

  defp do_get_company_profile(symbol, opts) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      eodhd_symbol = symbol_to_eodhd(symbol)

      build_req()
      |> Req.get(
        url: "/fundamentals/#{eodhd_symbol}",
        params: [api_token: api_key, fmt: "json", filter: "General,Highlights"]
      )
      |> handle_profile_response()
    end
  end

  # --- Symbol conversion ---

  @doc """
  Converts a Finnhub-style symbol to EODHD format.

  US stocks without a suffix get `.US` appended.
  Symbols already containing a dot are passed through unchanged.
  """
  def symbol_to_eodhd(symbol) do
    if String.contains?(symbol, "."), do: symbol, else: "#{symbol}.US"
  end

  @doc """
  Converts an OANDA forex pair to EODHD format.

  "OANDA:EUR_USD" becomes "EURUSD.FOREX".
  Non-OANDA strings pass through unchanged.
  """
  def oanda_to_eodhd(oanda_pair) do
    case Regex.run(~r/OANDA:(\w+)_(\w+)/, oanda_pair) do
      [_, base, quote_curr] -> "#{base}#{quote_curr}.FOREX"
      _ -> oanda_pair
    end
  end

  # --- Req builder ---

  defp build_req do
    opts = [base_url: @base_url, retry: false]

    opts =
      if Application.get_env(:dividendsomatic, :env) == :test,
        do: Keyword.put(opts, :plug, {Req.Test, __MODULE__}),
        else: opts

    Req.new(opts)
  end

  # --- Response handlers ---
  # Return raw maps (no Decimal conversion — the Stocks context handles that).

  defp handle_quote_response({:ok, %{status: 200, body: body}}) when is_map(body) do
    {:ok,
     %{
       current_price: body["close"],
       change: body["change"],
       percent_change: body["change_p"],
       high: body["high"],
       low: body["low"],
       open: body["open"],
       previous_close: body["previousClose"]
     }}
  end

  defp handle_quote_response({:ok, %{status: 429}}), do: {:error, :rate_limited}

  defp handle_quote_response({:ok, %{status: status}}) do
    Logger.error("EODHD quote failed: HTTP #{status}")
    {:error, :api_error}
  end

  defp handle_quote_response({:error, reason}), do: {:error, reason}

  defp handle_candles_response({:ok, %{status: 200, body: body}}) when is_list(body) do
    records =
      Enum.map(body, fn row ->
        {:ok, date} = Date.from_iso8601(row["date"])

        %{
          date: date,
          open: row["open"],
          high: row["high"],
          low: row["low"],
          close: row["close"] || row["adjusted_close"],
          volume: row["volume"]
        }
      end)

    {:ok, records}
  end

  defp handle_candles_response({:ok, %{status: 429}}), do: {:error, :rate_limited}

  defp handle_candles_response({:ok, %{status: status}}) do
    Logger.error("EODHD candles failed: HTTP #{status}")
    {:error, :api_error}
  end

  defp handle_candles_response({:error, reason}), do: {:error, reason}

  defp handle_profile_response({:ok, %{status: 200, body: %{"General" => general} = body}})
       when is_map(general) do
    highlights = body["Highlights"] || %{}

    {:ok,
     %{
       name: general["Name"],
       country: general["CountryName"],
       currency: general["CurrencyCode"],
       exchange: general["Exchange"],
       sector: general["Sector"],
       industry: general["Industry"],
       ipo_date: general["IPODate"],
       market_cap: highlights["MarketCapitalization"],
       logo_url: general["LogoURL"],
       web_url: general["WebURL"],
       isin: general["ISIN"]
     }}
  end

  defp handle_profile_response({:ok, %{status: 200}}), do: {:error, :no_data}
  defp handle_profile_response({:ok, %{status: 429}}), do: {:error, :rate_limited}

  defp handle_profile_response({:ok, %{status: status}}) do
    Logger.error("EODHD profile failed: HTTP #{status}")
    {:error, :api_error}
  end

  defp handle_profile_response({:error, reason}), do: {:error, reason}

  # --- Helpers ---

  defp resolve_api_key(opts) do
    case Keyword.get(opts, :api_key) || Application.get_env(:dividendsomatic, :eodhd_api_key) do
      nil -> {:error, :not_configured}
      key -> {:ok, key}
    end
  end
end
