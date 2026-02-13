# Multi-Provider Market Data Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract Finnhub HTTP calls from `stocks.ex` into a behaviour-based provider architecture with fallback chains. Add EODHD as a second real provider.

**Architecture:** `MarketData.Provider` behaviour defines 6 callbacks. Three adapters implement it (Finnhub, YahooFinance, EODHD). A `Dispatcher` tries providers in configured order per data type. `Stocks` context stays as the public facade — zero breaking changes for callers.

**Tech Stack:** Elixir behaviours, Req HTTP client, ExUnit with Req test adapters

**Design doc:** `docs/plans/2026-02-13-multi-provider-market-data-design.md`

---

### Task 1: Provider Behaviour

**Files:**
- Create: `lib/dividendsomatic/market_data/provider.ex`
- Test: `test/dividendsomatic/market_data/provider_test.exs`

**Step 1: Write the failing test**

```elixir
# test/dividendsomatic/market_data/provider_test.exs
defmodule Dividendsomatic.MarketData.ProviderTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketData.Provider

  # Define a test module that implements all required callbacks
  defmodule FullProvider do
    @behaviour Provider

    @impl true
    def get_quote(_symbol), do: {:ok, %{price: 100}}

    @impl true
    def get_candles(_symbol, _from, _to, _opts), do: {:ok, []}

    @impl true
    def get_company_profile(_symbol), do: {:ok, %{name: "Test"}}
  end

  # Define a partial provider (only required callbacks)
  defmodule PartialProvider do
    @behaviour Provider

    @impl true
    def get_quote(_symbol), do: {:ok, %{price: 50}}

    @impl true
    def get_candles(_symbol, _from, _to, _opts), do: {:ok, []}

    @impl true
    def get_company_profile(_symbol), do: {:ok, %{}}
  end

  describe "behaviour contract" do
    test "should compile full provider implementing all callbacks" do
      assert {:ok, %{price: 100}} = FullProvider.get_quote("AAPL")
      assert {:ok, []} = FullProvider.get_candles("AAPL", ~D[2025-01-01], ~D[2025-12-31], [])
      assert {:ok, %{name: "Test"}} = FullProvider.get_company_profile("AAPL")
    end

    test "should compile partial provider with only required callbacks" do
      assert {:ok, %{price: 50}} = PartialProvider.get_quote("AAPL")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/dividendsomatic/market_data/provider_test.exs --trace`
Expected: Compilation error — `Provider` module not found

**Step 3: Write the behaviour module**

```elixir
# lib/dividendsomatic/market_data/provider.ex
defmodule Dividendsomatic.MarketData.Provider do
  @moduledoc """
  Behaviour for market data providers.

  Required callbacks: get_quote, get_candles, get_company_profile.
  Optional callbacks: get_forex_candles, get_financial_metrics, lookup_symbol_by_isin.

  Providers that don't support an optional callback should not implement it.
  The dispatcher will skip providers that raise `UndefinedFunctionError`.
  """

  @type quote_result :: {:ok, map()} | {:error, term()}
  @type candles_result :: {:ok, [map()]} | {:error, term()}
  @type profile_result :: {:ok, map()} | {:error, term()}
  @type metrics_result :: {:ok, map()} | {:error, term()}

  @callback get_quote(symbol :: String.t()) :: quote_result()
  @callback get_candles(symbol :: String.t(), from :: Date.t(), to :: Date.t(), opts :: keyword()) ::
              candles_result()
  @callback get_forex_candles(pair :: String.t(), from :: Date.t(), to :: Date.t()) ::
              candles_result()
  @callback get_company_profile(symbol :: String.t()) :: profile_result()
  @callback get_financial_metrics(symbol :: String.t()) :: metrics_result()
  @callback lookup_symbol_by_isin(isin :: String.t()) :: {:ok, map()} | {:error, term()}

  @optional_callbacks get_forex_candles: 3, get_financial_metrics: 1, lookup_symbol_by_isin: 1
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/dividendsomatic/market_data/provider_test.exs --trace`
Expected: 2 tests, 0 failures

**Step 5: Commit**

```bash
git add lib/dividendsomatic/market_data/provider.ex test/dividendsomatic/market_data/provider_test.exs
git commit -m "feat: Add MarketData.Provider behaviour (#22)

- 6 callbacks: get_quote, get_candles, get_forex_candles, get_company_profile, get_financial_metrics, lookup_symbol_by_isin
- 3 optional callbacks for providers with partial coverage"
```

---

### Task 2: Dispatcher

**Files:**
- Create: `lib/dividendsomatic/market_data/dispatcher.ex`
- Test: `test/dividendsomatic/market_data/dispatcher_test.exs`

**Step 1: Write the failing test**

```elixir
# test/dividendsomatic/market_data/dispatcher_test.exs
defmodule Dividendsomatic.MarketData.DispatcherTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketData.Dispatcher

  # Test providers
  defmodule SuccessProvider do
    @behaviour Dividendsomatic.MarketData.Provider

    @impl true
    def get_quote(_symbol), do: {:ok, %{source: :success, price: 150}}
    @impl true
    def get_candles(_s, _f, _t, _o), do: {:ok, [%{close: 150}]}
    @impl true
    def get_company_profile(_s), do: {:ok, %{name: "Success Corp"}}
  end

  defmodule FailProvider do
    @behaviour Dividendsomatic.MarketData.Provider

    @impl true
    def get_quote(_symbol), do: {:error, :api_error}
    @impl true
    def get_candles(_s, _f, _t, _o), do: {:error, :api_error}
    @impl true
    def get_company_profile(_s), do: {:error, :api_error}
  end

  defmodule PartialProvider do
    @behaviour Dividendsomatic.MarketData.Provider

    @impl true
    def get_quote(_symbol), do: {:error, :not_supported}
    @impl true
    def get_candles(_s, _f, _t, _o), do: {:ok, [%{close: 200}]}
    @impl true
    def get_company_profile(_s), do: {:error, :not_supported}
  end

  describe "dispatch/3" do
    test "should return first successful provider result" do
      providers = [SuccessProvider]
      assert {:ok, %{source: :success}} = Dispatcher.dispatch(:get_quote, ["AAPL"], providers)
    end

    test "should skip failing providers and use next" do
      providers = [FailProvider, SuccessProvider]
      assert {:ok, %{source: :success}} = Dispatcher.dispatch(:get_quote, ["AAPL"], providers)
    end

    test "should skip not_supported and use next" do
      providers = [PartialProvider, SuccessProvider]
      assert {:ok, %{source: :success}} = Dispatcher.dispatch(:get_quote, ["AAPL"], providers)
    end

    test "should return all_providers_failed when all fail" do
      providers = [FailProvider]
      assert {:error, :all_providers_failed} = Dispatcher.dispatch(:get_quote, ["AAPL"], providers)
    end

    test "should return all_providers_failed for empty provider list" do
      assert {:error, :all_providers_failed} = Dispatcher.dispatch(:get_quote, ["AAPL"], [])
    end

    test "should pass multiple args correctly" do
      providers = [SuccessProvider]

      assert {:ok, [%{close: 150}]} =
               Dispatcher.dispatch(:get_candles, ["AAPL", ~D[2025-01-01], ~D[2025-12-31], []], providers)
    end
  end

  describe "dispatch_for/3 (config-based)" do
    setup do
      # Temporarily set config for test
      original = Application.get_env(:dividendsomatic, :market_data)

      Application.put_env(:dividendsomatic, :market_data,
        providers: %{
          quote: [FailProvider, SuccessProvider],
          candles: [PartialProvider]
        }
      )

      on_exit(fn ->
        if original, do: Application.put_env(:dividendsomatic, :market_data, original),
        else: Application.delete_env(:dividendsomatic, :market_data)
      end)

      :ok
    end

    test "should use config-based provider chain" do
      assert {:ok, %{source: :success}} = Dispatcher.dispatch_for(:get_quote, ["AAPL"], :quote)
    end

    test "should return all_providers_failed for unconfigured data type" do
      assert {:error, :all_providers_failed} = Dispatcher.dispatch_for(:get_quote, ["AAPL"], :unknown)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/dividendsomatic/market_data/dispatcher_test.exs --trace`
Expected: Compilation error — `Dispatcher` module not found

**Step 3: Write the dispatcher**

```elixir
# lib/dividendsomatic/market_data/dispatcher.ex
defmodule Dividendsomatic.MarketData.Dispatcher do
  @moduledoc """
  Dispatches market data requests through a provider fallback chain.

  Tries each provider in order. Stops on first `{:ok, _}` result.
  Skips providers returning `{:error, :not_supported}` or any other error.
  """

  require Logger

  @doc """
  Dispatches a callback to an explicit list of providers.
  """
  def dispatch(callback, args, providers) when is_list(providers) do
    try_providers(providers, callback, args)
  end

  @doc """
  Dispatches using the configured provider chain for the given data type.

  Reads provider list from `config :dividendsomatic, :market_data, providers: %{data_type => [modules]}`.
  """
  def dispatch_for(callback, args, data_type) do
    providers = providers_for(data_type)
    try_providers(providers, callback, args)
  end

  defp try_providers([], _callback, _args), do: {:error, :all_providers_failed}

  defp try_providers([provider | rest], callback, args) do
    case apply(provider, callback, args) do
      {:ok, _} = success ->
        success

      {:error, :not_supported} ->
        try_providers(rest, callback, args)

      {:error, reason} ->
        Logger.debug("Provider #{inspect(provider)} failed for #{callback}: #{inspect(reason)}")
        try_providers(rest, callback, args)
    end
  end

  defp providers_for(data_type) do
    :dividendsomatic
    |> Application.get_env(:market_data, [])
    |> Keyword.get(:providers, %{})
    |> Map.get(data_type, [])
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/dividendsomatic/market_data/dispatcher_test.exs --trace`
Expected: 7 tests, 0 failures

**Step 5: Commit**

```bash
git add lib/dividendsomatic/market_data/dispatcher.ex test/dividendsomatic/market_data/dispatcher_test.exs
git commit -m "feat: Add MarketData.Dispatcher with fallback chains (#22)

- dispatch/3 for explicit provider lists
- dispatch_for/3 for config-based provider chains
- Skips :not_supported and errors, stops on first success"
```

---

### Task 3: Finnhub Provider (extract from stocks.ex)

**Files:**
- Create: `lib/dividendsomatic/market_data/providers/finnhub.ex`
- Test: `test/dividendsomatic/market_data/providers/finnhub_test.exs`

**Step 1: Write the failing test**

```elixir
# test/dividendsomatic/market_data/providers/finnhub_test.exs
defmodule Dividendsomatic.MarketData.Providers.FinnhubTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketData.Providers.Finnhub

  describe "get_quote/1" do
    test "should return quote data on success" do
      Req.Test.stub(Finnhub, fn conn ->
        assert conn.params["symbol"] == "AAPL"
        assert conn.params["token"] == "test_key"

        Req.Test.json(conn, %{
          "c" => 150.0,
          "d" => 2.5,
          "dp" => 1.69,
          "h" => 152.0,
          "l" => 148.0,
          "o" => 149.0,
          "pc" => 147.5
        })
      end)

      assert {:ok, quote_data} = Finnhub.get_quote("AAPL", api_key: "test_key")
      assert quote_data.current_price == 150.0
      assert quote_data.change == 2.5
      assert quote_data.percent_change == 1.69
      assert quote_data.high == 152.0
      assert quote_data.low == 148.0
      assert quote_data.open == 149.0
      assert quote_data.previous_close == 147.5
    end

    test "should return error when no data" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{"c" => 0, "d" => nil, "dp" => nil, "h" => 0, "l" => 0, "o" => 0, "pc" => 0})
      end)

      assert {:error, :no_data} = Finnhub.get_quote("INVALID", api_key: "test_key")
    end

    test "should return rate_limited on 429" do
      Req.Test.stub(Finnhub, fn conn ->
        Plug.Conn.send_resp(conn, 429, "Rate limited")
      end)

      assert {:error, :rate_limited} = Finnhub.get_quote("AAPL", api_key: "test_key")
    end

    test "should return not_configured without API key" do
      assert {:error, :not_configured} = Finnhub.get_quote("AAPL")
    end
  end

  describe "get_candles/4" do
    test "should return candle records on success" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{
          "s" => "ok",
          "t" => [1_704_067_200, 1_704_153_600],
          "o" => [100.0, 101.0],
          "h" => [105.0, 106.0],
          "l" => [99.0, 100.0],
          "c" => [104.0, 105.0],
          "v" => [1_000_000, 1_100_000]
        })
      end)

      assert {:ok, records} =
               Finnhub.get_candles("AAPL", ~D[2024-01-01], ~D[2024-01-02], api_key: "test_key")

      assert length(records) == 2
      assert hd(records).close == 104.0
      assert hd(records).volume == 1_000_000
    end

    test "should return empty list for no_data" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{"s" => "no_data"})
      end)

      assert {:ok, []} =
               Finnhub.get_candles("AAPL", ~D[2024-01-01], ~D[2024-01-02], api_key: "test_key")
    end
  end

  describe "get_company_profile/1" do
    test "should return profile data on success" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{
          "name" => "Apple Inc.",
          "country" => "US",
          "currency" => "USD",
          "exchange" => "NASDAQ",
          "finnhubIndustry" => "Technology",
          "ipo" => "1980-12-12",
          "logo" => "https://example.com/logo.png",
          "weburl" => "https://apple.com",
          "marketCapitalization" => 3_000_000
        })
      end)

      assert {:ok, profile} = Finnhub.get_company_profile("AAPL", api_key: "test_key")
      assert profile.name == "Apple Inc."
      assert profile.country == "US"
      assert profile.exchange == "NASDAQ"
    end
  end

  describe "get_financial_metrics/1" do
    test "should return metrics data on success" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{
          "metric" => %{
            "peBasicExclExtraTTM" => 28.5,
            "pbQuarterly" => 45.2,
            "epsBasicExclExtraItemsTTM" => 6.42,
            "roeRfy" => 147.25,
            "beta" => 1.24
          }
        })
      end)

      assert {:ok, metrics} = Finnhub.get_financial_metrics("AAPL", api_key: "test_key")
      assert metrics.pe_ratio == 28.5
      assert metrics.beta == 1.24
    end
  end

  describe "lookup_symbol_by_isin/1" do
    test "should return symbol data on success" do
      Req.Test.stub(Finnhub, fn conn ->
        assert conn.params["isin"] == "US0378331005"

        Req.Test.json(conn, %{
          "ticker" => "AAPL",
          "exchange" => "NASDAQ",
          "currency" => "USD",
          "name" => "Apple Inc."
        })
      end)

      assert {:ok, result} = Finnhub.lookup_symbol_by_isin("US0378331005", api_key: "test_key")
      assert result.symbol == "AAPL"
      assert result.exchange == "NASDAQ"
    end

    test "should return not_found for unknown ISIN" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{})
      end)

      assert {:error, :not_found} = Finnhub.lookup_symbol_by_isin("XX0000000000", api_key: "test_key")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/dividendsomatic/market_data/providers/finnhub_test.exs --trace`
Expected: Compilation error — `Finnhub` provider module not found

**Step 3: Write the Finnhub provider**

Extract all Finnhub HTTP logic from `stocks.ex` into this module. Each function accepts an optional `api_key:` option (for testing) and falls back to `Application.get_env`.

```elixir
# lib/dividendsomatic/market_data/providers/finnhub.ex
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

  @impl true
  def get_quote(symbol, opts \\ []) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      request("/quote", [symbol: symbol, token: api_key])
      |> handle_quote_response()
    end
  end

  @impl true
  def get_candles(symbol, from_date, to_date, opts \\ []) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      params = [
        symbol: symbol,
        resolution: "D",
        from: date_to_unix(from_date),
        to: date_to_unix(to_date),
        token: api_key
      ]

      request("/stock/candle", params)
      |> handle_candles_response()
    end
  end

  @impl true
  def get_forex_candles(pair, from_date, to_date, opts \\ []) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      params = [
        symbol: pair,
        resolution: "D",
        from: date_to_unix(from_date),
        to: date_to_unix(to_date),
        token: api_key
      ]

      request("/forex/candle", params)
      |> handle_candles_response()
    end
  end

  @impl true
  def get_company_profile(symbol, opts \\ []) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      request("/stock/profile2", [symbol: symbol, token: api_key])
      |> handle_profile_response()
    end
  end

  @impl true
  def get_financial_metrics(symbol, opts \\ []) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      request("/stock/metric", [symbol: symbol, metric: "all", token: api_key])
      |> handle_metrics_response()
    end
  end

  @impl true
  def lookup_symbol_by_isin(isin, opts \\ []) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      request("/stock/profile2", [isin: isin, token: api_key])
      |> handle_isin_response()
    end
  end

  # HTTP request helper
  defp request(path, params) do
    Req.get("#{@base_url}#{path}",
      params: params,
      plug: {Req.Test, Dividendsomatic.MarketData.Providers.Finnhub}
    )
  end

  # Response handlers
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
  defp handle_quote_response({:ok, %{status: status}}), do: log_error("quote", status)
  defp handle_quote_response({:error, reason}), do: {:error, reason}

  defp handle_candles_response({:ok, %{status: 200, body: %{"s" => "ok"} = body}}) do
    records = parse_candle_body(body)
    {:ok, records}
  end

  defp handle_candles_response({:ok, %{status: 200, body: %{"s" => "no_data"}}}), do: {:ok, []}
  defp handle_candles_response({:ok, %{status: 429}}), do: {:error, :rate_limited}
  defp handle_candles_response({:ok, %{status: 403}}), do: {:error, :access_denied}
  defp handle_candles_response({:ok, %{status: status}}), do: log_error("candles", status)
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
  defp handle_profile_response({:ok, %{status: status}}), do: log_error("profile", status)
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
  defp handle_metrics_response({:ok, %{status: status}}), do: log_error("metrics", status)
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
  defp handle_isin_response({:ok, %{status: status}}), do: log_error("isin_lookup", status)
  defp handle_isin_response({:error, reason}), do: {:error, reason}

  # Helpers
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
    date |> Date.to_iso8601() |> then(&(&1 <> "T00:00:00Z")) |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_unix()
  end

  defp unix_to_date(ts), do: ts |> DateTime.from_unix!() |> DateTime.to_date()

  defp log_error(endpoint, status) do
    Logger.error("Finnhub #{endpoint} failed: HTTP #{status}")
    {:error, :api_error}
  end
end
```

**NOTE on Req.Test:** The `plug: {Req.Test, ...}` option is only active when a stub is registered. In production with no stub, Req makes real HTTP requests. This is the standard Req testing pattern — see [Req.Test docs](https://hexdocs.pm/req/Req.Test.html). If the project doesn't use this pattern yet, you may need to conditionally include the plug option only in test, or configure it via application config. Check how Req is used in existing tests first. If the project uses a different test strategy, adapt accordingly — the key requirement is that tests don't make real HTTP calls.

**Step 4: Run test to verify it passes**

Run: `mix test test/dividendsomatic/market_data/providers/finnhub_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/dividendsomatic/market_data/providers/finnhub.ex test/dividendsomatic/market_data/providers/finnhub_test.exs
git commit -m "feat: Extract Finnhub provider from stocks.ex (#22)

- All 6 callbacks implemented: quote, candles, forex, profile, metrics, isin
- Raw map returns (no Decimal conversion — Stocks context handles that)
- Req.Test stubs for unit testing"
```

---

### Task 4: Yahoo Finance Provider (wrap existing module)

**Files:**
- Create: `lib/dividendsomatic/market_data/providers/yahoo_finance.ex`
- Test: `test/dividendsomatic/market_data/providers/yahoo_finance_test.exs`
- Keep: `lib/dividendsomatic/stocks/yahoo_finance.ex` (still used for symbol conversion helpers)

**Step 1: Write the failing test**

```elixir
# test/dividendsomatic/market_data/providers/yahoo_finance_test.exs
defmodule Dividendsomatic.MarketData.Providers.YahooFinanceTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketData.Providers.YahooFinance

  describe "get_quote/1" do
    test "should return not_supported" do
      assert {:error, :not_supported} = YahooFinance.get_quote("AAPL")
    end
  end

  describe "get_company_profile/1" do
    test "should return not_supported" do
      assert {:error, :not_supported} = YahooFinance.get_company_profile("AAPL")
    end
  end

  describe "get_candles/4" do
    test "should return candle data on success" do
      Req.Test.stub(YahooFinance, fn conn ->
        Req.Test.json(conn, %{
          "chart" => %{
            "result" => [
              %{
                "timestamp" => [1_704_067_200, 1_704_153_600],
                "indicators" => %{
                  "quote" => [
                    %{
                      "open" => [100.0, 101.0],
                      "high" => [105.0, 106.0],
                      "low" => [99.0, 100.0],
                      "close" => [104.0, 105.0],
                      "volume" => [1_000_000, 1_100_000]
                    }
                  ]
                }
              }
            ]
          }
        })
      end)

      assert {:ok, records} = YahooFinance.get_candles("AAPL", ~D[2024-01-01], ~D[2024-01-02], [])
      assert length(records) == 2
      assert hd(records).close == 104.0
    end
  end

  describe "get_forex_candles/3" do
    test "should convert OANDA pair and fetch" do
      Req.Test.stub(YahooFinance, fn conn ->
        # Verify the symbol was converted to Yahoo format
        assert String.contains?(conn.request_path, "EURUSD")

        Req.Test.json(conn, %{
          "chart" => %{
            "result" => [
              %{
                "timestamp" => [1_704_067_200],
                "indicators" => %{
                  "quote" => [%{"open" => [1.1], "high" => [1.2], "low" => [1.0], "close" => [1.15], "volume" => [0]}]
                }
              }
            ]
          }
        })
      end)

      assert {:ok, [record]} = YahooFinance.get_forex_candles("OANDA:EUR_USD", ~D[2024-01-01], ~D[2024-01-02])
      assert record.close == 1.15
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/dividendsomatic/market_data/providers/yahoo_finance_test.exs --trace`
Expected: Compilation error

**Step 3: Write the Yahoo Finance provider**

This wraps the existing `Dividendsomatic.Stocks.YahooFinance` module, delegating to it but implementing the Provider behaviour interface.

```elixir
# lib/dividendsomatic/market_data/providers/yahoo_finance.ex
defmodule Dividendsomatic.MarketData.Providers.YahooFinance do
  @moduledoc """
  Yahoo Finance market data provider.

  Wraps the existing YahooFinance module to implement the Provider behaviour.
  Supports historical candles and forex only — no quotes, profiles, or metrics.
  """

  @behaviour Dividendsomatic.MarketData.Provider

  alias Dividendsomatic.Stocks.YahooFinance, as: YF

  @base_url "https://query1.finance.yahoo.com/v8/finance/chart"
  @headers [{"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}]

  @impl true
  def get_quote(_symbol), do: {:error, :not_supported}

  @impl true
  def get_company_profile(_symbol), do: {:error, :not_supported}

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

    url = "#{@base_url}/#{URI.encode(yahoo_symbol)}"

    case Req.get(url,
           params: [period1: from_ts, period2: to_ts, interval: "1d"],
           headers: @headers,
           plug: {Req.Test, __MODULE__}
         ) do
      {:ok, %{status: 200, body: body}} ->
        parse_chart_response(body)

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: _status}} ->
        {:error, :api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

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
    date |> Date.to_iso8601() |> then(&(&1 <> "T00:00:00Z")) |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_unix()
  end

  defp unix_to_date(ts), do: ts |> DateTime.from_unix!() |> DateTime.to_date()
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/dividendsomatic/market_data/providers/yahoo_finance_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/dividendsomatic/market_data/providers/yahoo_finance.ex test/dividendsomatic/market_data/providers/yahoo_finance_test.exs
git commit -m "feat: Add Yahoo Finance provider adapter (#22)

- Wraps existing YahooFinance module with Provider behaviour
- Supports get_candles and get_forex_candles
- Returns :not_supported for quotes, profiles, metrics"
```

---

### Task 5: EODHD Provider (new)

**Files:**
- Create: `lib/dividendsomatic/market_data/providers/eodhd.ex`
- Test: `test/dividendsomatic/market_data/providers/eodhd_test.exs`

**Step 1: Write the failing test**

```elixir
# test/dividendsomatic/market_data/providers/eodhd_test.exs
defmodule Dividendsomatic.MarketData.Providers.EodhdTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketData.Providers.Eodhd

  describe "get_quote/1" do
    test "should return quote data on success" do
      Req.Test.stub(Eodhd, fn conn ->
        Req.Test.json(conn, %{
          "code" => "AAPL.US",
          "timestamp" => 1_711_670_340,
          "open" => 170.0,
          "high" => 172.0,
          "low" => 169.0,
          "close" => 171.5,
          "volume" => 50_000_000,
          "previousClose" => 170.0,
          "change" => 1.5,
          "change_p" => 0.88
        })
      end)

      assert {:ok, quote_data} = Eodhd.get_quote("AAPL.US", api_key: "test_key")
      assert quote_data.current_price == 171.5
      assert quote_data.change == 1.5
      assert quote_data.percent_change == 0.88
      assert quote_data.previous_close == 170.0
    end

    test "should return not_configured without API key" do
      assert {:error, :not_configured} = Eodhd.get_quote("AAPL.US")
    end
  end

  describe "get_candles/4" do
    test "should return candle records on success" do
      Req.Test.stub(Eodhd, fn conn ->
        Req.Test.json(conn, [
          %{"date" => "2024-01-01", "open" => 100.0, "high" => 105.0, "low" => 99.0, "close" => 104.0, "adjusted_close" => 104.0, "volume" => 1_000_000},
          %{"date" => "2024-01-02", "open" => 104.0, "high" => 106.0, "low" => 103.0, "close" => 105.5, "adjusted_close" => 105.5, "volume" => 1_100_000}
        ])
      end)

      assert {:ok, records} = Eodhd.get_candles("AAPL.US", ~D[2024-01-01], ~D[2024-01-02], api_key: "test_key")
      assert length(records) == 2
      assert hd(records).date == ~D[2024-01-01]
      assert hd(records).close == 104.0
    end

    test "should return empty list for empty response" do
      Req.Test.stub(Eodhd, fn conn ->
        Req.Test.json(conn, [])
      end)

      assert {:ok, []} = Eodhd.get_candles("AAPL.US", ~D[2024-01-01], ~D[2024-01-02], api_key: "test_key")
    end
  end

  describe "get_forex_candles/3" do
    test "should convert OANDA pair to EODHD format" do
      Req.Test.stub(Eodhd, fn conn ->
        # Verify the path contains the correct forex symbol
        assert String.contains?(conn.request_path, "EURUSD.FOREX")

        Req.Test.json(conn, [
          %{"date" => "2024-01-01", "open" => 1.1, "high" => 1.12, "low" => 1.09, "close" => 1.11, "adjusted_close" => 1.11, "volume" => 0}
        ])
      end)

      assert {:ok, [record]} = Eodhd.get_forex_candles("OANDA:EUR_USD", ~D[2024-01-01], ~D[2024-01-01], api_key: "test_key")
      assert record.close == 1.11
    end
  end

  describe "get_company_profile/1" do
    test "should return profile data from fundamentals endpoint" do
      Req.Test.stub(Eodhd, fn conn ->
        Req.Test.json(conn, %{
          "General" => %{
            "Code" => "AAPL",
            "Name" => "Apple Inc.",
            "CountryName" => "USA",
            "CurrencyCode" => "USD",
            "Exchange" => "NASDAQ",
            "Sector" => "Technology",
            "Industry" => "Consumer Electronics",
            "WebURL" => "https://apple.com",
            "LogoURL" => "https://eodhd.com/img/logos/US/AAPL.png",
            "ISIN" => "US0378331005",
            "IPODate" => "1980-12-12"
          },
          "Highlights" => %{
            "MarketCapitalization" => 3_000_000_000_000
          }
        })
      end)

      assert {:ok, profile} = Eodhd.get_company_profile("AAPL.US", api_key: "test_key")
      assert profile.name == "Apple Inc."
      assert profile.country == "USA"
      assert profile.sector == "Technology"
      assert profile.industry == "Consumer Electronics"
    end
  end

  describe "symbol_to_eodhd/1" do
    test "should map Finnhub suffixes to EODHD exchange codes" do
      assert Eodhd.symbol_to_eodhd("NOKIA.HE") == "NOKIA.HE"
      assert Eodhd.symbol_to_eodhd("TELIA1.ST") == "TELIA1.ST"
      assert Eodhd.symbol_to_eodhd("AAPL") == "AAPL.US"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/dividendsomatic/market_data/providers/eodhd_test.exs --trace`
Expected: Compilation error

**Step 3: Write the EODHD provider**

```elixir
# lib/dividendsomatic/market_data/providers/eodhd.ex
defmodule Dividendsomatic.MarketData.Providers.Eodhd do
  @moduledoc """
  EODHD market data provider.

  Implements the Provider behaviour for quotes, historical candles, forex, and
  company profiles via EODHD's REST API.

  API key from EODHD_API_KEY env var. Symbol format: TICKER.EXCHANGE (e.g. AAPL.US, NOKIA.HE).
  """

  @behaviour Dividendsomatic.MarketData.Provider

  require Logger

  @base_url "https://eodhd.com/api"

  @impl true
  def get_quote(symbol, opts \\ []) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      eodhd_symbol = symbol_to_eodhd(symbol)

      request("/real-time/#{eodhd_symbol}", api_token: api_key, fmt: "json")
      |> handle_quote_response()
    end
  end

  @impl true
  def get_candles(symbol, from_date, to_date, opts \\ []) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      eodhd_symbol = symbol_to_eodhd(symbol)

      request("/eod/#{eodhd_symbol}",
        api_token: api_key,
        fmt: "json",
        period: "d",
        from: Date.to_iso8601(from_date),
        to: Date.to_iso8601(to_date)
      )
      |> handle_candles_response()
    end
  end

  @impl true
  def get_forex_candles(pair, from_date, to_date, opts \\ []) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      eodhd_pair = oanda_to_eodhd(pair)

      request("/eod/#{eodhd_pair}",
        api_token: api_key,
        fmt: "json",
        period: "d",
        from: Date.to_iso8601(from_date),
        to: Date.to_iso8601(to_date)
      )
      |> handle_candles_response()
    end
  end

  @impl true
  def get_company_profile(symbol, opts \\ []) do
    with {:ok, api_key} <- resolve_api_key(opts) do
      eodhd_symbol = symbol_to_eodhd(symbol)

      request("/fundamentals/#{eodhd_symbol}",
        api_token: api_key,
        fmt: "json",
        filter: "General,Highlights"
      )
      |> handle_profile_response()
    end
  end

  # Symbol conversion

  @doc """
  Converts a Finnhub-style symbol to EODHD format.

  EODHD uses the same exchange suffixes as Finnhub for Nordic markets.
  US stocks without a suffix get `.US` appended.
  """
  def symbol_to_eodhd(symbol) do
    if String.contains?(symbol, ".") do
      symbol
    else
      "#{symbol}.US"
    end
  end

  @doc false
  def oanda_to_eodhd(oanda_pair) do
    case Regex.run(~r/OANDA:(\w+)_(\w+)/, oanda_pair) do
      [_, base, quote_currency] -> "#{base}#{quote_currency}.FOREX"
      _ -> oanda_pair
    end
  end

  # HTTP
  defp request(path, params) do
    Req.get("#{@base_url}#{path}",
      params: params,
      plug: {Req.Test, __MODULE__}
    )
  end

  # Response handlers
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

  defp resolve_api_key(opts) do
    case Keyword.get(opts, :api_key) || Application.get_env(:dividendsomatic, :eodhd_api_key) do
      nil -> {:error, :not_configured}
      key -> {:ok, key}
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/dividendsomatic/market_data/providers/eodhd_test.exs --trace`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/dividendsomatic/market_data/providers/eodhd.ex test/dividendsomatic/market_data/providers/eodhd_test.exs
git commit -m "feat: Add EODHD provider adapter (#22)

- Quotes via /real-time, candles via /eod, profile via /fundamentals
- Forex via /eod with .FOREX suffix
- Finnhub symbol format compatible (same exchange suffixes for Nordic)
- US stocks without suffix get .US appended"
```

---

### Task 6: Configuration + EODHD API Key

**Files:**
- Modify: `config/config.exs`
- Modify: `config/runtime.exs`
- Modify: `config/test.exs`

**Step 1: Add market_data provider config to `config/config.exs`**

Add after the Oban config block (before the `import_config` line):

```elixir
# Multi-provider market data configuration
config :dividendsomatic, :market_data,
  providers: %{
    quote: [
      Dividendsomatic.MarketData.Providers.Finnhub,
      Dividendsomatic.MarketData.Providers.Eodhd
    ],
    candles: [
      Dividendsomatic.MarketData.Providers.YahooFinance,
      Dividendsomatic.MarketData.Providers.Eodhd,
      Dividendsomatic.MarketData.Providers.Finnhub
    ],
    forex: [
      Dividendsomatic.MarketData.Providers.YahooFinance,
      Dividendsomatic.MarketData.Providers.Eodhd
    ],
    profile: [
      Dividendsomatic.MarketData.Providers.Finnhub,
      Dividendsomatic.MarketData.Providers.Eodhd
    ],
    metrics: [
      Dividendsomatic.MarketData.Providers.Finnhub
    ],
    isin_lookup: [
      Dividendsomatic.MarketData.Providers.Finnhub
    ]
  }
```

**Step 2: Add EODHD API key to `config/runtime.exs`**

Add after the Finnhub config block:

```elixir
# EODHD API configuration for historical data and fundamentals
# All World Extended plan: $20/month
if eodhd_api_key = System.get_env("EODHD_API_KEY") do
  config :dividendsomatic, eodhd_api_key: eodhd_api_key
end
```

**Step 3: Override providers in test config `config/test.exs`**

Add to `config/test.exs` (so tests don't accidentally hit real APIs via dispatcher):

```elixir
# Disable market data providers in test — tests use Req.Test stubs directly
config :dividendsomatic, :market_data,
  providers: %{}
```

**Step 4: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles cleanly

**Step 5: Run full test suite**

Run: `mix test`
Expected: All existing tests still pass

**Step 6: Commit**

```bash
git add config/config.exs config/runtime.exs config/test.exs
git commit -m "chore: Add market data provider configuration (#22)

- Provider fallback chains in config.exs
- EODHD_API_KEY env var in runtime.exs
- Empty providers in test.exs to prevent accidental API calls"
```

---

### Task 7: Rewire Stocks Context to Use Dispatcher

**Files:**
- Modify: `lib/dividendsomatic/stocks.ex`
- Test: Existing `test/dividendsomatic/stocks_test.exs` (should still pass)

This is the critical integration step. Replace all direct Finnhub HTTP calls in `stocks.ex` with `Dispatcher.dispatch_for/3` calls. The Stocks context keeps its caching, Decimal conversion, and DB operations.

**Step 1: Modify `stocks.ex`**

Changes required:
1. Remove `@finnhub_base_url` module attribute
2. Add `alias Dividendsomatic.MarketData.Dispatcher`
3. Replace `fetch_quote_from_api/2` to use dispatcher
4. Replace `fetch_profile_from_api/2` to use dispatcher
5. Replace `fetch_metrics_from_api/2` to use dispatcher
6. Replace `fetch_historical_candles/4` to use dispatcher
7. Replace `fetch_forex_candles/3` to use dispatcher
8. Replace `lookup_symbol_by_isin/1` to use dispatcher
9. Keep `fetch_yahoo_candles/4` and `fetch_yahoo_forex/3` (these write to DB, so they call the Yahoo provider directly — or better, route through dispatcher for candles)
10. Remove `get_api_key/0` private function (providers handle their own keys)
11. Keep `parse_decimal/1`, `parse_date/1`, `parse_market_cap/1` helpers (used for DB upserts)

**Key pattern change — fetch_and_cache_quote becomes:**

```elixir
defp fetch_and_cache_quote(symbol) do
  case Dispatcher.dispatch_for(:get_quote, [symbol], :quote) do
    {:ok, data} -> upsert_quote(symbol, data)
    {:error, _} = error -> error
  end
end
```

**And upsert_quote changes to accept a normalized map (not raw API response):**

```elixir
defp upsert_quote(symbol, data) do
  attrs = %{
    symbol: symbol,
    current_price: to_decimal(data.current_price || data[:current_price]),
    change: to_decimal(data.change || data[:change]),
    percent_change: to_decimal(data.percent_change || data[:percent_change]),
    high: to_decimal(data.high || data[:high]),
    low: to_decimal(data.low || data[:low]),
    open: to_decimal(data.open || data[:open]),
    previous_close: to_decimal(data.previous_close || data[:previous_close]),
    fetched_at: DateTime.utc_now()
  }
  # ... rest of upsert unchanged
end

defp to_decimal(nil), do: nil
defp to_decimal(%Decimal{} = d), do: d
defp to_decimal(value) when is_number(value), do: Decimal.new("#{value}")
defp to_decimal(value) when is_binary(value), do: Decimal.new(value)
```

**Same pattern for profiles, metrics. For candles, the dispatcher returns raw records, and stocks.ex inserts them:**

```elixir
def fetch_historical_candles(symbol, from_date, to_date, opts \\ []) do
  isin = Keyword.get(opts, :isin)

  case Dispatcher.dispatch_for(:get_candles, [symbol, from_date, to_date, []], :candles) do
    {:ok, records} -> insert_candle_records(symbol, isin, "provider", records)
    {:error, _} = error -> error
  end
end
```

**Step 2: Run existing tests**

Run: `mix test test/dividendsomatic/stocks_test.exs --trace`
Expected: All existing tests still pass (they test caching/DB behavior, not API calls)

**Step 3: Run full test suite**

Run: `mix test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add lib/dividendsomatic/stocks.ex
git commit -m "refactor: Rewire Stocks context to use MarketData dispatcher (#22)

- Replace direct Finnhub HTTP calls with Dispatcher.dispatch_for/3
- Providers return raw maps, Stocks handles Decimal conversion + DB upsert
- All public API signatures unchanged — zero breaking changes
- Remove @finnhub_base_url and get_api_key/0 from stocks.ex"
```

---

### Task 8: Integration Test + Cleanup

**Files:**
- Create: `test/dividendsomatic/market_data/integration_test.exs`
- Verify: All existing tests pass

**Step 1: Write integration test that exercises the full dispatcher chain**

```elixir
# test/dividendsomatic/market_data/integration_test.exs
defmodule Dividendsomatic.MarketData.IntegrationTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketData.Dispatcher

  defmodule AlwaysFails do
    @behaviour Dividendsomatic.MarketData.Provider
    @impl true
    def get_quote(_), do: {:error, :down}
    @impl true
    def get_candles(_, _, _, _), do: {:error, :down}
    @impl true
    def get_company_profile(_), do: {:error, :down}
  end

  defmodule Fallback do
    @behaviour Dividendsomatic.MarketData.Provider
    @impl true
    def get_quote(_), do: {:ok, %{current_price: 99.99, source: :fallback}}
    @impl true
    def get_candles(_, _, _, _), do: {:ok, [%{close: 99.99}]}
    @impl true
    def get_company_profile(_), do: {:ok, %{name: "Fallback Corp"}}
  end

  describe "fallback chain integration" do
    test "should fall through to working provider" do
      chain = [AlwaysFails, Fallback]
      assert {:ok, %{source: :fallback}} = Dispatcher.dispatch(:get_quote, ["TEST"], chain)
    end

    test "should report all_providers_failed when entire chain fails" do
      chain = [AlwaysFails]
      assert {:error, :all_providers_failed} = Dispatcher.dispatch(:get_quote, ["TEST"], chain)
    end
  end
end
```

**Step 2: Run full test suite**

Run: `mix test --trace`
Expected: All tests pass (existing + new)

**Step 3: Run code quality checks**

Run: `mix format && mix credo`
Expected: No issues

**Step 4: Commit**

```bash
git add test/dividendsomatic/market_data/integration_test.exs
git commit -m "test: Add market data integration tests (#22)

- Fallback chain integration test
- Verifies dispatcher correctly cascades through providers"
```

---

### Task 9: Final Verification + Cleanup

**Step 1: Run full quality suite**

Run: `mix test.all`
Expected: All tests pass, 0 credo issues

**Step 2: Verify the server starts**

Run: `mix phx.server` (manual check at localhost:4000)
Expected: Portfolio page loads, quotes display (if FINNHUB_API_KEY is set)

**Step 3: Update MEMO.md**

Add to current status section noting the multi-provider architecture is complete.

**Step 4: Final commit**

```bash
git add MEMO.md
git commit -m "docs: Update MEMO.md with multi-provider architecture (#22)"
```

**Step 5: Close the issue**

```bash
gh issue close 22 --comment "Multi-provider market data architecture implemented. Finnhub extracted, Yahoo Finance wrapped, EODHD added. Dispatcher with configurable fallback chains. Stocks context unchanged externally."
```

---

## Summary

| Task | What | New Files | Tests |
|------|------|-----------|-------|
| 1 | Provider behaviour | 1 | 2 |
| 2 | Dispatcher | 1 | 7 |
| 3 | Finnhub provider | 1 | ~8 |
| 4 | Yahoo Finance provider | 1 | ~4 |
| 5 | EODHD provider | 1 | ~6 |
| 6 | Configuration | 0 (modify 3) | 0 |
| 7 | Rewire stocks.ex | 0 (modify 1) | 0 (existing pass) |
| 8 | Integration tests | 1 | 2 |
| 9 | Verification + cleanup | 0 | 0 |

**Total: 6 new files, 4 modified files, ~29 new tests**
