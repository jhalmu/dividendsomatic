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

  alias Dividendsomatic.Stocks.{
    CompanyNote,
    CompanyProfile,
    HistoricalPrice,
    StockMetric,
    StockQuote,
    SymbolMapping,
    YahooFinance
  }

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
  Gets financial metrics, using cache if fresh enough.

  Returns cached data if less than 7 days old, otherwise fetches fresh data.
  """
  def get_financial_metrics(symbol) do
    case get_cached_metrics(symbol) do
      %StockMetric{} = metric ->
        if stale?(metric.fetched_at, @profile_cache_seconds) do
          fetch_and_cache_metrics(symbol)
        else
          {:ok, metric}
        end

      nil ->
        fetch_and_cache_metrics(symbol)
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

  defp get_cached_metrics(symbol) do
    Repo.get_by(StockMetric, symbol: symbol)
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

  defp fetch_and_cache_metrics(symbol) do
    case get_api_key() do
      {:ok, api_key} ->
        fetch_metrics_from_api(symbol, api_key)

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

  defp fetch_metrics_from_api(symbol, api_key) do
    url = "#{@finnhub_base_url}/stock/metric"

    case Req.get(url, params: [symbol: symbol, metric: "all", token: api_key]) do
      {:ok, %{status: 200, body: %{"metric" => metric}}} when is_map(metric) ->
        upsert_metrics(symbol, metric)

      {:ok, %{status: 200, body: _}} ->
        Logger.warning("No metrics data for symbol: #{symbol}")
        {:error, :no_data}

      {:ok, %{status: 429}} ->
        Logger.warning("Finnhub rate limit exceeded")
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Finnhub metrics failed: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("Finnhub request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp upsert_metrics(symbol, api_data) do
    attrs = %{
      symbol: symbol,
      pe_ratio: parse_decimal(api_data["peBasicExclExtraTTM"]),
      pb_ratio: parse_decimal(api_data["pbQuarterly"]),
      eps: parse_decimal(api_data["epsBasicExclExtraItemsTTM"]),
      roe: parse_decimal(api_data["roeRfy"]),
      roa: parse_decimal(api_data["roaRfy"]),
      net_margin: parse_decimal(api_data["netProfitMarginTTM"]),
      operating_margin: parse_decimal(api_data["operatingMarginTTM"]),
      debt_to_equity: parse_decimal(api_data["totalDebt/totalEquityQuarterly"]),
      current_ratio: parse_decimal(api_data["currentRatioQuarterly"]),
      fcf_margin: parse_decimal(api_data["fcfMarginTTM"]),
      beta: parse_decimal(api_data["beta"]),
      payout_ratio: parse_decimal(api_data["payoutRatioTTM"]),
      fetched_at: DateTime.utc_now()
    }

    case get_cached_metrics(symbol) do
      nil ->
        %StockMetric{}
        |> StockMetric.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> StockMetric.changeset(attrs)
        |> Repo.update()
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(value) when is_number(value), do: Decimal.new("#{value}")
  defp parse_decimal(_), do: nil

  ## Historical Prices

  @doc """
  Fetches daily candle data from Finnhub for a stock symbol.

  Returns `{:ok, count}` with number of records inserted, or `{:error, reason}`.
  """
  def fetch_historical_candles(symbol, from_date, to_date, opts \\ []) do
    isin = Keyword.get(opts, :isin)

    case get_api_key() do
      {:ok, api_key} ->
        from_ts = date_to_unix(from_date)
        to_ts = date_to_unix(to_date)
        url = "#{@finnhub_base_url}/stock/candle"

        case Req.get(url,
               params: [symbol: symbol, resolution: "D", from: from_ts, to: to_ts, token: api_key]
             ) do
          {:ok, %{status: 200, body: %{"s" => "ok"} = body}} ->
            insert_candle_data(symbol, isin, body)

          {:ok, %{status: 200, body: %{"s" => "no_data"}}} ->
            Logger.warning("No candle data for #{symbol} (#{from_date}..#{to_date})")
            {:ok, 0}

          {:ok, %{status: 429}} ->
            {:error, :rate_limited}

          {:ok, %{status: 403, body: _}} ->
            Logger.warning("Finnhub candle access denied for #{symbol} — paid plan required")
            {:error, :access_denied}

          {:ok, %{status: status, body: body}} ->
            Logger.error("Finnhub candle failed for #{symbol}: #{status} - #{inspect(body)}")
            {:error, :api_error}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_configured} ->
        {:error, :not_configured}
    end
  end

  @doc """
  Fetches daily forex candle data from Finnhub.

  Pair format: "OANDA:EUR_USD". Returns `{:ok, count}`.
  """
  def fetch_forex_candles(pair, from_date, to_date) do
    case get_api_key() do
      {:ok, api_key} ->
        from_ts = date_to_unix(from_date)
        to_ts = date_to_unix(to_date)
        url = "#{@finnhub_base_url}/forex/candle"

        case Req.get(url,
               params: [symbol: pair, resolution: "D", from: from_ts, to: to_ts, token: api_key]
             ) do
          {:ok, %{status: 200, body: %{"s" => "ok"} = body}} ->
            insert_candle_data(pair, nil, body)

          {:ok, %{status: 200, body: %{"s" => "no_data"}}} ->
            Logger.warning("No forex data for #{pair} (#{from_date}..#{to_date})")
            {:ok, 0}

          {:ok, %{status: 429}} ->
            {:error, :rate_limited}

          {:ok, %{status: 403, body: _}} ->
            Logger.warning("Finnhub forex access denied for #{pair} — paid plan required")
            {:error, :access_denied}

          {:ok, %{status: status, body: body}} ->
            Logger.error("Finnhub forex failed for #{pair}: #{status} - #{inspect(body)}")
            {:error, :api_error}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_configured} ->
        {:error, :not_configured}
    end
  end

  defp insert_candle_data(symbol, isin, body) do
    timestamps = body["t"] || []
    opens = body["o"] || []
    highs = body["h"] || []
    lows = body["l"] || []
    closes = body["c"] || []
    volumes = body["v"] || []

    records =
      timestamps
      |> Enum.with_index()
      |> Enum.map(fn {ts, i} ->
        %{
          symbol: symbol,
          isin: isin,
          date: unix_to_date(ts),
          open: parse_decimal(Enum.at(opens, i)),
          high: parse_decimal(Enum.at(highs, i)),
          low: parse_decimal(Enum.at(lows, i)),
          close: parse_decimal(Enum.at(closes, i)),
          volume: Enum.at(volumes, i),
          source: "finnhub"
        }
      end)

    count =
      Enum.reduce(records, 0, fn attrs, acc ->
        changeset = HistoricalPrice.changeset(%HistoricalPrice{}, attrs)

        case Repo.insert(changeset, on_conflict: :nothing, conflict_target: [:symbol, :date]) do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end)

    {:ok, count}
  end

  ## Yahoo Finance Historical Data

  @doc """
  Fetches daily candle data from Yahoo Finance for a stock symbol.

  Returns `{:ok, count}` with number of records inserted, or `{:error, reason}`.
  """
  def fetch_yahoo_candles(symbol, from_date, to_date, opts \\ []) do
    isin = Keyword.get(opts, :isin)
    yahoo_symbol = YahooFinance.to_yahoo_symbol(symbol)

    case YahooFinance.fetch_candles(yahoo_symbol, from_date, to_date) do
      {:ok, records} ->
        insert_yahoo_records(symbol, isin, records)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches daily forex candle data from Yahoo Finance.

  Pair format: "OANDA:EUR_USD" (converted to "EURUSD=X" internally).
  Returns `{:ok, count}`.
  """
  def fetch_yahoo_forex(oanda_pair, from_date, to_date) do
    yahoo_pair = YahooFinance.forex_to_yahoo(oanda_pair)

    case YahooFinance.fetch_forex(yahoo_pair, from_date, to_date) do
      {:ok, records} ->
        insert_yahoo_records(oanda_pair, nil, records)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp insert_yahoo_records(symbol, isin, records) do
    count =
      Enum.reduce(records, 0, fn record, acc ->
        attrs = %{
          symbol: symbol,
          isin: isin,
          date: record.date,
          open: parse_decimal(record.open),
          high: parse_decimal(record.high),
          low: parse_decimal(record.low),
          close: parse_decimal(record.close),
          volume: record.volume,
          source: "yahoo"
        }

        changeset = HistoricalPrice.changeset(%HistoricalPrice{}, attrs)

        case Repo.insert(changeset, on_conflict: :nothing, conflict_target: [:symbol, :date]) do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end)

    {:ok, count}
  end

  @doc """
  Gets the close price for a symbol on a given date.

  Falls back to the nearest prior trading day within 5 days.
  """
  def get_close_price(symbol, date) do
    lookback = Date.add(date, -5)

    HistoricalPrice
    |> where([p], p.symbol == ^symbol and p.date >= ^lookback and p.date <= ^date)
    |> order_by([p], desc: p.date)
    |> limit(1)
    |> Repo.one()
    |> case do
      %HistoricalPrice{close: close} when not is_nil(close) -> {:ok, close}
      _ -> {:error, :no_price}
    end
  end

  @doc """
  Gets the FX rate (close price) for a forex pair on a given date.

  Falls back to the nearest prior trading day within 5 days.
  """
  def get_fx_rate(pair, date) do
    get_close_price(pair, date)
  end

  @doc """
  Lists historical prices for a symbol within a date range.
  """
  def list_historical_prices(symbol, from_date, to_date) do
    HistoricalPrice
    |> where([p], p.symbol == ^symbol and p.date >= ^from_date and p.date <= ^to_date)
    |> order_by([p], asc: p.date)
    |> Repo.all()
  end

  @doc """
  Returns count of historical price records for a symbol.
  """
  def count_historical_prices(symbol) do
    HistoricalPrice
    |> where([p], p.symbol == ^symbol)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns the date range of historical prices for a symbol.
  """
  def historical_price_range(symbol) do
    HistoricalPrice
    |> where([p], p.symbol == ^symbol)
    |> select([p], %{min_date: min(p.date), max_date: max(p.date), count: count()})
    |> Repo.one()
  end

  ## Finnhub ISIN Lookup

  @doc """
  Looks up a stock's Finnhub symbol by ISIN using the /stock/profile2 endpoint.

  Returns `{:ok, %{symbol: "TICKER", exchange: "HEX", currency: "EUR"}}` or `{:error, reason}`.
  """
  def lookup_symbol_by_isin(isin) do
    case get_api_key() do
      {:ok, api_key} ->
        url = "#{@finnhub_base_url}/stock/profile2"

        case Req.get(url, params: [isin: isin, token: api_key]) do
          {:ok, %{status: 200, body: body}} when is_map(body) and map_size(body) > 0 ->
            {:ok,
             %{
               symbol: body["ticker"],
               exchange: body["exchange"],
               currency: body["currency"],
               name: body["name"]
             }}

          {:ok, %{status: 200, body: _}} ->
            {:error, :not_found}

          {:ok, %{status: 429}} ->
            {:error, :rate_limited}

          {:ok, %{status: status, body: body}} ->
            Logger.error("Finnhub ISIN lookup failed: #{status} - #{inspect(body)}")
            {:error, :api_error}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_configured} ->
        {:error, :not_configured}
    end
  end

  ## Batch Queries (for chart reconstruction)

  @doc """
  Loads all symbol mappings for a list of ISINs in a single query.

  Returns `%{isin => %SymbolMapping{}}`.
  """
  def batch_symbol_mappings(isins) when is_list(isins) do
    SymbolMapping
    |> where([m], m.isin in ^isins and m.status == "resolved")
    |> Repo.all()
    |> Map.new(fn m -> {m.isin, m} end)
  end

  @doc """
  Loads all historical prices for multiple symbols in a date range in a single query.

  Returns `%{symbol => %{date => close_price}}`.
  """
  def batch_historical_prices(symbols, from_date, to_date) when is_list(symbols) do
    HistoricalPrice
    |> where([p], p.symbol in ^symbols and p.date >= ^from_date and p.date <= ^to_date)
    |> select([p], {p.symbol, p.date, p.close})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {symbol, rows} ->
      date_map = Map.new(rows, fn {_sym, date, close} -> {date, close} end)
      {symbol, date_map}
    end)
  end

  @doc """
  Pure in-memory close price lookup with 5-day fallback.

  Same logic as `get_close_price/2` but reads from pre-loaded price map.
  """
  def batch_get_close_price(price_map, symbol, date) do
    symbol_prices = Map.get(price_map, symbol, %{})

    # Try exact date, then walk back up to 5 days
    Enum.find_value(0..5, fn offset ->
      lookup_date = Date.add(date, -offset)

      case Map.get(symbol_prices, lookup_date) do
        nil -> nil
        close when not is_nil(close) -> {:ok, close}
      end
    end) || {:error, :no_price}
  end

  ## Symbol Mappings (CRUD)

  @doc """
  Gets a symbol mapping by ISIN.
  """
  def get_symbol_mapping(isin) do
    Repo.get_by(SymbolMapping, isin: isin)
  end

  @doc """
  Creates or updates a symbol mapping.
  """
  def upsert_symbol_mapping(attrs) do
    isin = attrs[:isin] || attrs["isin"]

    case get_symbol_mapping(isin) do
      nil ->
        %SymbolMapping{}
        |> SymbolMapping.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> SymbolMapping.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Lists all symbol mappings.
  """
  def list_symbol_mappings do
    SymbolMapping
    |> order_by([m], asc: m.isin)
    |> Repo.all()
  end

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

  ## Company Notes

  @doc """
  Gets a company note by ISIN.
  """
  def get_company_note_by_isin(isin) when is_binary(isin) do
    Repo.get_by(CompanyNote, isin: isin)
  end

  @doc """
  Gets an existing company note or returns an unsaved struct with defaults.
  """
  def get_or_init_company_note(isin, defaults \\ %{}) do
    case get_company_note_by_isin(isin) do
      nil -> struct(CompanyNote, Map.merge(%{isin: isin}, defaults))
      note -> note
    end
  end

  @doc """
  Creates or updates a company note by ISIN.
  """
  def upsert_company_note(attrs) do
    isin = attrs[:isin] || attrs["isin"]

    case get_company_note_by_isin(isin) do
      nil ->
        %CompanyNote{}
        |> CompanyNote.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> CompanyNote.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Lists all company notes with watchlist=true.
  """
  def list_watchlist do
    CompanyNote
    |> where([n], n.watchlist == true)
    |> order_by([n], asc: n.symbol)
    |> Repo.all()
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
