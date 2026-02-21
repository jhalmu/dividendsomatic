defmodule Mix.Tasks.Fetch.HistoricalPrices do
  @moduledoc """
  Fetch historical prices for portfolio reconstruction.

  Uses Yahoo Finance (free, no API key) for OHLCV candle data and forex rates.
  Falls back to Finnhub if `--finnhub` flag is passed (requires paid plan).

  Usage:
    mix fetch.historical_prices              # Full pipeline (Yahoo Finance)
    mix fetch.historical_prices --resolve    # Only resolve ISIN→symbol mappings
    mix fetch.historical_prices --dry-run    # Preview what would be fetched
    mix fetch.historical_prices --finnhub    # Use Finnhub instead of Yahoo
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{Instrument, Trade}
  alias Dividendsomatic.Repo
  alias Dividendsomatic.Stocks
  alias Dividendsomatic.Stocks.SymbolMapper

  @shortdoc "Fetch historical prices (Yahoo Finance)"

  # Yahoo Finance is more lenient, but be polite
  @rate_limit_ms 500

  # Forex pairs needed for EUR conversion
  @forex_pairs [
    {"OANDA:EUR_USD", "USD"},
    {"OANDA:EUR_SEK", "SEK"},
    {"OANDA:EUR_NOK", "NOK"},
    {"OANDA:EUR_GBP", "GBP"},
    {"OANDA:EUR_JPY", "JPY"},
    {"OANDA:EUR_HKD", "HKD"},
    {"OANDA:EUR_CAD", "CAD"},
    {"OANDA:EUR_CHF", "CHF"},
    {"OANDA:EUR_DKK", "DKK"}
  ]

  def run(args) do
    Mix.Task.run("app.start")

    cond do
      "--resolve" in args -> resolve_only()
      "--dry-run" in args -> dry_run()
      true -> full_pipeline(args)
    end
  end

  defp resolve_only do
    IO.puts("--- Resolving ISIN → symbol mappings ---\n")
    IO.puts("Step 1: Local resolution (cache + holdings + known ISINs)...")
    {resolved, unmappable, pending} = SymbolMapper.resolve_all()
    IO.puts("  Resolved: #{resolved}, Unmappable: #{unmappable}, Pending: #{pending}\n")

    if pending > 0 do
      IO.puts("Step 2: Finnhub ISIN lookup for #{pending} pending symbols...")

      IO.puts(
        "  (rate-limited: ~1 request/sec, estimated #{div(pending * 1100, 60_000) + 1} min)\n"
      )

      {new_resolved, new_unmappable, still_pending} = SymbolMapper.resolve_pending()

      IO.puts("\n--- Resolution Summary ---")
      IO.puts("  Previously resolved: #{resolved}")
      IO.puts("  Newly resolved: #{new_resolved}")
      IO.puts("  Newly unmappable: #{new_unmappable}")
      IO.puts("  Still pending: #{still_pending}")
      IO.puts("  Total resolved: #{resolved + new_resolved}")
    else
      IO.puts("No pending symbols to look up.")
    end
  end

  defp dry_run do
    IO.puts("--- Dry Run: Historical Price Fetch Plan ---\n")

    {resolved, unmappable, pending} = SymbolMapper.resolve_all()

    IO.puts(
      "Symbol resolution: #{resolved} resolved, #{unmappable} unmappable, #{pending} pending\n"
    )

    mappings = SymbolMapper.list_resolved()
    date_ranges = build_date_ranges()

    IO.puts("Stocks to fetch (#{length(mappings)}):")

    Enum.each(mappings, fn mapping ->
      range = Map.get(date_ranges, mapping.isin)

      if range do
        existing = Stocks.count_historical_prices(mapping.finnhub_symbol)

        IO.puts(
          "  #{mapping.finnhub_symbol} (#{mapping.isin}) #{range.first_date}..#{range.last_date} [#{existing} existing]"
        )
      end
    end)

    currencies = currencies_in_use()
    needed_fx = Enum.filter(@forex_pairs, fn {_pair, currency} -> currency in currencies end)

    IO.puts("\nForex pairs to fetch (#{length(needed_fx)}):")
    Enum.each(needed_fx, fn {pair, currency} -> IO.puts("  #{pair} (#{currency})") end)

    total_calls = length(mappings) + length(needed_fx)
    rate_ms = @rate_limit_ms

    IO.puts(
      "\nEstimated API calls: #{total_calls} (~#{div(total_calls * rate_ms, 60_000) + 1} min)"
    )
  end

  defp full_pipeline(args) do
    use_finnhub = "--finnhub" in args
    source = if use_finnhub, do: "Finnhub", else: "Yahoo Finance"
    IO.puts("--- Historical Price Fetch Pipeline (#{source}) ---\n")

    # Step 1: Resolve symbols
    IO.puts("Step 1: Resolving ISIN → symbols...")
    {resolved, unmappable, pending} = SymbolMapper.resolve_all()
    IO.puts("  #{resolved} resolved, #{unmappable} unmappable, #{pending} pending\n")

    # Step 2: Fetch stock candles
    mappings = SymbolMapper.list_resolved()
    date_ranges = build_date_ranges()

    IO.puts("Step 2: Fetching stock candles (#{length(mappings)} symbols)...")

    stock_results =
      Enum.reduce(mappings, {0, 0}, fn mapping, acc ->
        fetch_stock_candle(mapping, date_ranges, acc, use_finnhub)
      end)

    IO.puts(
      "  Stock candles: #{elem(stock_results, 0)} succeeded, #{elem(stock_results, 1)} failed\n"
    )

    # Step 3: Fetch forex rates
    currencies = currencies_in_use()
    needed_fx = Enum.filter(@forex_pairs, fn {_pair, currency} -> currency in currencies end)
    {global_from, global_to} = global_date_range()

    IO.puts("Step 3: Fetching forex rates (#{length(needed_fx)} pairs)...")

    if global_from do
      Enum.each(needed_fx, &fetch_forex_pair(&1, global_from, global_to, use_finnhub))
    else
      IO.puts("  No date range found, skipping forex")
    end

    IO.puts("\n--- Done ---")
  end

  defp fetch_forex_pair({pair, currency}, global_from, global_to, use_finnhub) do
    IO.write("  #{pair} (#{currency})...")
    Process.sleep(@rate_limit_ms)

    result =
      if use_finnhub do
        Stocks.fetch_forex_candles(pair, global_from, global_to)
      else
        Stocks.fetch_yahoo_forex(pair, global_from, global_to)
      end

    case result do
      {:ok, count} -> IO.puts(" #{count} records")
      {:error, reason} -> IO.puts(" ERROR: #{inspect(reason)}")
    end
  end

  defp fetch_stock_candle(mapping, date_ranges, {success, fail}, use_finnhub) do
    case Map.get(date_ranges, mapping.isin) do
      nil ->
        {success, fail}

      range ->
        IO.write("  #{mapping.finnhub_symbol}...")
        Process.sleep(@rate_limit_ms)

        result =
          if use_finnhub do
            Stocks.fetch_historical_candles(
              mapping.finnhub_symbol,
              range.first_date,
              range.last_date,
              isin: mapping.isin
            )
          else
            Stocks.fetch_yahoo_candles(
              mapping.finnhub_symbol,
              range.first_date,
              range.last_date,
              isin: mapping.isin
            )
          end

        case result do
          {:ok, count} ->
            IO.puts(" #{count} records")
            {success + 1, fail}

          {:error, reason} ->
            IO.puts(" ERROR: #{inspect(reason)}")
            {success, fail + 1}
        end
    end
  end

  # Build a map of ISIN → %{first_date, last_date} from trades
  defp build_date_ranges do
    Trade
    |> join(:inner, [t], i in Instrument, on: t.instrument_id == i.id)
    |> where([t, i], not is_nil(i.isin))
    |> group_by([t, i], i.isin)
    |> select([t, i], {i.isin, %{first_date: min(t.trade_date), last_date: max(t.trade_date)}})
    |> Repo.all()
    |> Map.new()
  end

  # Get the global date range across all trades
  defp global_date_range do
    result =
      Trade
      |> select([t], %{min_date: min(t.trade_date), max_date: max(t.trade_date)})
      |> Repo.one()

    {result.min_date, result.max_date}
  end

  # Get distinct currencies used in trades
  defp currencies_in_use do
    Trade
    |> where([t], not is_nil(t.currency))
    |> distinct(true)
    |> select([t], t.currency)
    |> Repo.all()
    |> Enum.reject(&(&1 == "EUR"))
  end
end
