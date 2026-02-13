# Multi-Provider Market Data Architecture

**Issue:** #22
**Date:** 2026-02-13
**Status:** Approved

## Goal

Extract hardcoded Finnhub HTTP calls from `stocks.ex` into a provider-based architecture with configurable fallback chains. Add EODHD as a second provider. Keep Stocks context as the public API facade.

## Behaviour Contract

```elixir
defmodule Dividendsomatic.MarketData.Provider do
  @type quote_result :: {:ok, map()} | {:error, term()}
  @type candles_result :: {:ok, [map()]} | {:error, term()}
  @type profile_result :: {:ok, map()} | {:error, term()}
  @type metrics_result :: {:ok, map()} | {:error, term()}

  @callback get_quote(symbol :: String.t()) :: quote_result()
  @callback get_candles(symbol :: String.t(), from :: Date.t(), to :: Date.t(), opts :: keyword()) :: candles_result()
  @callback get_forex_candles(pair :: String.t(), from :: Date.t(), to :: Date.t()) :: candles_result()
  @callback get_company_profile(symbol :: String.t()) :: profile_result()
  @callback get_financial_metrics(symbol :: String.t()) :: metrics_result()
  @callback lookup_symbol_by_isin(isin :: String.t()) :: {:ok, map()} | {:error, term()}

  @optional_callbacks [get_financial_metrics: 1, lookup_symbol_by_isin: 1, get_forex_candles: 3]
end
```

Providers that don't support a callback return `{:error, :not_supported}`. The dispatcher skips these automatically.

## Module Layout

```
lib/dividendsomatic/market_data/
  provider.ex              # Behaviour definition
  dispatcher.ex            # Fallback chain logic
  providers/
    finnhub.ex             # Extracted from stocks.ex
    yahoo_finance.ex       # Migrated from stocks/yahoo_finance.ex
    eodhd.ex               # New implementation
```

## Dispatcher

Tries providers in configured order for each data type. Stops on first success.

```elixir
defmodule Dividendsomatic.MarketData.Dispatcher do
  def dispatch(callback, args, data_type) do
    providers = providers_for(data_type)
    try_providers(providers, callback, args)
  end

  defp try_providers([], _callback, _args), do: {:error, :all_providers_failed}
  defp try_providers([provider | rest], callback, args) do
    case apply(provider, callback, args) do
      {:ok, _} = success -> success
      {:error, :not_supported} -> try_providers(rest, callback, args)
      {:error, _reason} -> try_providers(rest, callback, args)
    end
  end

  defp providers_for(data_type) do
    config = Application.get_env(:dividendsomatic, :market_data, %{})
    Map.get(config[:providers] || %{}, data_type, [])
  end
end
```

## Configuration

```elixir
# config/config.exs
config :dividendsomatic, :market_data,
  providers: %{
    quote:       [MarketData.Providers.Finnhub, MarketData.Providers.Eodhd],
    candles:     [MarketData.Providers.YahooFinance, MarketData.Providers.Eodhd, MarketData.Providers.Finnhub],
    forex:       [MarketData.Providers.YahooFinance, MarketData.Providers.Eodhd],
    profile:     [MarketData.Providers.Finnhub, MarketData.Providers.Eodhd],
    metrics:     [MarketData.Providers.Finnhub],
    isin_lookup: [MarketData.Providers.Finnhub]
  }
```

## Stocks Context Changes

`stocks.ex` remains the public facade. Functions that currently make direct Finnhub HTTP calls are replaced with `Dispatcher.dispatch/3` calls. Caching logic, batch operations, schema CRUD, and all public function signatures stay unchanged.

Before:
```elixir
# Direct Finnhub HTTP in stocks.ex
defp fetch_quote_from_api(symbol) do
  url = "#{@finnhub_base}/quote?symbol=#{symbol}&token=#{api_key()}"
  Req.get(url) |> handle_response()
end
```

After:
```elixir
defp fetch_quote_from_api(symbol) do
  Dispatcher.dispatch(:get_quote, [symbol], :quote)
end
```

## Provider Implementations

### Finnhub (extracted from stocks.ex)

Endpoints:
- `/quote` — real-time quotes
- `/stock/profile2` — company profiles
- `/stock/metric` — financial metrics (P/E, ROE, etc.)
- `/stock/candle` — daily OHLCV
- `/forex/candle` — forex pairs
- `/stock/profile2?isin=` — ISIN lookup

All existing Finnhub HTTP logic moves here unchanged. API key from `FINNHUB_API_KEY` env var.

### Yahoo Finance (migrated from stocks/yahoo_finance.ex)

Endpoints:
- `/v8/finance/chart` — daily OHLCV + forex

Existing `YahooFinance` module wrapped to implement the Provider behaviour. Symbol conversion logic (`to_yahoo_symbol/1`, `forex_to_yahoo/1`) stays in the module.

Supports: `get_candles`, `get_forex_candles`. Returns `{:error, :not_supported}` for quotes, profiles, metrics, isin_lookup.

### EODHD (new)

Endpoints:
- `/real-time/{symbol}` — real-time quotes
- `/eod/{symbol}` — end-of-day OHLCV (30+ years)
- `/eod/{pair}.FOREX` — forex pairs
- `/fundamentals/{symbol}` — company profile + fundamentals
- `/div/{symbol}` — dividend history (future use)

API key from `EODHD_API_KEY` env var. Symbol format: `{TICKER}.{EXCHANGE}` (e.g., `AAPL.US`, `NOKIA.HE`).

Supports: `get_quote`, `get_candles`, `get_forex_candles`, `get_company_profile`. Returns `{:error, :not_supported}` for metrics, isin_lookup.

## Testing Strategy

- Each provider: unit tests with Req test adapters (plug-based mocks, no Mox needed)
- Dispatcher: tests with in-line test modules implementing the behaviour
- Stocks context: existing integration tests remain, now hitting dispatcher
- Config: test environment uses specific provider lists to ensure deterministic behavior

## Decisions

- **ISIN stays primary identifier** — no change to the identifier strategy
- **No rate limiting in dispatcher** — providers handle their own rate limits
- **No automatic retry** — dispatcher moves to next provider on failure, doesn't retry same provider
- **Stocks context unchanged externally** — zero breaking changes for LiveView/portfolio callers
