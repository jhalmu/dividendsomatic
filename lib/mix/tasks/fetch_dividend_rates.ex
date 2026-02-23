defmodule Mix.Tasks.Fetch.DividendRates do
  @moduledoc """
  Fetch declared dividend rates from Yahoo Finance for instruments.

  Uses the Yahoo Finance quoteSummary API (summaryDetail module) to get
  forward dividend rate, yield, ex-dividend date, and payout ratio.

  Usage:
    mix fetch.dividend_rates              # All instruments with resolved symbols
    mix fetch.dividend_rates --active     # Only current position ISINs
    mix fetch.dividend_rates --dry-run    # Preview what would be fetched
    mix fetch.dividend_rates ISIN         # Fetch for a specific ISIN
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.MarketData.Providers.YahooFinance
  alias Dividendsomatic.Portfolio.{Instrument, PortfolioSnapshot, Position}
  alias Dividendsomatic.Repo
  alias Dividendsomatic.Stocks.SymbolMapper
  alias Dividendsomatic.Stocks.YahooFinance, as: YF

  @shortdoc "Fetch dividend rates from Yahoo Finance"
  @rate_limit_ms 500

  # ISINs where Yahoo Finance returns incorrect dividend data.
  # These are skipped during fetch and should use manual or TTM-computed rates.
  @yahoo_isin_blacklist MapSet.new([
                          "SE0000667925",
                          "US8964423086"
                        ])

  def run(args) do
    Mix.Task.run("app.start")

    if "--dry-run" in args do
      dry_run(args)
    else
      fetch(args)
    end
  end

  defp fetch(args) do
    instruments = target_instruments(args)
    IO.puts("--- Fetching Dividend Rates (#{length(instruments)} instruments) ---\n")

    {fetched, skipped, failed} =
      Enum.reduce(instruments, {0, 0, 0}, fn entry, acc ->
        fetch_one(entry, acc)
      end)

    IO.puts("\n--- Summary ---")
    IO.puts("  Fetched: #{fetched}")
    IO.puts("  Skipped: #{skipped}")
    IO.puts("  Failed:  #{failed}")
  end

  defp fetch_one({isin, yahoo_symbol, name}, {f, s, fl}) do
    IO.write("  #{yahoo_symbol} (#{name || isin})...")

    if MapSet.member?(@yahoo_isin_blacklist, isin) do
      IO.puts(" BLACKLISTED — skipping (use mix backfill.dividend_rates for manual/TTM)")
      {f, s + 1, fl}
    else
      fetch_one_yahoo({isin, yahoo_symbol}, {f, s, fl})
    end
  end

  defp fetch_one_yahoo({isin, yahoo_symbol}, {f, s, fl}) do
    Process.sleep(@rate_limit_ms)

    case fetch_and_update(isin, yahoo_symbol) do
      {:ok, data} ->
        IO.puts(" rate=#{data.dividend_rate || "nil"} freq=#{data.dividend_frequency || "?"}")
        {f + 1, s, fl}

      {:skip, reason} ->
        IO.puts(" #{inspect(reason)}")
        {f, s + 1, fl}

      {:fail, reason} ->
        IO.puts(" UPDATE FAILED: #{inspect(reason)}")
        {f, s, fl + 1}
    end
  end

  defp fetch_and_update(isin, yahoo_symbol) do
    case YahooFinance.fetch_dividend_info(yahoo_symbol) do
      {:ok, data} ->
        case update_instrument(isin, data) do
          {:ok, _} -> {:ok, data}
          {:skip, reason} -> {:skip, reason}
          {:error, reason} -> {:fail, reason}
        end

      {:error, reason} ->
        {:skip, reason}
    end
  end

  defp dry_run(args) do
    instruments = target_instruments(args)
    IO.puts("--- Dry Run: Dividend Rate Fetch (#{length(instruments)} instruments) ---\n")

    Enum.each(instruments, fn {isin, yahoo_symbol, name} ->
      instrument = Repo.get_by(Instrument, isin: isin)
      existing = if instrument, do: instrument.dividend_rate, else: nil
      IO.puts("  #{yahoo_symbol} (#{name || isin}) [current: #{existing || "nil"}]")
    end)

    IO.puts("\nEstimated time: ~#{div(length(instruments) * @rate_limit_ms, 1_000) + 1}s")
  end

  defp target_instruments(args) do
    clean_args = Enum.reject(args, &String.starts_with?(&1, "--"))

    cond do
      clean_args != [] ->
        # Specific ISIN
        isin = hd(clean_args)
        resolve_isin(isin)

      "--active" in args ->
        active_position_instruments()

      true ->
        all_resolved_instruments()
    end
  end

  defp resolve_isin(isin) do
    case SymbolMapper.resolve(isin) do
      {:ok, finnhub_symbol} ->
        yahoo_symbol = YF.to_yahoo_symbol(finnhub_symbol)
        instrument = Repo.get_by(Instrument, isin: isin)
        name = if instrument, do: instrument.name, else: nil
        [{isin, yahoo_symbol, name}]

      _ ->
        IO.puts("Cannot resolve ISIN #{isin} to a symbol")
        []
    end
  end

  defp active_position_instruments do
    latest_snapshot =
      PortfolioSnapshot
      |> order_by([s], desc: s.date)
      |> limit(1)
      |> Repo.one()

    case latest_snapshot do
      nil ->
        IO.puts("No snapshots found")
        []

      snapshot ->
        Position
        |> where([p], p.portfolio_snapshot_id == ^snapshot.id)
        |> where([p], not is_nil(p.isin))
        |> select([p], {p.isin, p.symbol})
        |> Repo.all()
        |> Enum.uniq_by(fn {isin, _} -> isin end)
        |> Enum.flat_map(&resolve_position_isin/1)
    end
  end

  defp resolve_position_isin({isin, _symbol}) do
    case SymbolMapper.resolve(isin) do
      {:ok, finnhub_symbol} ->
        yahoo_symbol = YF.to_yahoo_symbol(finnhub_symbol)
        instrument = Repo.get_by(Instrument, isin: isin)
        name = if instrument, do: instrument.name, else: nil
        [{isin, yahoo_symbol, name}]

      _ ->
        []
    end
  end

  defp all_resolved_instruments do
    SymbolMapper.list_resolved()
    |> Enum.map(fn mapping ->
      yahoo_symbol = YF.to_yahoo_symbol(mapping.finnhub_symbol)
      instrument = Repo.get_by(Instrument, isin: mapping.isin)
      name = if instrument, do: instrument.name, else: nil
      {mapping.isin, yahoo_symbol, name}
    end)
  end

  defp update_instrument(isin, data) do
    case Repo.get_by(Instrument, isin: isin) do
      nil ->
        {:error, :instrument_not_found}

      instrument ->
        if instrument.dividend_source in ["manual", "ttm_computed"] do
          {:skip, :protected_source}
        else
          attrs =
            %{
              dividend_rate: data.dividend_rate,
              dividend_yield: data.dividend_yield,
              dividend_frequency: data.dividend_frequency,
              ex_dividend_date: data.ex_dividend_date,
              payout_ratio: data.payout_ratio,
              dividend_source: "yahoo",
              dividend_updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
            }

          instrument
          |> Instrument.changeset(attrs)
          |> Repo.update()
        end
    end
  end
end
