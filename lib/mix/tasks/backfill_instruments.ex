defmodule Mix.Tasks.Backfill.Instruments do
  @moduledoc """
  Backfill missing instrument data (currency, company info, symbol).

  ## Usage

      mix backfill.instruments           # Run all backfills
      mix backfill.instruments --currency # Only backfill currency
      mix backfill.instruments --company  # Only backfill company data
      mix backfill.instruments --symbol   # Only backfill canonical symbol
  """

  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{DividendPayment, Instrument, InstrumentAlias, Position, Trade}
  alias Dividendsomatic.Repo

  require Logger

  @shortdoc "Backfill missing instrument data"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Logger.configure(level: :info)

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [currency: :boolean, company: :boolean, symbol: :boolean]
      )

    run_all = !opts[:currency] && !opts[:company] && !opts[:symbol]

    if run_all || opts[:symbol], do: backfill_symbol()
    if run_all || opts[:currency], do: backfill_currency()
    if run_all || opts[:company], do: backfill_company_data()

    null_currency =
      Repo.one(from(i in Instrument, where: is_nil(i.currency), select: count(i.id)))

    null_symbol =
      Repo.one(from(i in Instrument, where: is_nil(i.symbol), select: count(i.id)))

    Mix.shell().info("\nRemaining instruments with NULL currency: #{null_currency}")
    Mix.shell().info("Remaining instruments with NULL symbol: #{null_symbol}")
  end

  # --- Symbol Backfill ---

  defp backfill_symbol do
    Mix.shell().info("=== Backfilling instrument symbol ===\n")

    null_before =
      Repo.one(from(i in Instrument, where: is_nil(i.symbol), select: count(i.id)))

    Mix.shell().info("Instruments with NULL symbol: #{null_before}")

    # Step 1: From positions (most authoritative — IBKR-supplied)
    from_positions = backfill_symbol_from_positions()
    Mix.shell().info("  From positions: #{from_positions} updated")

    # Step 2: From instrument_aliases (prefer finnhub source, then most recent)
    from_aliases = backfill_symbol_from_aliases()
    Mix.shell().info("  From aliases: #{from_aliases} updated")

    # Step 3: From instrument name (last resort — short all-caps names)
    from_name = backfill_symbol_from_name()
    Mix.shell().info("  From name: #{from_name} updated")

    total = from_positions + from_aliases + from_name
    Mix.shell().info("\nTotal symbol updates: #{total}")
  end

  defp backfill_symbol_from_positions do
    null_ids =
      Repo.all(from(i in Instrument, where: is_nil(i.symbol), select: {i.id, i.isin}))

    if null_ids == [] do
      0
    else
      isin_to_id =
        Map.new(null_ids, fn {id, isin} -> {isin, id} end)

      # For each ISIN, find the most recent position symbol
      symbol_map =
        from(p in Position,
          where: p.isin in ^Map.keys(isin_to_id),
          where: not is_nil(p.symbol),
          distinct: p.isin,
          order_by: [desc: p.date],
          select: {p.isin, p.symbol}
        )
        |> Repo.all()
        |> Map.new(fn {isin, symbol} -> {Map.get(isin_to_id, isin), symbol} end)
        |> Enum.reject(fn {id, _} -> is_nil(id) end)
        |> Map.new()

      update_symbols(symbol_map)
    end
  end

  defp backfill_symbol_from_aliases do
    null_ids =
      Repo.all(from(i in Instrument, where: is_nil(i.symbol), select: i.id))

    if null_ids == [] do
      0
    else
      # Prefer finnhub source, then ibkr, then most recent
      aliases =
        from(a in InstrumentAlias,
          where: a.instrument_id in ^null_ids,
          order_by: [
            asc:
              fragment(
                "CASE WHEN ? = 'finnhub' THEN 0 WHEN ? = 'ibkr' THEN 1 ELSE 2 END",
                a.source,
                a.source
              ),
            desc: a.inserted_at
          ],
          select: {a.instrument_id, a.symbol}
        )
        |> Repo.all()

      # Take the first (best) symbol per instrument
      symbol_map =
        aliases
        |> Enum.reduce(%{}, fn {instrument_id, symbol}, acc ->
          Map.put_new(acc, instrument_id, symbol)
        end)

      update_symbols(symbol_map)
    end
  end

  defp backfill_symbol_from_name do
    null_instruments =
      Repo.all(
        from(i in Instrument,
          where: is_nil(i.symbol) and not is_nil(i.name),
          select: {i.id, i.name}
        )
      )

    symbol_map =
      null_instruments
      |> Enum.reduce(%{}, fn {id, name}, acc ->
        # Only use name if it looks like a ticker: all-caps, 1-6 chars, letters only
        trimmed = String.trim(name)

        if trimmed =~ ~r/^[A-Z]{1,6}$/ do
          Map.put(acc, id, trimmed)
        else
          acc
        end
      end)

    update_symbols(symbol_map)
  end

  defp update_symbols(symbol_map) when map_size(symbol_map) == 0, do: 0

  defp update_symbols(symbol_map) do
    Enum.reduce(symbol_map, 0, fn {instrument_id, symbol}, count ->
      {updated, _} =
        Instrument
        |> where([i], i.id == ^instrument_id and is_nil(i.symbol))
        |> Repo.update_all(set: [symbol: symbol, updated_at: DateTime.utc_now()])

      count + updated
    end)
  end

  # --- Currency Backfill ---

  defp backfill_currency do
    Mix.shell().info("=== Backfilling instrument currency ===\n")

    null_before =
      Repo.one(from(i in Instrument, where: is_nil(i.currency), select: count(i.id)))

    Mix.shell().info("Instruments with NULL currency: #{null_before}")

    # Step 1: Derive from trades (dominant currency per instrument)
    from_trades = backfill_currency_from_trades()
    Mix.shell().info("  From trades: #{from_trades} updated")

    # Step 2: Derive from dividend_payments
    from_dividends = backfill_currency_from_dividends()
    Mix.shell().info("  From dividends: #{from_dividends} updated")

    # Step 3: Derive from Flex portfolio CSVs
    from_flex = backfill_currency_from_flex_csvs()
    Mix.shell().info("  From Flex CSVs: #{from_flex} updated")

    # Step 4: Derive from Activity Statement CSVs (corporate actions, WHT rows)
    from_activity = backfill_currency_from_activity_csvs()
    Mix.shell().info("  From Activity CSVs: #{from_activity} updated")

    # Step 5: Infer from ISIN country prefix / exchange
    from_inferred = backfill_currency_inferred()
    Mix.shell().info("  From ISIN/exchange inference: #{from_inferred} updated")

    total = from_trades + from_dividends + from_flex + from_activity + from_inferred
    Mix.shell().info("\nTotal currency updates: #{total}")
  end

  defp backfill_currency_from_trades do
    # For each instrument with NULL currency, find the most common currency in trades
    null_ids =
      Repo.all(from(i in Instrument, where: is_nil(i.currency), select: i.id))

    if null_ids == [] do
      0
    else
      # Get dominant currency per instrument from trades
      currency_map =
        Trade
        |> where([t], t.instrument_id in ^null_ids)
        |> group_by([t], [t.instrument_id, t.currency])
        |> select([t], {t.instrument_id, t.currency, count(t.id)})
        |> Repo.all()
        |> Enum.group_by(&elem(&1, 0))
        |> Map.new(fn {instrument_id, entries} ->
          # Pick currency with most trades
          {_, dominant_currency, _} = Enum.max_by(entries, &elem(&1, 2))
          {instrument_id, dominant_currency}
        end)

      update_currencies(currency_map)
    end
  end

  defp backfill_currency_from_dividends do
    null_ids =
      Repo.all(from(i in Instrument, where: is_nil(i.currency), select: i.id))

    if null_ids == [] do
      0
    else
      currency_map =
        DividendPayment
        |> where([d], d.instrument_id in ^null_ids)
        |> group_by([d], [d.instrument_id, d.currency])
        |> select([d], {d.instrument_id, d.currency, count(d.id)})
        |> Repo.all()
        |> Enum.group_by(&elem(&1, 0))
        |> Map.new(fn {instrument_id, entries} ->
          {_, dominant_currency, _} = Enum.max_by(entries, &elem(&1, 2))
          {instrument_id, dominant_currency}
        end)

      update_currencies(currency_map)
    end
  end

  defp backfill_currency_from_flex_csvs do
    flex_dir = Path.join(File.cwd!(), "data_archive/flex")

    if File.dir?(flex_dir) do
      backfill_currency_from_flex_dir(flex_dir)
    else
      Mix.shell().info("  (No data_archive/flex/ directory found)")
      0
    end
  end

  defp backfill_currency_from_flex_dir(flex_dir) do
    null_instruments =
      Repo.all(from(i in Instrument, where: is_nil(i.currency), select: {i.id, i.isin}))

    if null_instruments == [] do
      0
    else
      isin_to_id = Map.new(null_instruments, fn {id, isin} -> {isin, id} end)

      currency_map =
        flex_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".csv"))
        |> Enum.sort(:desc)
        |> Enum.take(10)
        |> Enum.reduce(%{}, fn filename, acc ->
          path = Path.join(flex_dir, filename)
          parse_flex_currencies(path, isin_to_id, acc)
        end)

      update_currencies(currency_map)
    end
  end

  defp parse_flex_currencies(path, isin_to_id, acc) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.drop(1)
        |> Enum.reduce(acc, &match_flex_line(&1, isin_to_id, &2))

      {:error, _} ->
        acc
    end
  end

  defp match_flex_line(line, isin_to_id, map) do
    fields =
      line
      |> String.trim()
      |> String.split(",")
      |> Enum.map(&String.trim(&1, "\""))

    # Flex CSV columns: ReportDate, CurrencyPrimary, Symbol, ..., ISIN, FIGI
    with [_ | _] <- fields,
         isin when isin != "" <- Enum.at(fields, -2, ""),
         currency when currency != "" <- Enum.at(fields, 1, ""),
         instrument_id when not is_nil(instrument_id) <- Map.get(isin_to_id, isin) do
      Map.put_new(map, instrument_id, currency)
    else
      _ -> map
    end
  end

  defp backfill_currency_from_activity_csvs do
    csv_dir = Path.join(File.cwd!(), "csv_data")

    if File.dir?(csv_dir) do
      backfill_currency_from_activity_dir(csv_dir)
    else
      0
    end
  end

  defp backfill_currency_from_activity_dir(csv_dir) do
    null_instruments =
      Repo.all(from(i in Instrument, where: is_nil(i.currency), select: {i.id, i.isin}))

    if null_instruments == [] do
      0
    else
      isin_to_id = Map.new(null_instruments, fn {id, isin} -> {isin, id} end)
      isins = Map.keys(isin_to_id)

      isin_currency_map =
        csv_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".csv"))
        |> Enum.reduce(%{}, fn filename, acc ->
          Path.join(csv_dir, filename)
          |> File.stream!()
          |> Enum.reduce(acc, &match_isin_currency(&1, isins, &2))
        end)

      currency_map =
        Map.new(isin_currency_map, fn {isin, currency} ->
          {Map.fetch!(isin_to_id, isin), currency}
        end)

      update_currencies(currency_map)
    end
  end

  defp match_isin_currency(line, isins, map) do
    Enum.reduce(isins, map, &try_extract_isin_currency(&1, line, &2))
  end

  defp try_extract_isin_currency(isin, line, acc) do
    if String.contains?(line, isin) and !Map.has_key?(acc, isin) do
      case extract_currency_from_line(line) do
        nil -> acc
        currency -> Map.put(acc, isin, currency)
      end
    else
      acc
    end
  end

  defp extract_currency_from_line(line) do
    # Try various patterns:
    # "Corporate Actions,Data,Stocks,USD,..." → position 3
    # "Withholding Tax,Data,USD,..." → position 2
    fields = String.split(String.trim(line), ",")

    cond do
      # Corporate Actions: section,Data,AssetCategory,Currency,...
      Enum.at(fields, 0) == "Corporate Actions" and Enum.at(fields, 1) == "Data" ->
        currency = Enum.at(fields, 3, "")
        if valid_currency?(currency), do: currency, else: nil

      # Withholding Tax / Dividends: section,Data,Currency,...
      Enum.at(fields, 0) in ["Withholding Tax", "Dividends"] and Enum.at(fields, 1) == "Data" ->
        currency = Enum.at(fields, 2, "")
        if valid_currency?(currency), do: currency, else: nil

      true ->
        nil
    end
  end

  defp valid_currency?(str) when is_binary(str) do
    String.length(str) == 3 and str == String.upcase(str) and str =~ ~r/^[A-Z]{3}$/
  end

  defp valid_currency?(_), do: false

  @isin_prefix_to_currency %{
    "US" => "USD",
    "CA" => "CAD",
    "GB" => "GBP",
    "IE" => "EUR",
    "FI" => "EUR",
    "DE" => "EUR",
    "FR" => "EUR",
    "NL" => "EUR",
    "SE" => "SEK",
    "NO" => "NOK",
    "DK" => "DKK",
    "CH" => "CHF",
    "AU" => "AUD",
    "JP" => "JPY",
    "HK" => "HKD",
    "MH" => "USD"
  }

  @exchange_to_currency %{
    "NYSE" => "USD",
    "NASDAQ" => "USD",
    "ARCA" => "USD",
    "AMEX" => "USD",
    "PINK" => "USD",
    "LSE" => "GBP",
    "SWB" => "EUR",
    "HEX" => "EUR",
    "OMXH" => "EUR"
  }

  defp backfill_currency_inferred do
    null_instruments =
      Repo.all(
        from(i in Instrument,
          where: is_nil(i.currency),
          select: {i.id, i.isin, i.listing_exchange}
        )
      )

    currency_map =
      null_instruments
      |> Enum.reduce(%{}, fn {id, isin, exchange}, acc ->
        prefix = String.slice(isin || "", 0, 2)

        currency =
          Map.get(@isin_prefix_to_currency, prefix) ||
            Map.get(@exchange_to_currency, exchange || "")

        if currency, do: Map.put(acc, id, currency), else: acc
      end)

    update_currencies(currency_map)
  end

  defp update_currencies(currency_map) when map_size(currency_map) == 0, do: 0

  defp update_currencies(currency_map) do
    Enum.reduce(currency_map, 0, fn {instrument_id, currency}, count ->
      {1, _} =
        Instrument
        |> where([i], i.id == ^instrument_id and is_nil(i.currency))
        |> Repo.update_all(set: [currency: currency, updated_at: DateTime.utc_now()])

      count + 1
    end)
  end

  # --- Company Data Backfill ---

  defp backfill_company_data do
    Mix.shell().info("\n=== Backfilling company data ===\n")

    # Check if instruments has the enrichment columns yet
    unless has_enrichment_columns?() do
      Mix.shell().info("  Enrichment columns not yet added. Run migration first.")
      return_count(0)
    end

    # Step 1: Fill from already-cached company_profiles
    from_cached = backfill_from_company_profiles()

    # Step 2: Fetch from API for instruments still missing sector
    from_api = backfill_company_from_api()

    Mix.shell().info("\n  Total company data updates: #{from_cached + from_api}")
  end

  defp backfill_company_from_api do
    alias Dividendsomatic.Stocks

    # Find instruments still missing sector, that have a symbol to look up
    missing =
      Repo.all(
        from(i in Instrument,
          where: is_nil(i.sector) and not is_nil(i.symbol),
          select: {i.id, i.symbol}
        )
      )

    Mix.shell().info("  Instruments still missing sector (with symbol): #{length(missing)}")

    if missing == [] do
      0
    else
      Mix.shell().info("  Fetching company profiles from API (1s between calls)...")

      {updated, errors} =
        Enum.reduce(missing, {0, 0}, fn {id, symbol}, acc ->
          fetch_and_update_profile(id, symbol, acc)
        end)

      Mix.shell().info("  From API: #{updated} updated, #{errors} errors")
      updated
    end
  end

  defp fetch_and_update_profile(id, symbol, {ok_count, err_count}) do
    alias Dividendsomatic.Stocks

    case Stocks.get_company_profile(symbol) do
      {:ok, profile} ->
        count = apply_profile_updates(id, profile)
        Process.sleep(1000)
        {ok_count + count, err_count}

      {:error, _reason} ->
        Process.sleep(1000)
        {ok_count, err_count + 1}
    end
  end

  defp apply_profile_updates(id, profile) do
    updates =
      [
        sector: profile.sector,
        industry: profile.industry,
        country: profile.country,
        logo_url: profile.logo_url,
        web_url: profile.web_url,
        updated_at: DateTime.utc_now()
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)

    if updates != [] do
      Instrument
      |> where([i], i.id == ^id)
      |> Repo.update_all(set: updates)

      1
    else
      0
    end
  end

  defp has_enrichment_columns? do
    try do
      Repo.one(from(i in Instrument, select: fragment("1"), limit: 1))
      # Check if sector column exists by querying it
      Repo.one(
        from(i in "instruments",
          select: fragment("sector"),
          limit: 1
        )
      )

      true
    rescue
      _ -> false
    end
  end

  defp backfill_from_company_profiles do
    alias Dividendsomatic.Portfolio.InstrumentAlias
    alias Dividendsomatic.Stocks.CompanyProfile

    # Join: instruments → instrument_aliases (symbol) → company_profiles (symbol)
    results =
      from(i in Instrument,
        join: a in InstrumentAlias,
        on: a.instrument_id == i.id,
        join: cp in CompanyProfile,
        on: cp.symbol == a.symbol,
        where: is_nil(i.sector),
        select: {i.id, cp.sector, cp.industry, cp.country, cp.logo_url, cp.web_url},
        distinct: i.id
      )
      |> Repo.all()

    updated =
      Enum.reduce(results, 0, fn {id, sector, industry, country, logo_url, web_url}, count ->
        updates =
          [
            sector: sector,
            industry: industry,
            country: country,
            logo_url: logo_url,
            web_url: web_url,
            updated_at: DateTime.utc_now()
          ]
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)

        if updates != [] do
          Instrument
          |> where([i], i.id == ^id)
          |> Repo.update_all(set: updates)

          count + 1
        else
          count
        end
      end)

    Mix.shell().info("  Updated #{updated} instruments from company profiles")
    updated
  end

  defp return_count(n), do: n
end
