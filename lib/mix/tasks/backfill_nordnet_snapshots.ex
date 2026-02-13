defmodule Mix.Tasks.Backfill.NordnetSnapshots do
  @moduledoc """
  Generates navigable portfolio snapshots from Nordnet position reconstruction.

  Walks the PositionReconstructor output and creates PortfolioSnapshot + Holding
  records for each weekly data point. This makes the entire 2017-2025 Nordnet era
  navigable via the existing snapshot navigation UI.

  Usage:
    mix backfill.nordnet_snapshots            # Generate snapshots
    mix backfill.nordnet_snapshots --dry-run   # Preview without writing
    mix backfill.nordnet_snapshots --purge     # Delete all reconstructed snapshots first
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.{Portfolio, Repo, Stocks}
  alias Dividendsomatic.Portfolio.{Holding, PortfolioSnapshot, PositionReconstructor}

  @shortdoc "Generate navigable Nordnet-era snapshots"

  def run(args) do
    Mix.Task.run("app.start")

    cond do
      "--purge" in args -> purge_and_rebuild()
      "--dry-run" in args -> dry_run()
      true -> generate_snapshots()
    end
  end

  defp purge_and_rebuild do
    IO.puts("--- Purging existing Nordnet reconstructed snapshots ---\n")

    {snap_count, snapshot_ids} = get_reconstructed_snapshot_ids()

    if snap_count > 0 do
      # Delete holdings first (FK constraint)
      {h_deleted, _} =
        Holding
        |> where([h], h.portfolio_snapshot_id in ^snapshot_ids)
        |> Repo.delete_all()

      {s_deleted, _} =
        PortfolioSnapshot
        |> where([s], s.source == "nordnet_reconstructed")
        |> Repo.delete_all()

      IO.puts("  Deleted #{s_deleted} snapshots and #{h_deleted} holdings\n")
    else
      IO.puts("  No reconstructed snapshots to purge\n")
    end

    generate_snapshots()
  end

  defp dry_run do
    IO.puts("--- Dry Run: Nordnet Snapshot Backfill ---\n")

    points = PositionReconstructor.reconstruct()
    existing_dates = existing_snapshot_dates()

    {would_create, would_skip} =
      Enum.reduce(points, {0, 0}, fn %{date: date, positions: positions}, {create, skip} ->
        if MapSet.member?(existing_dates, date) do
          {create, skip + 1}
        else
          IO.puts("  #{date}: #{length(positions)} positions")
          {create + 1, skip}
        end
      end)

    IO.puts("\n--- Summary ---")
    IO.puts("  Would create: #{would_create} snapshots")
    IO.puts("  Would skip: #{would_skip} (already exist)")
    IO.puts("  Total reconstructed points: #{length(points)}")
  end

  defp generate_snapshots do
    IO.puts("--- Generating Nordnet-era snapshots ---\n")

    points = PositionReconstructor.reconstruct()
    existing_dates = existing_snapshot_dates()

    IO.puts("  Reconstructed points: #{length(points)}")
    IO.puts("  Existing snapshot dates: #{MapSet.size(existing_dates)}\n")

    # Collect all ISINs for batch price lookup
    all_isins =
      points
      |> Enum.flat_map(fn %{positions: positions} -> Enum.map(positions, & &1.isin) end)
      |> Enum.uniq()

    mappings = Stocks.batch_symbol_mappings(all_isins)

    # Collect all needed symbols and date range for batch price loading
    {stock_symbols, fx_pairs} = collect_needed_symbols(points, mappings)
    all_symbols = stock_symbols ++ fx_pairs

    all_dates = Enum.map(points, & &1.date)
    min_date = Date.add(Enum.min(all_dates, Date), -5)
    max_date = Enum.max(all_dates, Date)

    IO.puts("  Loading prices for #{length(all_symbols)} symbols...")
    price_map = Stocks.batch_historical_prices(all_symbols, min_date, max_date)
    IO.puts("  Price map loaded\n")

    # Generate snapshots
    new_points = Enum.reject(points, fn p -> MapSet.member?(existing_dates, p.date) end)
    skipped = length(points) - length(new_points)

    {created, errors} =
      Enum.reduce(new_points, {0, 0}, fn point, acc ->
        process_point(point, mappings, price_map, acc)
      end)

    Portfolio.invalidate_chart_cache()

    IO.puts("\n--- Done ---")
    IO.puts("  Created: #{created}")
    IO.puts("  Skipped: #{skipped} (already existed)")
    IO.puts("  Errors: #{errors}")
  end

  defp process_point(point, mappings, price_map, {c, e}) do
    case create_snapshot(point, mappings, price_map) do
      {:ok, _} ->
        if rem(c + 1, 25) == 0, do: IO.puts("  Created #{c + 1} snapshots...")
        {c + 1, e}

      {:error, reason} ->
        IO.puts("  ERROR #{point.date}: #{inspect(reason)}")
        {c, e + 1}
    end
  end

  defp create_snapshot(%{date: date, positions: positions}, mappings, price_map) do
    Repo.transaction(fn ->
      # Create the snapshot
      {:ok, snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{
          report_date: date,
          source: "nordnet_reconstructed"
        })
        |> Repo.insert()

      # Create holdings for each position
      Enum.each(positions, fn pos ->
        create_holding(snapshot, pos, date, mappings, price_map)
      end)

      snapshot
    end)
  end

  defp create_holding(snapshot, position, date, mappings, price_map) do
    {mark_price, fx_rate} = lookup_price_and_fx(position, date, mappings, price_map)

    position_value =
      if mark_price do
        Decimal.mult(position.quantity, mark_price)
      else
        nil
      end

    # Cost basis per share
    cost_basis_price =
      if Decimal.compare(position.quantity, Decimal.new("0")) == :gt do
        Decimal.div(position.cost_basis, position.quantity)
      else
        nil
      end

    attrs = %{
      portfolio_snapshot_id: snapshot.id,
      report_date: date,
      currency_primary: position.currency,
      symbol: extract_symbol(position, mappings),
      description: position.security_name,
      quantity: position.quantity,
      mark_price: mark_price,
      position_value: position_value,
      cost_basis_price: cost_basis_price,
      cost_basis_money: position.cost_basis,
      fx_rate_to_base: fx_rate,
      isin: position.isin,
      asset_class: "STK",
      identifier_key: position.isin
    }

    %Holding{}
    |> Holding.changeset(attrs)
    |> Repo.insert!()
  end

  defp lookup_price_and_fx(position, date, mappings, price_map) do
    mark_price = lookup_mark_price(position.isin, date, mappings, price_map)
    fx_rate = lookup_fx_rate(position.currency, date, price_map)
    {mark_price, fx_rate}
  end

  defp lookup_mark_price(isin, date, mappings, price_map) do
    with %{finnhub_symbol: symbol} when is_binary(symbol) <- Map.get(mappings, isin),
         {:ok, price} <- Stocks.batch_get_close_price(price_map, symbol, date) do
      price
    else
      _ -> nil
    end
  end

  defp lookup_fx_rate("EUR", _date, _price_map), do: Decimal.new("1")

  defp lookup_fx_rate(currency, date, price_map) do
    pair = "OANDA:EUR_#{currency}"

    with {:ok, rate} <- Stocks.batch_get_close_price(price_map, pair, date),
         true <- Decimal.compare(rate, Decimal.new("0")) == :gt do
      Decimal.div(Decimal.new("1"), rate)
    else
      _ -> nil
    end
  end

  defp extract_symbol(position, mappings) do
    case Map.get(mappings, position.isin) do
      %{finnhub_symbol: symbol} when is_binary(symbol) ->
        # Strip exchange suffix for display (e.g., "NESN.SW" -> "NESN")
        symbol |> String.split(".") |> hd()

      _ ->
        # Fallback: use ISIN or security name
        position.security_name || position.isin
    end
  end

  defp collect_needed_symbols(points, mappings) do
    all_positions = Enum.flat_map(points, & &1.positions)

    {symbols, currencies} =
      Enum.reduce(all_positions, {MapSet.new(), MapSet.new()}, fn pos, {syms, curs} ->
        collect_position_symbols(pos, mappings, syms, curs)
      end)

    fx_pairs = Enum.map(currencies, fn cur -> "OANDA:EUR_#{cur}" end)
    {MapSet.to_list(symbols), fx_pairs}
  end

  defp collect_position_symbols(pos, mappings, syms, curs) do
    case Map.get(mappings, pos.isin) do
      %{finnhub_symbol: sym} when is_binary(sym) ->
        curs = if pos.currency != "EUR", do: MapSet.put(curs, pos.currency), else: curs
        {MapSet.put(syms, sym), curs}

      _ ->
        {syms, curs}
    end
  end

  defp existing_snapshot_dates do
    PortfolioSnapshot
    |> select([s], s.report_date)
    |> Repo.all()
    |> MapSet.new()
  end

  defp get_reconstructed_snapshot_ids do
    ids =
      PortfolioSnapshot
      |> where([s], s.source == "nordnet_reconstructed")
      |> select([s], s.id)
      |> Repo.all()

    {length(ids), ids}
  end
end
