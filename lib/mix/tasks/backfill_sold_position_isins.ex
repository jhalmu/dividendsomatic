defmodule Mix.Tasks.Backfill.SoldPositionIsins do
  @moduledoc """
  Backfill ISINs on sold_positions using symbol→ISIN lookup maps.

  Builds lookup from instruments + instrument_aliases + positions,
  then matches sold_positions by symbol. Recalculates identifier_key.

  ## Usage

      mix backfill.sold_position_isins           # Run backfill
      mix backfill.sold_position_isins --dry-run  # Preview without changes
  """

  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{Instrument, InstrumentAlias, Position, SoldPosition}
  alias Dividendsomatic.Repo

  require Logger

  @shortdoc "Backfill ISINs on sold_positions from instruments/aliases/positions"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Logger.configure(level: :info)

    {opts, _, _} = OptionParser.parse(args, switches: [dry_run: :boolean])
    dry_run = opts[:dry_run] || false

    if dry_run, do: Mix.shell().info("=== DRY RUN — no changes will be made ===\n")

    Mix.shell().info("=== Backfilling sold_position ISINs ===\n")

    # Build symbol→ISIN lookup maps
    {unique_map, ambiguous_map} = build_symbol_isin_maps()

    Mix.shell().info(
      "Symbol lookup: #{map_size(unique_map)} unique, #{map_size(ambiguous_map)} ambiguous"
    )

    # Load sold_positions missing ISIN
    null_positions =
      Repo.all(
        from(sp in SoldPosition,
          where: is_nil(sp.isin),
          select: %{
            id: sp.id,
            symbol: sp.symbol,
            currency: sp.currency,
            purchase_date: sp.purchase_date,
            sale_date: sp.sale_date
          }
        )
      )

    Mix.shell().info("Sold positions missing ISIN: #{length(null_positions)}\n")

    # Resolve ISINs
    {resolved, ambiguous_resolved, unresolved} =
      resolve_isins(null_positions, unique_map, ambiguous_map)

    Mix.shell().info("  Direct match: #{length(resolved)}")
    Mix.shell().info("  Ambiguity resolved: #{length(ambiguous_resolved)}")
    Mix.shell().info("  Unresolved: #{length(unresolved)}")

    unless dry_run do
      all_resolved = resolved ++ ambiguous_resolved
      updated = apply_updates(all_resolved)
      Mix.shell().info("\nUpdated #{updated} sold positions with ISIN")
    end

    # Show remaining unresolved symbols
    if unresolved != [] do
      unresolved_symbols =
        unresolved
        |> Enum.frequencies_by(& &1.symbol)
        |> Enum.sort_by(&elem(&1, 1), :desc)
        |> Enum.take(20)

      Mix.shell().info("\nTop unresolved symbols:")

      Enum.each(unresolved_symbols, fn {symbol, count} ->
        Mix.shell().info("  #{symbol}: #{count}")
      end)
    end

    # Final stats
    remaining =
      Repo.one(from(sp in SoldPosition, where: is_nil(sp.isin), select: count()))

    total = Repo.one(from(sp in SoldPosition, select: count()))
    Mix.shell().info("\nFinal: #{total - remaining}/#{total} sold positions have ISIN")
  end

  defp build_symbol_isin_maps do
    # Source 1: instruments table (symbol → isin, authoritative)
    instrument_entries =
      Repo.all(
        from(i in Instrument,
          where: not is_nil(i.symbol) and not is_nil(i.isin),
          select: {i.symbol, i.isin, i.currency}
        )
      )

    # Source 2: instrument_aliases → instruments (alias symbol → isin)
    alias_entries =
      Repo.all(
        from(a in InstrumentAlias,
          join: i in Instrument,
          on: a.instrument_id == i.id,
          where: not is_nil(i.isin),
          select: {a.symbol, i.isin, i.currency}
        )
      )

    # Source 3: positions (symbol → isin, most recent, authoritative)
    position_entries =
      Repo.all(
        from(p in Position,
          where: not is_nil(p.isin) and not is_nil(p.symbol),
          distinct: [p.symbol, p.isin],
          select: {p.symbol, p.isin, p.currency}
        )
      )

    # Combine all entries, group by symbol
    all_entries = instrument_entries ++ alias_entries ++ position_entries

    by_symbol =
      all_entries
      |> Enum.group_by(&elem(&1, 0))
      |> Map.new(fn {symbol, entries} ->
        unique_isins =
          entries
          |> Enum.map(fn {_, isin, currency} -> {isin, currency} end)
          |> Enum.uniq_by(&elem(&1, 0))

        {symbol, unique_isins}
      end)

    # Split into unique (1 ISIN) and ambiguous (multiple ISINs)
    {unique_entries, ambiguous_entries} =
      Enum.split_with(by_symbol, fn {_symbol, isins} -> length(isins) == 1 end)

    unique_map =
      Map.new(unique_entries, fn {symbol, [{isin, _currency}]} -> {symbol, isin} end)

    ambiguous_map =
      Map.new(ambiguous_entries, fn {symbol, isins} -> {symbol, isins} end)

    {unique_map, ambiguous_map}
  end

  defp resolve_isins(positions, unique_map, ambiguous_map) do
    Enum.reduce(positions, {[], [], []}, fn sp, acc ->
      resolve_single(sp, unique_map, ambiguous_map, acc)
    end)
  end

  defp resolve_single(sp, unique_map, ambiguous_map, {resolved, ambig_resolved, unresolved}) do
    cond do
      Map.has_key?(unique_map, sp.symbol) ->
        isin = Map.fetch!(unique_map, sp.symbol)
        {[Map.put(sp, :resolved_isin, isin) | resolved], ambig_resolved, unresolved}

      Map.has_key?(ambiguous_map, sp.symbol) ->
        try_disambiguate(sp, ambiguous_map, {resolved, ambig_resolved, unresolved})

      true ->
        {resolved, ambig_resolved, [sp | unresolved]}
    end
  end

  defp try_disambiguate(sp, ambiguous_map, {resolved, ambig_resolved, unresolved}) do
    isins = Map.fetch!(ambiguous_map, sp.symbol)

    case disambiguate(sp, isins) do
      {:ok, isin} ->
        {resolved, [Map.put(sp, :resolved_isin, isin) | ambig_resolved], unresolved}

      :ambiguous ->
        {resolved, ambig_resolved, [sp | unresolved]}
    end
  end

  defp disambiguate(sp, isins) do
    # Strategy 1: Match by currency
    by_currency = Enum.filter(isins, fn {_isin, currency} -> currency == sp.currency end)

    case by_currency do
      [{isin, _}] -> {:ok, isin}
      _ -> :ambiguous
    end
  end

  defp apply_updates(resolved_positions) do
    Enum.reduce(resolved_positions, 0, fn sp, count ->
      isin = sp.resolved_isin
      identifier_key = isin

      {updated, _} =
        SoldPosition
        |> where([s], s.id == ^sp.id and is_nil(s.isin))
        |> Repo.update_all(
          set: [
            isin: isin,
            identifier_key: identifier_key,
            updated_at: DateTime.utc_now()
          ]
        )

      count + updated
    end)
  end
end
