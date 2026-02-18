defmodule Dividendsomatic.MarketData.Providers.YahooFinance do
  @moduledoc """
  Yahoo Finance market data provider.

  Supports historical candles, forex, and company profiles. No API key required.
  Uses the unofficial Yahoo Finance chart API (v8) and quoteSummary API (v10).
  Profile fetching requires a cookie+crumb flow via fc.yahoo.com.
  """

  @behaviour Dividendsomatic.MarketData.Provider

  require Logger

  alias Dividendsomatic.Stocks.YahooFinance, as: YF

  @base_url "https://query1.finance.yahoo.com/v8/finance/chart"
  @summary_url "https://query2.finance.yahoo.com/v10/finance/quoteSummary"
  @headers [{"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}]

  @impl true
  def get_quote(_symbol), do: {:error, :not_supported}

  @impl true
  def get_company_profile(symbol) do
    yahoo_symbol = YF.to_yahoo_symbol(symbol)
    fetch_profile(yahoo_symbol)
  end

  @impl true
  def get_candles(symbol, from_date, to_date, _opts) do
    yahoo_symbol = YF.to_yahoo_symbol(symbol)
    fetch(yahoo_symbol, from_date, to_date)
  end

  @impl true
  def get_forex_candles(pair, from_date, to_date) do
    yahoo_pair = YF.forex_to_yahoo(pair)
    fetch(yahoo_pair, from_date, to_date)
  end

  defp fetch(yahoo_symbol, from_date, to_date) do
    from_ts = date_to_unix(from_date)
    to_ts = date_to_unix(Date.add(to_date, 1))

    Req.new(
      base_url: @base_url,
      headers: @headers,
      plug: {Req.Test, __MODULE__},
      retry: false
    )
    |> Req.get(
      url: "/#{URI.encode(yahoo_symbol)}",
      params: [period1: from_ts, period2: to_ts, interval: "1d"]
    )
    |> handle_response()
  end

  defp handle_response({:ok, %{status: 200, body: body}}), do: parse_chart_response(body)
  defp handle_response({:ok, %{status: 404}}), do: {:error, :not_found}
  defp handle_response({:ok, %{status: 429}}), do: {:error, :rate_limited}
  defp handle_response({:ok, %{status: _}}), do: {:error, :api_error}
  defp handle_response({:error, reason}), do: {:error, reason}

  defp parse_chart_response(%{"chart" => %{"result" => [result | _]}}) do
    timestamps = result["timestamp"] || []
    indicators = get_in(result, ["indicators", "quote", Access.at(0)]) || %{}

    records =
      timestamps
      |> Enum.with_index()
      |> Enum.map(fn {ts, i} ->
        %{
          date: unix_to_date(ts),
          open: get_in(indicators, ["open", Access.at(i)]),
          high: get_in(indicators, ["high", Access.at(i)]),
          low: get_in(indicators, ["low", Access.at(i)]),
          close: get_in(indicators, ["close", Access.at(i)]),
          volume: get_in(indicators, ["volume", Access.at(i)])
        }
      end)
      |> Enum.reject(fn r -> is_nil(r.close) end)

    {:ok, records}
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

  defp unix_to_date(ts), do: ts |> DateTime.from_unix!() |> DateTime.to_date()

  # --- Company Profile via quoteSummary API ---

  defp fetch_profile(yahoo_symbol) do
    with {:ok, cookie, crumb} <- get_crumb(),
         {:ok, data} <- fetch_summary(yahoo_symbol, cookie, crumb) do
      {:ok, data}
    else
      {:error, reason} ->
        Logger.debug("Yahoo profile fetch failed for #{yahoo_symbol}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_crumb do
    # Step 1: Get cookie from fc.yahoo.com
    case Req.new(headers: @headers, redirect: false, retry: false)
         |> Req.get(url: "https://fc.yahoo.com") do
      {:ok, %{headers: headers}} ->
        headers |> extract_cookie() |> fetch_crumb()

      _ ->
        {:error, :cookie_failed}
    end
  end

  defp extract_cookie(headers) do
    headers
    |> Enum.filter(fn {k, _} -> String.downcase(k) == "set-cookie" end)
    |> Enum.flat_map(fn {_, v} ->
      values = if is_list(v), do: v, else: [v]
      Enum.map(values, fn s -> s |> String.split(";") |> hd() end)
    end)
    |> Enum.join("; ")
  end

  defp fetch_crumb(""), do: {:error, :no_cookie}

  defp fetch_crumb(cookie) do
    case Req.new(headers: @headers ++ [{"cookie", cookie}], retry: false)
         |> Req.get(url: "https://query2.finance.yahoo.com/v1/test/getcrumb") do
      {:ok, %{status: 200, body: crumb}} when is_binary(crumb) and crumb != "" ->
        {:ok, cookie, crumb}

      _ ->
        {:error, :crumb_failed}
    end
  end

  defp fetch_summary(yahoo_symbol, cookie, crumb) do
    case Req.new(
           headers: @headers ++ [{"cookie", cookie}],
           retry: false
         )
         |> Req.get(
           url: "#{@summary_url}/#{URI.encode(yahoo_symbol)}",
           params: [modules: "assetProfile", crumb: crumb]
         ) do
      {:ok, %{status: 200, body: body}} ->
        parse_profile(body)

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_profile(%{
         "quoteSummary" => %{"result" => [%{"assetProfile" => profile} | _]}
       }) do
    {:ok,
     %{
       name: nil,
       sector: profile["sector"],
       industry: profile["industry"],
       country: profile["country"],
       exchange: nil,
       currency: nil,
       ipo_date: nil,
       market_cap: nil,
       logo_url: nil,
       web_url: profile["website"]
     }}
  end

  defp parse_profile(_), do: {:error, :invalid_response}
end
