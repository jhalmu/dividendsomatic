defmodule Dividendsomatic.Stocks do
  @moduledoc """
  Stock data context — public facade for quotes, profiles, metrics, and prices.

  All external market data flows through the MarketData Dispatcher, which
  selects providers based on configuration. This context handles caching
  (DB read/write) and Decimal conversion.

  ## Configuration

  Provider chains are configured in `config :dividendsomatic, :market_data`.
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Repo

  alias Dividendsomatic.MarketData.Dispatcher

  alias Dividendsomatic.Stocks.{
    CompanyNote,
    CompanyProfile,
    HistoricalPrice,
    StockMetric,
    StockQuote,
    SymbolMapping
  }

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
    case Dispatcher.dispatch_for(:get_quote, [symbol], :quote) do
      {:ok, data} -> upsert_quote(symbol, data)
      {:error, _} = error -> error
    end
  end

  defp fetch_and_cache_profile(symbol) do
    case Dispatcher.dispatch_for(:get_company_profile, [symbol], :profile) do
      {:ok, data} -> upsert_profile(symbol, data)
      {:error, _} = error -> error
    end
  end

  defp fetch_and_cache_metrics(symbol) do
    case Dispatcher.dispatch_for(:get_financial_metrics, [symbol], :metrics) do
      {:ok, data} -> upsert_metrics(symbol, data)
      {:error, _} = error -> error
    end
  end

  defp upsert_quote(symbol, data) do
    attrs = %{
      symbol: symbol,
      current_price: to_decimal(data[:current_price]),
      change: to_decimal(data[:change]),
      percent_change: to_decimal(data[:percent_change]),
      high: to_decimal(data[:high]),
      low: to_decimal(data[:low]),
      open: to_decimal(data[:open]),
      previous_close: to_decimal(data[:previous_close]),
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

  defp upsert_profile(symbol, data) do
    attrs = %{
      symbol: symbol,
      name: data[:name],
      country: data[:country],
      currency: data[:currency],
      exchange: data[:exchange],
      ipo_date: parse_date(data[:ipo_date]),
      market_cap: to_decimal(data[:market_cap]),
      sector: data[:sector],
      industry: data[:industry],
      logo_url: data[:logo_url],
      web_url: data[:web_url],
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

  defp upsert_metrics(symbol, data) do
    attrs = %{
      symbol: symbol,
      pe_ratio: to_decimal(data[:pe_ratio]),
      pb_ratio: to_decimal(data[:pb_ratio]),
      eps: to_decimal(data[:eps]),
      roe: to_decimal(data[:roe]),
      roa: to_decimal(data[:roa]),
      net_margin: to_decimal(data[:net_margin]),
      operating_margin: to_decimal(data[:operating_margin]),
      debt_to_equity: to_decimal(data[:debt_to_equity]),
      current_ratio: to_decimal(data[:current_ratio]),
      fcf_margin: to_decimal(data[:fcf_margin]),
      beta: to_decimal(data[:beta]),
      payout_ratio: to_decimal(data[:payout_ratio]),
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

  ## Historical Prices

  @doc """
  Fetches daily candle data for a stock symbol via the provider chain.

  Returns `{:ok, count}` with number of records inserted, or `{:error, reason}`.
  """
  def fetch_historical_candles(symbol, from_date, to_date, opts \\ []) do
    isin = Keyword.get(opts, :isin)

    case Dispatcher.dispatch_for(:get_candles, [symbol, from_date, to_date, []], :candles) do
      {:ok, records} -> insert_provider_records(symbol, isin, records)
      {:error, _} = error -> error
    end
  end

  @doc """
  Fetches daily forex candle data via the provider chain.

  Pair format: "OANDA:EUR_USD". Returns `{:ok, count}`.
  """
  def fetch_forex_candles(pair, from_date, to_date) do
    case Dispatcher.dispatch_for(:get_forex_candles, [pair, from_date, to_date], :forex) do
      {:ok, records} -> insert_provider_records(pair, nil, records)
      {:error, _} = error -> error
    end
  end

  ## Yahoo Finance Historical Data (direct provider calls for mix tasks)

  @doc """
  Fetches daily candle data from Yahoo Finance for a stock symbol.

  Returns `{:ok, count}` with number of records inserted, or `{:error, reason}`.
  """
  def fetch_yahoo_candles(symbol, from_date, to_date, opts \\ []) do
    isin = Keyword.get(opts, :isin)

    case Dividendsomatic.MarketData.Providers.YahooFinance.get_candles(
           symbol,
           from_date,
           to_date,
           []
         ) do
      {:ok, records} -> insert_provider_records(symbol, isin, records)
      {:error, _} = error -> error
    end
  end

  @doc """
  Fetches daily forex candle data from Yahoo Finance.

  Pair format: "OANDA:EUR_USD" (converted internally).
  Returns `{:ok, count}`.
  """
  def fetch_yahoo_forex(oanda_pair, from_date, to_date) do
    case Dividendsomatic.MarketData.Providers.YahooFinance.get_forex_candles(
           oanda_pair,
           from_date,
           to_date
         ) do
      {:ok, records} -> insert_provider_records(oanda_pair, nil, records)
      {:error, _} = error -> error
    end
  end

  defp insert_provider_records(symbol, isin, records) do
    count =
      Enum.reduce(records, 0, fn record, acc ->
        attrs = %{
          symbol: symbol,
          isin: isin,
          date: record.date,
          open: to_decimal(record.open),
          high: to_decimal(record.high),
          low: to_decimal(record.low),
          close: to_decimal(record.close),
          volume: record.volume,
          source: "provider"
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

  ## ISIN Lookup

  @doc """
  Looks up a stock's symbol by ISIN via the provider chain.

  Returns `{:ok, %{symbol: "TICKER", exchange: "HEX", currency: "EUR"}}` or `{:error, reason}`.
  """
  def lookup_symbol_by_isin(isin) do
    Dispatcher.dispatch_for(:lookup_symbol_by_isin, [isin], :isin_lookup)
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

  ## Helpers

  defp to_decimal(nil), do: nil
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(value) when is_number(value), do: Decimal.new("#{value}")
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)

  defp parse_date(nil), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
