defmodule Dividendsomatic.MarketData.Providers.Finnhub do
  @moduledoc """
  Finnhub market data provider.

  Implements the Provider behaviour for real-time quotes, company profiles,
  financial metrics, historical candles, and ISIN lookup.

  Free tier: 60 calls/minute. API key from FINNHUB_API_KEY env var.
  """

  @behaviour Dividendsomatic.MarketData.Provider

  require Logger

  @base_url "https://finnhub.io/api/v1"

  # --- Behaviour callbacks ---
  #
  # Each callback delegates to a 2-arity (or +1) version that accepts
  # an opts keyword list with `api_key: "key"` for testing.

  @impl true
  def get_quote(symbol), do: do_get_quote(symbol, [])

  def get_quote(symbol, opts), do: do_get_quote(symbol, opts)

  @impl true
  def get_candles(symbol, from_date, to_date, opts) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      params = [
        symbol: symbol,
        resolution: "D",
        from: date_to_unix(from_date),
        to: date_to_unix(to_date),
        token: api_key
      ]

      build_req()
      |> Req.get(url: "/stock/candle", params: params)
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

  @impl true
  def get_financial_metrics(symbol), do: do_get_financial_metrics(symbol, [])

  def get_financial_metrics(symbol, opts), do: do_get_financial_metrics(symbol, opts)

  @impl true
  def lookup_symbol_by_isin(isin), do: do_lookup_symbol_by_isin(isin, [])

  def lookup_symbol_by_isin(isin, opts), do: do_lookup_symbol_by_isin(isin, opts)

  # --- Implementation ---

  defp do_get_quote(symbol, opts) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      build_req()
      |> Req.get(url: "/quote", params: [symbol: symbol, token: api_key])
      |> handle_quote_response()
    end
  end

  defp do_get_forex_candles(pair, from_date, to_date, opts) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      params = [
        symbol: pair,
        resolution: "D",
        from: date_to_unix(from_date),
        to: date_to_unix(to_date),
        token: api_key
      ]

      build_req()
      |> Req.get(url: "/forex/candle", params: params)
      |> handle_candles_response()
    end
  end

  defp do_get_company_profile(symbol, opts) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      build_req()
      |> Req.get(url: "/stock/profile2", params: [symbol: symbol, token: api_key])
      |> handle_profile_response()
    end
  end

  defp do_get_financial_metrics(symbol, opts) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      build_req()
      |> Req.get(
        url: "/stock/metric",
        params: [symbol: symbol, metric: "all", token: api_key]
      )
      |> handle_metrics_response()
    end
  end

  defp do_lookup_symbol_by_isin(isin, opts) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      build_req()
      |> Req.get(url: "/stock/profile2", params: [isin: isin, token: api_key])
      |> handle_isin_response()
    end
  end

  # --- Req builder ---

  defp build_req do
    Req.new(base_url: @base_url, plug: {Req.Test, __MODULE__}, retry: false)
  end

  # --- Response handlers ---
  # Return raw maps (no Decimal conversion — the Stocks context handles that).

  defp handle_quote_response({:ok, %{status: 200, body: body}}) when is_map(body) do
    if body["c"] && body["c"] != 0 do
      {:ok,
       %{
         current_price: body["c"],
         change: body["d"],
         percent_change: body["dp"],
         high: body["h"],
         low: body["l"],
         open: body["o"],
         previous_close: body["pc"]
       }}
    else
      {:error, :no_data}
    end
  end

  defp handle_quote_response({:ok, %{status: 429}}), do: {:error, :rate_limited}

  defp handle_quote_response({:ok, %{status: status}}) do
    Logger.error("Finnhub quote failed: HTTP #{status}")
    {:error, :api_error}
  end

  defp handle_quote_response({:error, reason}), do: {:error, reason}

  defp handle_candles_response({:ok, %{status: 200, body: %{"s" => "ok"} = body}}) do
    {:ok, parse_candle_body(body)}
  end

  defp handle_candles_response({:ok, %{status: 200, body: %{"s" => "no_data"}}}), do: {:ok, []}
  defp handle_candles_response({:ok, %{status: 429}}), do: {:error, :rate_limited}
  defp handle_candles_response({:ok, %{status: 403}}), do: {:error, :access_denied}

  defp handle_candles_response({:ok, %{status: status}}) do
    Logger.error("Finnhub candles failed: HTTP #{status}")
    {:error, :api_error}
  end

  defp handle_candles_response({:error, reason}), do: {:error, reason}

  defp handle_profile_response({:ok, %{status: 200, body: body}})
       when is_map(body) and map_size(body) > 0 do
    {:ok,
     %{
       name: body["name"],
       country: body["country"],
       currency: body["currency"],
       exchange: body["exchange"],
       sector: body["finnhubIndustry"],
       industry: body["finnhubIndustry"],
       ipo_date: body["ipo"],
       market_cap: body["marketCapitalization"],
       logo_url: body["logo"],
       web_url: body["weburl"]
     }}
  end

  defp handle_profile_response({:ok, %{status: 200}}), do: {:error, :no_data}
  defp handle_profile_response({:ok, %{status: 429}}), do: {:error, :rate_limited}

  defp handle_profile_response({:ok, %{status: status}}) do
    Logger.error("Finnhub profile failed: HTTP #{status}")
    {:error, :api_error}
  end

  defp handle_profile_response({:error, reason}), do: {:error, reason}

  defp handle_metrics_response({:ok, %{status: 200, body: %{"metric" => metric}}})
       when is_map(metric) do
    {:ok,
     %{
       pe_ratio: metric["peBasicExclExtraTTM"],
       pb_ratio: metric["pbQuarterly"],
       eps: metric["epsBasicExclExtraItemsTTM"],
       roe: metric["roeRfy"],
       roa: metric["roaRfy"],
       net_margin: metric["netProfitMarginTTM"],
       operating_margin: metric["operatingMarginTTM"],
       debt_to_equity: metric["totalDebt/totalEquityQuarterly"],
       current_ratio: metric["currentRatioQuarterly"],
       fcf_margin: metric["fcfMarginTTM"],
       beta: metric["beta"],
       payout_ratio: metric["payoutRatioTTM"]
     }}
  end

  defp handle_metrics_response({:ok, %{status: 200}}), do: {:error, :no_data}
  defp handle_metrics_response({:ok, %{status: 429}}), do: {:error, :rate_limited}

  defp handle_metrics_response({:ok, %{status: status}}) do
    Logger.error("Finnhub metrics failed: HTTP #{status}")
    {:error, :api_error}
  end

  defp handle_metrics_response({:error, reason}), do: {:error, reason}

  defp handle_isin_response({:ok, %{status: 200, body: body}})
       when is_map(body) and map_size(body) > 0 do
    {:ok,
     %{
       symbol: body["ticker"],
       exchange: body["exchange"],
       currency: body["currency"],
       name: body["name"]
     }}
  end

  defp handle_isin_response({:ok, %{status: 200}}), do: {:error, :not_found}
  defp handle_isin_response({:ok, %{status: 429}}), do: {:error, :rate_limited}

  defp handle_isin_response({:ok, %{status: status}}) do
    Logger.error("Finnhub ISIN lookup failed: HTTP #{status}")
    {:error, :api_error}
  end

  defp handle_isin_response({:error, reason}), do: {:error, reason}

  # --- Helpers ---

  defp parse_candle_body(body) do
    timestamps = body["t"] || []
    opens = body["o"] || []
    highs = body["h"] || []
    lows = body["l"] || []
    closes = body["c"] || []
    volumes = body["v"] || []

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
  end

  defp resolve_api_key(opts) do
    case Keyword.get(opts, :api_key) || Application.get_env(:dividendsomatic, :finnhub_api_key) do
      nil -> {:error, :not_configured}
      key -> {:ok, key}
    end
  end

  defp date_to_unix(date) do
    date
    |> Date.to_iso8601()
    |> then(&(&1 <> "T00:00:00Z"))
    |> DateTime.from_iso8601()
    |> elem(1)
    |> DateTime.to_unix()
  end

  defp unix_to_date(ts), do: ts |> DateTime.from_unix!() |> DateTime.to_date()
end
