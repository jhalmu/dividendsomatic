defmodule Dividendsomatic.Stocks do
  @moduledoc """
  Stock data integration using Finnhub API.

  Provides real-time quotes and company profiles with caching.

  ## Configuration

  Set `FINNHUB_API_KEY` environment variable.

  ## Rate Limits

  Free tier: 60 calls/minute
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Repo
  alias Dividendsomatic.Stocks.{CompanyProfile, StockQuote}

  @finnhub_base_url "https://finnhub.io/api/v1"
  @quote_cache_seconds 900
  @profile_cache_seconds 604_800

  @doc """
  Gets a stock quote, using cache if fresh enough.

  Returns cached data if less than 15 minutes old, otherwise fetches fresh data.
  """
  def get_quote(symbol) do
    case get_cached_quote(symbol) do
      %StockQuote{} = quote ->
        if stale?(quote.fetched_at, @quote_cache_seconds) do
          fetch_and_cache_quote(symbol)
        else
          {:ok, quote}
        end

      nil ->
        fetch_and_cache_quote(symbol)
    end
  end

  @doc """
  Gets company profile, using cache if fresh enough.

  Returns cached data if less than 7 days old, otherwise fetches fresh data.
  """
  def get_company_profile(symbol) do
    case get_cached_profile(symbol) do
      %CompanyProfile{} = profile ->
        if stale?(profile.fetched_at, @profile_cache_seconds) do
          fetch_and_cache_profile(symbol)
        else
          {:ok, profile}
        end

      nil ->
        fetch_and_cache_profile(symbol)
    end
  end

  @doc """
  Gets quotes for multiple symbols.

  Returns a map of symbol => quote data.
  """
  def get_quotes(symbols) when is_list(symbols) do
    symbols
    |> Enum.map(fn symbol ->
      case get_quote(symbol) do
        {:ok, quote} -> {symbol, quote}
        {:error, _} -> {symbol, nil}
      end
    end)
    |> Enum.into(%{})
  end

  @doc """
  Forces refresh of a quote from the API.
  """
  def refresh_quote(symbol) do
    fetch_and_cache_quote(symbol)
  end

  @doc """
  Lists all cached quotes.
  """
  def list_cached_quotes do
    StockQuote
    |> order_by([q], asc: q.symbol)
    |> Repo.all()
  end

  defp get_cached_quote(symbol) do
    Repo.get_by(StockQuote, symbol: symbol)
  end

  defp get_cached_profile(symbol) do
    Repo.get_by(CompanyProfile, symbol: symbol)
  end

  defp stale?(fetched_at, max_age_seconds) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, fetched_at, :second)
    diff > max_age_seconds
  end

  defp fetch_and_cache_quote(symbol) do
    case get_api_key() do
      {:ok, api_key} ->
        fetch_quote_from_api(symbol, api_key)

      {:error, :not_configured} ->
        Logger.warning("Finnhub API key not configured")
        {:error, :not_configured}
    end
  end

  defp fetch_and_cache_profile(symbol) do
    case get_api_key() do
      {:ok, api_key} ->
        fetch_profile_from_api(symbol, api_key)

      {:error, :not_configured} ->
        Logger.warning("Finnhub API key not configured")
        {:error, :not_configured}
    end
  end

  defp fetch_quote_from_api(symbol, api_key) do
    url = "#{@finnhub_base_url}/quote"

    case Req.get(url, params: [symbol: symbol, token: api_key]) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        if body["c"] && body["c"] != 0 do
          upsert_quote(symbol, body)
        else
          Logger.warning("No quote data for symbol: #{symbol}")
          {:error, :no_data}
        end

      {:ok, %{status: 429}} ->
        Logger.warning("Finnhub rate limit exceeded")
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Finnhub quote failed: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("Finnhub request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_profile_from_api(symbol, api_key) do
    url = "#{@finnhub_base_url}/stock/profile2"

    case Req.get(url, params: [symbol: symbol, token: api_key]) do
      {:ok, %{status: 200, body: body}} when is_map(body) and map_size(body) > 0 ->
        upsert_profile(symbol, body)

      {:ok, %{status: 200, body: _}} ->
        Logger.warning("No profile data for symbol: #{symbol}")
        {:error, :no_data}

      {:ok, %{status: 429}} ->
        Logger.warning("Finnhub rate limit exceeded")
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Finnhub profile failed: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("Finnhub request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp upsert_quote(symbol, api_data) do
    attrs = %{
      symbol: symbol,
      current_price: Decimal.new("#{api_data["c"]}"),
      change: Decimal.new("#{api_data["d"]}"),
      percent_change: Decimal.new("#{api_data["dp"]}"),
      high: Decimal.new("#{api_data["h"]}"),
      low: Decimal.new("#{api_data["l"]}"),
      open: Decimal.new("#{api_data["o"]}"),
      previous_close: Decimal.new("#{api_data["pc"]}"),
      fetched_at: DateTime.utc_now()
    }

    case get_cached_quote(symbol) do
      nil ->
        %StockQuote{}
        |> StockQuote.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> StockQuote.changeset(attrs)
        |> Repo.update()
    end
  end

  defp upsert_profile(symbol, api_data) do
    attrs = %{
      symbol: symbol,
      name: api_data["name"],
      country: api_data["country"],
      currency: api_data["currency"],
      exchange: api_data["exchange"],
      ipo_date: parse_date(api_data["ipo"]),
      market_cap: parse_market_cap(api_data["marketCapitalization"]),
      sector: api_data["finnhubIndustry"],
      industry: api_data["finnhubIndustry"],
      logo_url: api_data["logo"],
      web_url: api_data["weburl"],
      fetched_at: DateTime.utc_now()
    }

    case get_cached_profile(symbol) do
      nil ->
        %CompanyProfile{}
        |> CompanyProfile.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> CompanyProfile.changeset(attrs)
        |> Repo.update()
    end
  end

  defp get_api_key do
    case Application.get_env(:dividendsomatic, :finnhub_api_key) do
      nil -> {:error, :not_configured}
      key -> {:ok, key}
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_market_cap(nil), do: nil
  defp parse_market_cap(value) when is_number(value), do: Decimal.new("#{value}")
  defp parse_market_cap(_), do: nil
end
