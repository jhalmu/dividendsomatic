defmodule Dividendsomatic.Portfolio do
  @moduledoc """
  Portfolio context for managing snapshots and positions.
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.{
    BrokerTransaction,
    Cost,
    CsvParser,
    Dividend,
    DividendAnalytics,
    PortfolioSnapshot,
    Position,
    SoldPosition
  }

  alias Dividendsomatic.Repo

  ## Portfolio Snapshots

  @doc """
  Returns the latest portfolio snapshot.
  """
  def get_latest_snapshot do
    PortfolioSnapshot
    |> order_by([s], desc: s.date)
    |> limit(1)
    |> preload(:positions)
    |> Repo.one()
  end

  @doc """
  Returns snapshot for a specific date.
  """
  def get_snapshot_by_date(date) do
    Repo.get_by(PortfolioSnapshot, date: date)
    |> Repo.preload(:positions)
  end

  @doc """
  Returns snapshot before given date (for navigation).
  """
  def get_previous_snapshot(date) do
    PortfolioSnapshot
    |> where([s], s.date < ^date)
    |> order_by([s], desc: s.date)
    |> limit(1)
    |> preload(:positions)
    |> Repo.one()
  end

  @doc """
  Returns snapshot after given date (for navigation).
  """
  def get_next_snapshot(date) do
    PortfolioSnapshot
    |> where([s], s.date > ^date)
    |> order_by([s], asc: s.date)
    |> limit(1)
    |> preload(:positions)
    |> Repo.one()
  end

  @doc """
  Returns the snapshot N positions before the given date.
  """
  def get_snapshot_back(date, n) do
    PortfolioSnapshot
    |> where([s], s.date < ^date)
    |> order_by([s], desc: s.date)
    |> offset(^(n - 1))
    |> limit(1)
    |> preload(:positions)
    |> Repo.one()
  end

  @doc """
  Returns the snapshot N positions after the given date.
  """
  def get_snapshot_forward(date, n) do
    PortfolioSnapshot
    |> where([s], s.date > ^date)
    |> order_by([s], asc: s.date)
    |> offset(^(n - 1))
    |> limit(1)
    |> preload(:positions)
    |> Repo.one()
  end

  @doc """
  Lists all snapshots ordered by date descending.
  """
  def list_snapshots do
    PortfolioSnapshot
    |> order_by([s], desc: s.date)
    |> Repo.all()
  end

  @doc """
  Checks if a snapshot exists before the given date.
  """
  def has_previous_snapshot?(date) do
    PortfolioSnapshot
    |> where([s], s.date < ^date)
    |> Repo.exists?()
  end

  @doc """
  Checks if a snapshot exists after the given date.
  """
  def has_next_snapshot?(date) do
    PortfolioSnapshot
    |> where([s], s.date > ^date)
    |> Repo.exists?()
  end

  @doc """
  Returns snapshot data for charting (date and total value).
  """
  def get_chart_data(limit \\ 30) do
    PortfolioSnapshot
    |> order_by([s], desc: s.date)
    |> limit(^limit)
    |> select([s], %{
      date: s.date,
      date_string: fragment("to_char(?, 'YYYY-MM-DD')", s.date),
      value: s.total_value,
      value_float: type(s.total_value, :float),
      cost_basis_float: type(s.total_cost, :float),
      source: s.source,
      data_quality: s.data_quality
    })
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  Returns ALL chart data from the unified portfolio_snapshots table.

  Simple query — no runtime reconstruction needed. All data sources
  (IBKR Flex, Nordnet, 9A) write precomputed totals at import time.
  """
  def get_all_chart_data do
    PortfolioSnapshot
    |> order_by([s], asc: s.date)
    |> select([s], %{
      date: s.date,
      date_string: fragment("to_char(?, 'YYYY-MM-DD')", s.date),
      value: s.total_value,
      value_float: type(s.total_value, :float),
      cost_basis_float: type(s.total_cost, :float),
      source: s.source,
      data_quality: s.data_quality
    })
    |> Repo.all()
  end

  @doc """
  Returns growth statistics comparing first snapshot to the given snapshot.
  Falls back to latest snapshot if none provided.
  """
  def get_growth_stats(current_snapshot \\ nil) do
    first = get_first_snapshot()
    current = current_snapshot || get_latest_snapshot()

    case {first, current} do
      {nil, _} ->
        nil

      {_, nil} ->
        nil

      {first_snap, current_snap} ->
        first_value = first_snap.total_value || calculate_total_value(first_snap.positions)
        current_value = current_snap.total_value || calculate_total_value(current_snap.positions)
        absolute_change = Decimal.sub(current_value, first_value)

        percent_change =
          if Decimal.compare(first_value, Decimal.new("0")) == :gt do
            first_value
            |> Decimal.div(Decimal.new("100"))
            |> then(&Decimal.div(absolute_change, &1))
            |> Decimal.round(2)
          else
            Decimal.new("0")
          end

        %{
          first_date: first_snap.date,
          latest_date: current_snap.date,
          first_value: first_value,
          latest_value: current_value,
          absolute_change: absolute_change,
          percent_change: percent_change
        }
    end
  end

  defp calculate_total_value(positions) do
    Enum.reduce(positions || [], Decimal.new("0"), fn pos, acc ->
      Decimal.add(acc, to_base_currency(pos.value, pos.fx_rate))
    end)
  end

  defp to_base_currency(nil, _fx_rate), do: Decimal.new("0")
  defp to_base_currency(_amount, nil), do: Decimal.new("0")

  defp to_base_currency(amount, fx_rate) do
    Decimal.mult(amount, fx_rate)
  end

  @doc """
  Returns the first (oldest) snapshot.
  """
  def get_first_snapshot do
    PortfolioSnapshot
    |> order_by([s], asc: s.date)
    |> limit(1)
    |> preload(:positions)
    |> Repo.one()
  end

  @doc """
  Returns the date of the latest actual (non-reconstructed) snapshot.
  """
  def get_latest_snapshot_date do
    PortfolioSnapshot
    |> where([s], s.data_quality == "actual")
    |> select([s], max(s.date))
    |> Repo.one()
  end

  @doc """
  Returns the total count of snapshots.
  """
  def count_snapshots do
    Repo.aggregate(PortfolioSnapshot, :count)
  end

  @doc """
  Returns the position (1-based index) of a snapshot by date.
  """
  def get_snapshot_position(date) do
    PortfolioSnapshot
    |> where([s], s.date <= ^date)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns the snapshot closest to the given date (before or after).
  """
  def get_snapshot_nearest_date(target_date) do
    before =
      PortfolioSnapshot
      |> where([s], s.date <= ^target_date)
      |> order_by(desc: :date)
      |> limit(1)
      |> preload(:positions)
      |> Repo.one()

    after_s =
      PortfolioSnapshot
      |> where([s], s.date >= ^target_date)
      |> order_by(asc: :date)
      |> limit(1)
      |> preload(:positions)
      |> Repo.one()

    case {before, after_s} do
      {nil, nil} ->
        nil

      {b, nil} ->
        b

      {nil, a} ->
        a

      {b, a} ->
        if abs(Date.diff(b.date, target_date)) <= abs(Date.diff(a.date, target_date)),
          do: b,
          else: a
    end
  end

  @doc """
  Returns the snapshot at a given 1-based position (ordered by date ASC).
  """
  def get_snapshot_at_position(position) when is_integer(position) and position >= 1 do
    PortfolioSnapshot
    |> order_by([s], asc: s.date)
    |> offset(^(position - 1))
    |> limit(1)
    |> preload(:positions)
    |> Repo.one()
  end

  def get_snapshot_at_position(_), do: nil

  @doc """
  Creates a portfolio snapshot with positions from CSV data.

  Returns `{:ok, snapshot}` on success, `{:error, reason}` on failure.
  """
  def create_snapshot_from_csv(csv_data, report_date) do
    Repo.transaction(fn ->
      case create_snapshot(report_date, csv_data) do
        {:ok, snapshot} ->
          positions = parse_csv_positions(csv_data, snapshot.id, report_date)
          {total_value, total_cost} = compute_snapshot_totals(positions)

          {:ok, snapshot} =
            snapshot
            |> PortfolioSnapshot.changeset(%{
              total_value: total_value,
              total_cost: total_cost,
              positions_count: length(positions)
            })
            |> Repo.update()

          snapshot

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp create_snapshot(report_date, csv_data) do
    metadata =
      if is_binary(csv_data) and csv_data != "",
        do: %{"raw_csv" => String.length(csv_data)},
        else: nil

    %PortfolioSnapshot{}
    |> PortfolioSnapshot.changeset(%{
      date: report_date,
      source: "ibkr_flex",
      data_quality: "actual",
      metadata: metadata
    })
    |> Repo.insert()
  end

  defp parse_csv_positions(csv_data, snapshot_id, report_date) do
    csv_data
    |> CsvParser.parse(snapshot_id, report_date)
    |> Enum.map(fn attrs ->
      %Position{}
      |> Position.changeset(attrs)
      |> Repo.insert!()
    end)
  end

  defp compute_snapshot_totals(positions) do
    Enum.reduce(positions, {Decimal.new("0"), Decimal.new("0")}, fn pos, {val_acc, cost_acc} ->
      fx = pos.fx_rate || Decimal.new("1")
      pos_val = pos.value || Decimal.new("0")
      cost_val = pos.cost_basis || Decimal.new("0")

      {
        Decimal.add(val_acc, Decimal.mult(pos_val, fx)),
        Decimal.add(cost_acc, Decimal.mult(cost_val, fx))
      }
    end)
  end

  ## Dividends

  @doc """
  Lists all positions for a specific symbol (from most recent snapshots).
  """
  def list_positions_by_symbol(symbol) do
    Position
    |> where([p], p.symbol == ^symbol)
    |> order_by([p], desc: p.date)
    |> Repo.all()
  end

  # Keep old name as alias for backward compatibility during transition
  defdelegate list_holdings_by_symbol(symbol), to: __MODULE__, as: :list_positions_by_symbol

  @doc """
  Lists all dividends ordered by ex_date descending.
  """
  def list_dividends do
    Dividend
    |> order_by([d], desc: d.ex_date)
    |> Repo.all()
  end

  @doc """
  Lists dividends for a specific symbol.
  """
  def list_dividends_by_symbol(symbol) do
    Dividend
    |> where([d], d.symbol == ^symbol)
    |> order_by([d], desc: d.ex_date)
    |> Repo.all()
  end

  @doc """
  Lists dividends for the current year.
  """
  def list_dividends_this_year do
    year_start = Date.new!(Date.utc_today().year, 1, 1)

    Dividend
    |> where([d], d.ex_date >= ^year_start)
    |> order_by([d], desc: d.ex_date)
    |> Repo.all()
  end

  @doc """
  Lists dividends for the current year with computed income (per-share * qty * fx).
  """
  def list_dividends_with_income do
    year_start = Date.new!(Date.utc_today().year, 1, 1)
    today = Date.utc_today()

    dividends =
      Dividend
      |> where([d], d.ex_date >= ^year_start and d.ex_date <= ^today)
      |> order_by([d], desc: d.ex_date)
      |> Repo.all()

    positions_data = build_positions_map(year_start, today)

    dividends
    |> Enum.map(fn div ->
      income = compute_dividend_income(div, positions_data)
      %{dividend: div, income: income}
    end)
    |> Enum.filter(fn entry ->
      Decimal.compare(entry.income, Decimal.new("0")) == :gt
    end)
  end

  @doc """
  Gets total dividend income for the current year (base currency).
  """
  def total_dividends_this_year do
    total_dividends_for_year(Date.utc_today().year)
  end

  @doc """
  Gets total dividend income for a specific year.
  """
  def total_dividends_for_year(year) do
    year_start = Date.new!(year, 1, 1)

    year_end =
      if year == Date.utc_today().year, do: Date.utc_today(), else: Date.new!(year, 12, 31)

    dividends_by_month(year_start, year_end)
    |> Enum.reduce(Decimal.new("0"), fn %{total: t}, acc -> Decimal.add(acc, t) end)
  end

  @doc """
  Returns years that have dividend data, most recent first.
  """
  def dividend_years do
    Dividend
    |> where([d], not is_nil(d.ex_date))
    |> select([d], fragment("DISTINCT EXTRACT(YEAR FROM ?)::integer", d.ex_date))
    |> Repo.all()
    |> Enum.sort(:desc)
  end

  @doc """
  Gets dividend income grouped by month for the current year.
  """
  def dividends_by_month do
    year_start = Date.new!(Date.utc_today().year, 1, 1)
    dividends_by_month(year_start, Date.utc_today())
  end

  @doc """
  Gets dividend income grouped by month for a date range.
  """
  def dividends_by_month(from_date, to_date) do
    dividends =
      Dividend
      |> where([d], d.ex_date >= ^from_date and d.ex_date <= ^to_date)
      |> order_by([d], asc: d.ex_date)
      |> Repo.all()

    positions_map = build_positions_map(from_date, to_date)

    dividends
    |> Enum.map(fn div ->
      month = Calendar.strftime(div.ex_date, "%Y-%m")
      income = compute_dividend_income(div, positions_map)
      {month, income}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {month, incomes} ->
      %{month: month, total: Enum.reduce(incomes, Decimal.new("0"), &Decimal.add/2)}
    end)
    |> Enum.sort_by(& &1.month)
  end

  defp build_positions_map(from_date, to_date) do
    lookback_snapshot =
      PortfolioSnapshot
      |> where([s], s.date < ^from_date)
      |> order_by([s], desc: s.date)
      |> limit(1)
      |> preload(:positions)
      |> Repo.all()

    range_snapshots =
      PortfolioSnapshot
      |> where([s], s.date >= ^from_date and s.date <= ^to_date)
      |> preload(:positions)
      |> order_by([s], asc: s.date)
      |> Repo.all()

    (lookback_snapshot ++ range_snapshots)
    |> Enum.flat_map(fn snapshot ->
      Enum.map(snapshot.positions, fn p ->
        {snapshot.date, p.symbol, p.quantity, p.fx_rate, p.currency}
      end)
    end)
  end

  defp compute_dividend_income(dividend, positions_data) do
    amount = dividend.amount || Decimal.new("0")

    # Find matching position for fx_rate and quantity
    matching = find_matching_position(dividend, positions_data)

    {matched_qty, holding_fx, holding_currency} =
      case matching do
        {_date, _symbol, quantity, fx_rate, currency} ->
          {quantity || Decimal.new("0"), fx_rate || Decimal.new("1"), currency}

        nil ->
          {Decimal.new("0"), Decimal.new("1"), nil}
      end

    div_currency = Map.get(dividend, :currency)
    fx = resolve_fx_rate(dividend, div_currency, holding_fx, holding_currency)

    if Map.get(dividend, :amount_type) == "total_net" do
      Decimal.mult(amount, fx)
    else
      Decimal.mult(Decimal.mult(amount, matched_qty), fx)
    end
  end

  # Prefer dividend's own fx_rate; fall back to position fx_rate only if currencies match.
  # Returns 0 for unknown cross-currency cases to avoid inflating totals.
  defp resolve_fx_rate(dividend, div_currency, holding_fx, holding_currency) do
    cond do
      Map.get(dividend, :fx_rate) != nil -> Map.get(dividend, :fx_rate)
      div_currency == "EUR" -> Decimal.new("1")
      div_currency == holding_currency -> holding_fx
      true -> Decimal.new("0")
    end
  end

  defp find_matching_position(dividend, positions_data) do
    # Only consider positions matching symbol and within -7..+45 days of ex_date
    Enum.filter(positions_data, fn {date, symbol, _qty, _fx, _cur} ->
      if symbol == dividend.symbol do
        diff = Date.diff(dividend.ex_date, date)
        diff >= -7 and diff <= 45
      end
    end)
    |> Enum.min_by(
      fn {date, _, _, _, _} -> abs(Date.diff(date, dividend.ex_date)) end,
      fn -> nil end
    )
  end

  @doc """
  Imports dividends from a Flex Dividend CSV string.

  Deduplicates by ISIN+ex_date first, then symbol+ex_date.
  Returns `{:ok, %{imported: n, skipped: n}}`.
  """
  def import_flex_dividends_csv(csv_string) do
    alias Dividendsomatic.Portfolio.FlexDividendCsvParser

    case FlexDividendCsvParser.parse(csv_string) do
      {:ok, records} ->
        results = Enum.map(records, &upsert_dividend/1)
        imported = Enum.count(results, &match?({:ok, _}, &1))
        skipped = Enum.count(results, &match?(:skipped, &1))
        {:ok, %{imported: imported, skipped: skipped}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upsert_dividend(attrs) do
    cond do
      attrs[:isin] && attrs[:ex_date] && dividend_exists_by_isin?(attrs.isin, attrs.ex_date) ->
        :skipped

      attrs[:symbol] && attrs[:ex_date] && dividend_exists_by_symbol?(attrs.symbol, attrs.ex_date) ->
        :skipped

      true ->
        create_dividend(attrs)
    end
  end

  defp dividend_exists_by_isin?(isin, ex_date) do
    Dividend
    |> where([d], d.isin == ^isin and d.ex_date == ^ex_date)
    |> Repo.exists?()
  end

  defp dividend_exists_by_symbol?(symbol, ex_date) do
    Dividend
    |> where([d], d.symbol == ^symbol and d.ex_date == ^ex_date)
    |> Repo.exists?()
  end

  @doc """
  Creates a dividend record.
  """
  def create_dividend(attrs) do
    %Dividend{}
    |> Dividend.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a dividend record.
  """
  def update_dividend(%Dividend{} = dividend, attrs) do
    dividend
    |> Dividend.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a dividend record.
  """
  def delete_dividend(%Dividend{} = dividend) do
    Repo.delete(dividend)
  end

  @doc """
  Gets a dividend by ID.
  """
  def get_dividend(id) do
    Repo.get(Dividend, id)
  end

  @doc """
  Gets projected annual dividend income based on current year rate.
  """
  def projected_annual_dividends do
    today = Date.utc_today()
    year_start = Date.new!(today.year, 1, 1)
    days_elapsed = Date.diff(today, year_start) + 1
    total = total_dividends_this_year()

    if days_elapsed > 0 do
      daily_rate = Decimal.div(total, Decimal.new(days_elapsed))
      Decimal.mult(daily_rate, Decimal.new(365)) |> Decimal.round(2)
    else
      Decimal.new("0")
    end
  end

  ## Dividend Dashboard (batch computation)

  @doc """
  Computes all dividend-related data in one pass.
  """
  def compute_dividend_dashboard(year, chart_date_range, positions \\ []) do
    today = Date.utc_today()
    year_start = Date.new!(year, 1, 1)
    year_end = if year == today.year, do: today, else: Date.new!(year, 12, 31)

    {widest_from, widest_to} = dashboard_date_range(year_start, year_end, chart_date_range)
    positions_map = build_positions_map(widest_from, widest_to)
    all_dividends = load_dividends_in_range(widest_from, widest_to)

    year_dividends = filter_date_range(all_dividends, year_start, year_end)
    year_by_month = compute_by_month(year_dividends, positions_map)
    total_for_year = sum_monthly_totals(year_by_month)

    per_symbol = compute_per_symbol_dividends(positions, all_dividends, positions_map)

    %{
      total_for_year: total_for_year,
      projected_annual: compute_projected_annual(year, today, year_start, total_for_year),
      recent_with_income: compute_recent_with_income(year_dividends, positions_map),
      cash_flow_summary: compute_cash_flow(year, today.year, year_by_month),
      by_month_full_range:
        compute_chart_range_months(chart_date_range, all_dividends, positions_map, year_by_month),
      per_symbol: per_symbol
    }
  end

  defp dashboard_date_range(year_start, year_end, nil), do: {year_start, year_end}

  defp dashboard_date_range(year_start, year_end, {chart_start, chart_end}) do
    {Enum.min([year_start, chart_start], Date), Enum.max([year_end, chart_end], Date)}
  end

  defp load_dividends_in_range(from, to) do
    Dividend
    |> where([d], d.ex_date >= ^from and d.ex_date <= ^to)
    |> order_by([d], asc: d.ex_date)
    |> Repo.all()
  end

  defp filter_date_range(dividends, from, to) do
    Enum.filter(dividends, fn d ->
      Date.compare(d.ex_date, from) != :lt and Date.compare(d.ex_date, to) != :gt
    end)
  end

  defp sum_monthly_totals(by_month) do
    Enum.reduce(by_month, Decimal.new("0"), fn %{total: t}, acc -> Decimal.add(acc, t) end)
  end

  defp compute_projected_annual(year, today, year_start, total) do
    if year == today.year do
      days_elapsed = Date.diff(today, year_start) + 1

      if days_elapsed > 0 do
        Decimal.div(total, Decimal.new(days_elapsed))
        |> Decimal.mult(Decimal.new(365))
        |> Decimal.round(2)
      else
        Decimal.new("0")
      end
    else
      nil
    end
  end

  defp compute_recent_with_income(year_dividends, positions_map) do
    year_dividends
    |> Enum.reverse()
    |> Enum.map(fn div ->
      %{dividend: div, income: compute_dividend_income(div, positions_map)}
    end)
    |> Enum.filter(fn entry -> Decimal.compare(entry.income, Decimal.new("0")) == :gt end)
    |> Enum.take(5)
  end

  defp compute_cash_flow(year, current_year, _year_by_month) when year != current_year, do: []

  defp compute_cash_flow(_year, current_year, year_by_month) do
    year_prefix = Integer.to_string(current_year)

    {entries, _} =
      year_by_month
      |> Enum.filter(fn %{month: m} -> String.starts_with?(m, year_prefix) end)
      |> Enum.map_reduce(Decimal.new("0"), fn %{month: month, total: total}, acc ->
        cumulative = Decimal.add(acc, total)
        {%{month: month, income: total, cumulative: cumulative}, cumulative}
      end)

    entries
  end

  defp compute_chart_range_months(nil, _all_dividends, _positions_map, year_by_month),
    do: year_by_month

  defp compute_chart_range_months({chart_start, chart_end}, all_dividends, positions_map, _) do
    all_dividends
    |> filter_date_range(chart_start, chart_end)
    |> compute_by_month(positions_map)
  end

  defp compute_by_month(dividends, positions_map) do
    dividends
    |> Enum.map(fn div ->
      month = Calendar.strftime(div.ex_date, "%Y-%m")
      income = compute_dividend_income(div, positions_map)
      {month, income}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {month, incomes} ->
      %{month: month, total: Enum.reduce(incomes, Decimal.new("0"), &Decimal.add/2)}
    end)
    |> Enum.sort_by(& &1.month)
  end

  defp compute_per_symbol_dividends([], _all_dividends, _positions_map), do: %{}

  defp compute_per_symbol_dividends(positions, all_dividends, positions_map) do
    current_symbols = MapSet.new(positions, & &1.symbol)

    divs_by_symbol =
      all_dividends
      |> Enum.filter(fn d -> MapSet.member?(current_symbols, d.symbol) end)
      |> Enum.group_by(& &1.symbol)

    pos_map = Map.new(positions, fn p -> {p.symbol, p} end)

    Map.new(divs_by_symbol, fn {symbol, divs} ->
      pos = Map.get(pos_map, symbol)
      divs_with_income = build_divs_with_income(divs, positions_map)
      {symbol, build_symbol_dividend_data(divs_with_income, divs, pos)}
    end)
  end

  defp build_divs_with_income(divs, positions_map) do
    Enum.map(divs, fn div ->
      %{dividend: div, income: compute_dividend_income(div, positions_map)}
    end)
  end

  defp build_symbol_dividend_data(divs_with_income, raw_divs, pos) do
    annual_per_share = DividendAnalytics.compute_annual_dividend_per_share(divs_with_income)
    yield_on_cost = symbol_yield_on_cost(annual_per_share, pos)
    projected_annual = symbol_projected_annual(annual_per_share, pos)
    ytd_paid = symbol_ytd_paid(divs_with_income)

    %{
      est_monthly: symbol_est_monthly(projected_annual),
      annual_per_share: annual_per_share,
      projected_annual: projected_annual,
      est_remaining: symbol_est_remaining(projected_annual, ytd_paid),
      yield_on_cost: yield_on_cost,
      rule72: symbol_rule72(yield_on_cost),
      payment_frequency: detect_payment_frequency(raw_divs)
    }
  end

  defp detect_payment_frequency(divs) when length(divs) < 3, do: :unknown

  defp detect_payment_frequency(divs) do
    divs
    |> Enum.sort_by(& &1.ex_date, Date)
    |> Enum.map(& &1.ex_date)
    |> avg_date_interval()
    |> interval_to_frequency()
  end

  defp avg_date_interval(dates) do
    intervals =
      dates
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> Date.diff(b, a) end)

    if intervals == [], do: 0, else: Enum.sum(intervals) / length(intervals)
  end

  defp interval_to_frequency(avg) when avg > 0 and avg < 45, do: :monthly
  defp interval_to_frequency(avg) when avg < 120, do: :quarterly
  defp interval_to_frequency(avg) when avg < 270, do: :semi_annual
  defp interval_to_frequency(avg) when avg >= 270, do: :annual
  defp interval_to_frequency(_), do: :unknown

  defp symbol_est_monthly(projected_annual) do
    projected_annual
    |> Decimal.div(Decimal.new(12))
    |> Decimal.round(2)
  end

  defp symbol_ytd_paid(divs_with_income) do
    today = Date.utc_today()
    year_start = Date.new!(today.year, 1, 1)

    divs_with_income
    |> Enum.filter(fn e ->
      Date.compare(e.dividend.ex_date, year_start) != :lt and
        Date.compare(e.dividend.ex_date, today) != :gt
    end)
    |> Enum.reduce(Decimal.new("0"), fn e, acc -> Decimal.add(acc, e.income) end)
  end

  defp symbol_est_remaining(projected_annual, ytd_paid) do
    Decimal.sub(projected_annual, ytd_paid)
    |> Decimal.max(Decimal.new("0"))
    |> Decimal.round(2)
  end

  defp symbol_yield_on_cost(_annual_per_share, nil), do: nil

  defp symbol_yield_on_cost(annual_per_share, pos) do
    avg_cost = pos.cost_price

    if avg_cost && Decimal.compare(avg_cost, Decimal.new("0")) == :gt do
      annual_per_share
      |> Decimal.div(avg_cost)
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.round(2)
    else
      nil
    end
  end

  defp symbol_projected_annual(_annual_per_share, nil), do: Decimal.new("0")

  defp symbol_projected_annual(annual_per_share, pos) do
    qty = pos.quantity || Decimal.new("0")

    if Decimal.compare(qty, Decimal.new("0")) == :gt do
      fx = pos.fx_rate || Decimal.new("1")
      annual_per_share |> Decimal.mult(qty) |> Decimal.mult(fx)
    else
      Decimal.new("0")
    end
  end

  defp symbol_rule72(nil), do: nil

  defp symbol_rule72(yield_on_cost) do
    if Decimal.compare(yield_on_cost, Decimal.new("0")) == :gt do
      DividendAnalytics.compute_rule72(Decimal.to_float(yield_on_cost))
    else
      nil
    end
  end

  ## FX Exposure

  @doc """
  Computes FX exposure breakdown from positions.
  """
  def compute_fx_exposure(positions) do
    total_eur =
      Enum.reduce(positions, Decimal.new("0"), fn p, acc ->
        fx = p.fx_rate || Decimal.new("1")
        Decimal.add(acc, Decimal.mult(p.value || Decimal.new("0"), fx))
      end)

    positions
    |> Enum.group_by(& &1.currency)
    |> Enum.map(fn {currency, group} -> build_currency_group(currency, group, total_eur) end)
    |> Enum.sort_by(fn e -> Decimal.to_float(e.eur_value) end, :desc)
  end

  defp build_currency_group(currency, group, total_eur) do
    local_value =
      Enum.reduce(group, Decimal.new("0"), fn p, acc ->
        Decimal.add(acc, p.value || Decimal.new("0"))
      end)

    eur_value =
      Enum.reduce(group, Decimal.new("0"), fn p, acc ->
        fx = p.fx_rate || Decimal.new("1")
        Decimal.add(acc, Decimal.mult(p.value || Decimal.new("0"), fx))
      end)

    %{
      currency: currency || "EUR",
      holdings_count: length(group),
      local_value: local_value,
      eur_value: eur_value,
      fx_rate: weighted_fx_rate(local_value, eur_value, hd(group)),
      pct: decimal_pct(eur_value, total_eur)
    }
  end

  defp weighted_fx_rate(local_value, eur_value, fallback_position) do
    if Decimal.compare(local_value, Decimal.new("0")) != :eq,
      do: eur_value |> Decimal.div(local_value) |> Decimal.round(4),
      else: fallback_position.fx_rate || Decimal.new("1")
  end

  defp decimal_pct(value, total) do
    if Decimal.compare(total, Decimal.new("0")) == :gt,
      do: value |> Decimal.div(total) |> Decimal.mult(Decimal.new("100")) |> Decimal.round(1),
      else: Decimal.new("0")
  end

  ## Dividend Cash Flow

  @doc """
  Returns YTD monthly dividend income with cumulative totals.
  """
  def dividend_cash_flow_summary do
    today = Date.utc_today()
    year_start = Date.new!(today.year, 1, 1)

    months = dividends_by_month(year_start, today)

    {entries, _} =
      Enum.map_reduce(months, Decimal.new("0"), fn %{month: month, total: total}, acc ->
        cumulative = Decimal.add(acc, total)
        {%{month: month, income: total, cumulative: cumulative}, cumulative}
      end)

    entries
  end

  ## Sold Positions (What-If Analysis)

  def list_sold_positions do
    SoldPosition
    |> order_by([s], desc: s.sale_date)
    |> Repo.all()
  end

  def list_sold_positions_grouped do
    SoldPosition
    |> group_by([s], s.symbol)
    |> select([s], %{
      symbol: s.symbol,
      trades: count(s.id),
      total_quantity: sum(s.quantity),
      total_pnl: sum(fragment("COALESCE(?, ?)", s.realized_pnl_eur, s.realized_pnl)),
      first_date: min(s.purchase_date),
      last_date: max(s.sale_date)
    })
    |> order_by([s], desc: sum(fragment("COALESCE(?, ?)", s.realized_pnl_eur, s.realized_pnl)))
    |> Repo.all()
  end

  def count_sold_positions do
    Repo.aggregate(SoldPosition, :count)
  end

  def list_sold_positions_by_symbol(symbol) do
    SoldPosition
    |> where([s], s.symbol == ^symbol)
    |> order_by([s], desc: s.sale_date)
    |> Repo.all()
  end

  def create_sold_position(attrs) do
    %SoldPosition{}
    |> SoldPosition.changeset(attrs)
    |> Repo.insert()
  end

  def update_sold_position(%SoldPosition{} = sold_position, attrs) do
    sold_position
    |> SoldPosition.changeset(attrs)
    |> Repo.update()
  end

  def delete_sold_position(%SoldPosition{} = sold_position) do
    Repo.delete(sold_position)
  end

  def get_sold_position(id) do
    Repo.get(SoldPosition, id)
  end

  def total_realized_pnl do
    SoldPosition
    |> select([s], sum(fragment("COALESCE(?, ?)", s.realized_pnl_eur, s.realized_pnl)))
    |> Repo.one() || Decimal.new("0")
  end

  def total_realized_pnl(year) when is_integer(year) do
    SoldPosition
    |> where([s], fragment("EXTRACT(YEAR FROM ?)::integer = ?", s.sale_date, ^year))
    |> select([s], sum(fragment("COALESCE(?, ?)", s.realized_pnl_eur, s.realized_pnl)))
    |> Repo.one() || Decimal.new("0")
  end

  def realized_pnl_summary(opts \\ []) do
    year = Keyword.get(opts, :year)

    base =
      if year,
        do:
          where(
            SoldPosition,
            [s],
            fragment("EXTRACT(YEAR FROM ?)::integer = ?", s.sale_date, ^year)
          ),
        else: SoldPosition

    grouped =
      base
      |> group_by([s], s.symbol)
      |> select([s], %{
        symbol: s.symbol,
        trades: count(s.id),
        total_quantity: sum(s.quantity),
        total_pnl: sum(fragment("COALESCE(?, ?)", s.realized_pnl_eur, s.realized_pnl)),
        first_date: min(s.purchase_date),
        last_date: max(s.sale_date)
      })
      |> Repo.all()

    zero = Decimal.new("0")

    total_pnl =
      Enum.reduce(grouped, zero, fn g, acc ->
        Decimal.add(acc, g.total_pnl || zero)
      end)

    total_trades = Enum.reduce(grouped, 0, fn g, acc -> acc + g.trades end)
    winners = Enum.filter(grouped, fn g -> Decimal.positive?(g.total_pnl) end)
    losers = Enum.filter(grouped, fn g -> not Decimal.positive?(g.total_pnl) end)

    total_gains =
      Enum.reduce(winners, zero, fn g, acc -> Decimal.add(acc, g.total_pnl) end)

    total_losses =
      Enum.reduce(losers, zero, fn g, acc -> Decimal.add(acc, g.total_pnl) end)

    sorted = Enum.sort_by(grouped, & &1.total_pnl, {:desc, Decimal})
    top_winners = Enum.take(sorted, 10)
    top_losers = sorted |> Enum.reverse() |> Enum.take(10) |> Enum.reverse()

    has_unconverted =
      Repo.exists?(
        from s in base,
          where: is_nil(s.realized_pnl_eur) and s.currency != "EUR"
      )

    %{
      total_pnl: total_pnl,
      total_trades: total_trades,
      symbol_count: length(grouped),
      total_gains: total_gains,
      total_losses: total_losses,
      win_count: length(winners),
      loss_count: length(losers),
      top_winners: top_winners,
      top_losers: top_losers,
      all_grouped: sorted,
      available_years: list_sale_years(),
      has_unconverted: has_unconverted
    }
  end

  def list_sale_years do
    SoldPosition
    |> select([s], fragment("DISTINCT EXTRACT(YEAR FROM ?)::integer", s.sale_date))
    |> order_by([s], fragment("1 DESC"))
    |> Repo.all()
  end

  def what_if_value(current_prices) when is_map(current_prices) do
    list_sold_positions()
    |> Enum.reduce(Decimal.new("0"), fn sold, acc ->
      current_price = Map.get(current_prices, sold.symbol)

      if current_price do
        value = Decimal.mult(sold.quantity, current_price)
        Decimal.add(acc, value)
      else
        acc
      end
    end)
  end

  def what_if_opportunity_cost(current_prices) when is_map(current_prices) do
    list_sold_positions()
    |> Enum.reduce(Decimal.new("0"), fn sold, acc ->
      current_price = Map.get(current_prices, sold.symbol)

      if current_price do
        sale_proceeds = Decimal.mult(sold.quantity, sold.sale_price)
        hypothetical_value = Decimal.mult(sold.quantity, current_price)
        opportunity = Decimal.sub(sale_proceeds, hypothetical_value)
        Decimal.add(acc, opportunity)
      else
        acc
      end
    end)
  end

  def get_what_if_summary(current_prices \\ %{}) do
    sold_positions = list_sold_positions()

    %{
      sold_positions_count: length(sold_positions),
      total_realized_pnl: total_realized_pnl(),
      hypothetical_value: what_if_value(current_prices),
      opportunity_cost: what_if_opportunity_cost(current_prices)
    }
  end

  ## Broker Transactions

  @doc """
  Imports trades from a Flex Trades CSV string.

  Deduplicates by broker+external_id (upsert with on_conflict: :nothing).
  Returns `{:ok, %{imported: n, skipped: n}}`.
  """
  def import_flex_trades_csv(csv_string) do
    alias Dividendsomatic.Portfolio.FlexTradesCsvParser

    case FlexTradesCsvParser.parse(csv_string) do
      {:ok, transactions} ->
        results = Enum.map(transactions, &upsert_flex_trade/1)
        imported = Enum.count(results, &match?({:ok, _}, &1))
        skipped = Enum.count(results, &match?(:skipped, &1))
        {:ok, %{imported: imported, skipped: skipped}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upsert_flex_trade(attrs) do
    if trade_exists?(attrs) do
      :skipped
    else
      upsert_broker_transaction(attrs)
    end
  end

  defp trade_exists?(%{isin: isin, trade_date: date, transaction_type: type})
       when is_binary(isin) and isin != "" and not is_nil(date) do
    BrokerTransaction
    |> where([t], t.isin == ^isin and t.trade_date == ^date and t.transaction_type == ^type)
    |> Repo.exists?()
  end

  defp trade_exists?(_), do: false

  def create_broker_transaction(attrs) do
    %BrokerTransaction{}
    |> BrokerTransaction.changeset(attrs)
    |> Repo.insert()
  end

  def upsert_broker_transaction(attrs) do
    %BrokerTransaction{}
    |> BrokerTransaction.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:broker, :external_id])
  end

  def list_broker_transactions(opts \\ []) do
    query = BrokerTransaction |> order_by([t], desc: t.trade_date)

    query =
      case Keyword.get(opts, :broker) do
        nil -> query
        broker -> where(query, [t], t.broker == ^broker)
      end

    query =
      case Keyword.get(opts, :type) do
        nil -> query
        type -> where(query, [t], t.transaction_type == ^type)
      end

    query =
      case Keyword.get(opts, :isin) do
        nil -> query
        isin -> where(query, [t], t.isin == ^isin)
      end

    Repo.all(query)
  end

  ## Dividend Diagnostics

  @doc """
  Diagnostic function for verifying dividend totals.
  Run in IEx: `Dividendsomatic.Portfolio.diagnose_dividends()`

  Returns:
  - ISIN-based duplicates (same ISIN + ex_date, different symbols)
  - Zero-income dividends (no matching position found)
  - Top 20 income records by value
  - Yearly totals
  """
  def diagnose_dividends do
    all_dividends = Dividend |> order_by([d], asc: d.ex_date) |> Repo.all()

    first_date =
      case all_dividends do
        [first | _] -> first.ex_date
        [] -> Date.utc_today()
      end

    last_date =
      case all_dividends do
        [] -> Date.utc_today()
        divs -> List.last(divs).ex_date
      end

    positions_map = build_positions_map(first_date, last_date)

    # ISIN-based duplicates: same ISIN + same ex_date, different symbols
    isin_dupes =
      all_dividends
      |> Enum.filter(& &1.isin)
      |> Enum.group_by(fn d -> {d.isin, d.ex_date} end)
      |> Enum.filter(fn {_key, divs} -> length(divs) > 1 end)
      |> Enum.map(fn {{isin, date}, divs} ->
        symbols = Enum.map(divs, & &1.symbol) |> Enum.uniq()
        %{isin: isin, ex_date: date, symbols: symbols, count: length(divs)}
      end)

    # Zero-income dividends
    zero_income =
      all_dividends
      |> Enum.map(fn div ->
        income = compute_dividend_income(div, positions_map)

        %{
          symbol: div.symbol,
          isin: div.isin,
          ex_date: div.ex_date,
          amount: div.amount,
          income: income
        }
      end)
      |> Enum.filter(fn entry -> Decimal.compare(entry.income, Decimal.new("0")) == :eq end)

    # Top 20 income records
    top_20 =
      all_dividends
      |> Enum.map(fn div ->
        income = compute_dividend_income(div, positions_map)

        %{
          symbol: div.symbol,
          isin: div.isin,
          ex_date: div.ex_date,
          amount: div.amount,
          income: income
        }
      end)
      |> Enum.sort_by(fn e -> Decimal.to_float(e.income) end, :desc)
      |> Enum.take(20)

    # Yearly totals
    years = dividend_years()

    yearly_totals =
      Enum.map(years, fn year ->
        total = total_dividends_for_year(year)
        %{year: year, total: total}
      end)

    grand_total =
      Enum.reduce(yearly_totals, Decimal.new("0"), fn %{year: _y, total: t}, acc ->
        Decimal.add(acc, t)
      end)

    %{
      total_dividends: length(all_dividends),
      isin_duplicates: isin_dupes,
      zero_income_count: length(zero_income),
      zero_income: Enum.take(zero_income, 20),
      top_20_income: top_20,
      yearly_totals: yearly_totals,
      grand_total: grand_total
    }
  end

  ## Costs

  @doc """
  Returns total costs for a specific year.
  """
  def total_costs_for_year(year) do
    year_start = Date.new!(year, 1, 1)

    year_end =
      if year == Date.utc_today().year, do: Date.utc_today(), else: Date.new!(year, 12, 31)

    Cost
    |> where([c], c.date >= ^year_start and c.date <= ^year_end)
    |> Repo.aggregate(:sum, :amount) || Decimal.new("0")
  end

  def create_cost(attrs) do
    %Cost{}
    |> Cost.changeset(attrs)
    |> Repo.insert()
  end

  def list_costs do
    Cost
    |> order_by([c], desc: c.date)
    |> Repo.all()
  end

  def list_costs_by_type(cost_type) do
    Cost
    |> where([c], c.cost_type == ^cost_type)
    |> order_by([c], desc: c.date)
    |> Repo.all()
  end

  def list_costs_by_symbol(symbol) do
    Cost
    |> where([c], c.symbol == ^symbol)
    |> order_by([c], desc: c.date)
    |> Repo.all()
  end

  def total_costs_by_type do
    Cost
    |> group_by([c], c.cost_type)
    |> select([c], {c.cost_type, sum(c.amount)})
    |> Repo.all()
    |> Map.new()
  end

  def costs_summary do
    by_type = total_costs_by_type()

    total =
      by_type
      |> Map.values()
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

    %{by_type: by_type, total: total, count: Repo.aggregate(Cost, :count)}
  end

  ## Investment Summary

  @doc """
  Returns total deposits and withdrawals from broker transactions.
  Amounts are converted to EUR using exchange_rate when available.
  """
  def total_deposits_withdrawals do
    zero = Decimal.new("0")

    results =
      BrokerTransaction
      |> where([t], t.transaction_type in ["deposit", "withdrawal"])
      |> select([t], %{
        transaction_type: t.transaction_type,
        amount: t.amount,
        exchange_rate: t.exchange_rate
      })
      |> Repo.all()

    {deposits, withdrawals} =
      Enum.reduce(results, {zero, zero}, fn txn, {dep_acc, wd_acc} ->
        amt = txn.amount || zero
        fx = txn.exchange_rate || Decimal.new("1")
        eur_amt = Decimal.mult(Decimal.abs(amt), fx)

        case txn.transaction_type do
          "deposit" -> {Decimal.add(dep_acc, eur_amt), wd_acc}
          "withdrawal" -> {dep_acc, Decimal.add(wd_acc, eur_amt)}
          _ -> {dep_acc, wd_acc}
        end
      end)

    %{
      deposits: deposits,
      withdrawals: withdrawals,
      net_invested: Decimal.sub(deposits, withdrawals)
    }
  end

  @doc """
  Returns a comprehensive investment summary combining deposits, costs, P&L, and dividends.
  """
  def investment_summary do
    zero = Decimal.new("0")
    dw = total_deposits_withdrawals()
    costs = costs_summary()
    realized_pnl = total_realized_pnl()

    total_dividends =
      dividend_years()
      |> Enum.reduce(zero, fn year, acc ->
        Decimal.add(acc, total_dividends_for_year(year))
      end)

    net_profit =
      realized_pnl
      |> Decimal.add(total_dividends)
      |> Decimal.sub(costs.total)

    %{
      total_deposits: dw.deposits,
      total_withdrawals: dw.withdrawals,
      net_invested: dw.net_invested,
      total_costs: costs.total,
      realized_pnl: realized_pnl,
      total_dividends: total_dividends,
      net_profit: net_profit
    }
  end

  ## Waterfall Chart Data

  @doc """
  Returns monthly waterfall data combining deposits, withdrawals, dividends, costs, and realized P&L.
  Each entry: `%{month: "YYYY-MM", deposits: Decimal, withdrawals: Decimal, dividends: Decimal, costs: Decimal, realized_pnl: Decimal}`
  """
  def waterfall_data do
    zero = Decimal.new("0")

    # Get full date range from snapshots
    first = get_first_snapshot()
    latest = get_latest_snapshot()

    case {first, latest} do
      {nil, _} ->
        []

      {_, nil} ->
        []

      {f, l} ->
        from_date = f.date
        to_date = l.date

        # Dividends by month (reuse existing function)
        div_months =
          dividends_by_month(from_date, to_date) |> Map.new(fn d -> {d.month, d.total} end)

        # Costs by month
        cost_months = costs_by_month(from_date, to_date)

        # Deposits/withdrawals by month
        dw_months = deposits_withdrawals_by_month(from_date, to_date)

        # Realized P&L by month
        pnl_months = realized_pnl_by_month(from_date, to_date)

        # Build list of all months
        all_months =
          [Map.keys(div_months), Map.keys(cost_months), Map.keys(dw_months), Map.keys(pnl_months)]
          |> List.flatten()
          |> Enum.uniq()
          |> Enum.sort()

        Enum.map(all_months, fn month ->
          %{
            month: month,
            deposits: Map.get(dw_months, month, %{deposits: zero, withdrawals: zero}).deposits,
            withdrawals:
              Map.get(dw_months, month, %{deposits: zero, withdrawals: zero}).withdrawals,
            dividends: Map.get(div_months, month, zero),
            costs: Map.get(cost_months, month, zero),
            realized_pnl: Map.get(pnl_months, month, zero)
          }
        end)
    end
  end

  @doc """
  Returns costs grouped by month for a date range.
  """
  def costs_by_month(from_date, to_date) do
    Cost
    |> where([c], c.date >= ^from_date and c.date <= ^to_date)
    |> group_by([c], fragment("to_char(?, 'YYYY-MM')", c.date))
    |> select([c], {fragment("to_char(?, 'YYYY-MM')", c.date), sum(c.amount)})
    |> Repo.all()
    |> Map.new()
  end

  defp deposits_withdrawals_by_month(from_date, to_date) do
    BrokerTransaction
    |> where([t], t.transaction_type in ["deposit", "withdrawal"])
    |> where([t], t.trade_date >= ^from_date and t.trade_date <= ^to_date)
    |> select([t], %{
      month: fragment("to_char(?, 'YYYY-MM')", t.trade_date),
      transaction_type: t.transaction_type,
      amount: t.amount,
      exchange_rate: t.exchange_rate
    })
    |> Repo.all()
    |> Enum.group_by(& &1.month)
    |> Map.new(fn {month, txns} ->
      {month, sum_dw_transactions(txns)}
    end)
  end

  defp sum_dw_transactions(txns) do
    zero = Decimal.new("0")

    {deposits, withdrawals} =
      Enum.reduce(txns, {zero, zero}, fn txn, {dep, wd} ->
        amt = Decimal.abs(txn.amount || zero)
        fx = txn.exchange_rate || Decimal.new("1")
        eur_amt = Decimal.mult(amt, fx)

        case txn.transaction_type do
          "deposit" -> {Decimal.add(dep, eur_amt), wd}
          "withdrawal" -> {dep, Decimal.add(wd, eur_amt)}
          _ -> {dep, wd}
        end
      end)

    %{deposits: deposits, withdrawals: withdrawals}
  end

  defp realized_pnl_by_month(from_date, to_date) do
    SoldPosition
    |> where([s], s.sale_date >= ^from_date and s.sale_date <= ^to_date)
    |> group_by([s], fragment("to_char(?, 'YYYY-MM')", s.sale_date))
    |> select([s], {
      fragment("to_char(?, 'YYYY-MM')", s.sale_date),
      sum(fragment("COALESCE(?, ?)", s.realized_pnl_eur, s.realized_pnl))
    })
    |> Repo.all()
    |> Map.new()
  end

  ## Data Gaps Analysis

  def broker_coverage do
    nordnet_range =
      BrokerTransaction
      |> where([t], t.broker == "nordnet")
      |> select([t], %{min_date: min(t.trade_date), max_date: max(t.trade_date), count: count()})
      |> Repo.one()

    ibkr_snapshot_range =
      PortfolioSnapshot
      |> select([s], %{
        min_date: min(s.date),
        max_date: max(s.date),
        count: count()
      })
      |> Repo.one()

    ibkr_txn_range =
      BrokerTransaction
      |> where([t], t.broker == "ibkr")
      |> select([t], %{min_date: min(t.trade_date), max_date: max(t.trade_date), count: count()})
      |> Repo.one()

    %{nordnet: nordnet_range, ibkr: ibkr_snapshot_range, ibkr_txns: ibkr_txn_range}
  end

  def stock_gaps(opts \\ []) do
    current_only = Keyword.get(opts, :current_only, false)

    nordnet_stocks = fetch_nordnet_stock_ranges()
    ibkr_stocks = fetch_ibkr_stock_ranges()
    current_isins = if current_only, do: current_position_isins(), else: nil

    gaps = merge_stock_gaps(nordnet_stocks, ibkr_stocks)

    if current_isins do
      Enum.filter(gaps, fn g -> MapSet.member?(current_isins, g.isin) end)
    else
      gaps
    end
  end

  defp fetch_nordnet_stock_ranges do
    BrokerTransaction
    |> where([t], t.broker == "nordnet" and not is_nil(t.isin))
    |> where([t], fragment("length(?) >= 12", t.isin))
    |> group_by([t], [t.isin, t.security_name])
    |> select([t], %{
      isin: t.isin,
      name: t.security_name,
      first_date: min(t.trade_date),
      last_date: max(t.trade_date),
      broker: "nordnet"
    })
    |> Repo.all()
  end

  defp fetch_ibkr_stock_ranges do
    Position
    |> where([p], not is_nil(p.isin))
    |> where([p], fragment("length(?) >= 12", p.isin))
    |> group_by([p], [p.isin, p.symbol, p.name])
    |> select([p], %{
      isin: p.isin,
      symbol: p.symbol,
      name: p.name,
      first_date: min(p.date),
      last_date: max(p.date),
      broker: "ibkr"
    })
    |> Repo.all()
  end

  defp current_position_isins do
    case get_latest_snapshot() do
      nil ->
        MapSet.new()

      snapshot ->
        snapshot.positions
        |> Enum.map(& &1.isin)
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()
    end
  end

  defp merge_stock_gaps(nordnet_stocks, ibkr_stocks) do
    all_isins =
      (Enum.map(nordnet_stocks, & &1.isin) ++ Enum.map(ibkr_stocks, & &1.isin))
      |> Enum.uniq()

    nordnet_map = Map.new(nordnet_stocks, &{&1.isin, &1})
    ibkr_map = Map.new(ibkr_stocks, &{&1.isin, &1})

    all_isins
    |> Enum.map(fn isin ->
      nordnet = Map.get(nordnet_map, isin)
      ibkr = Map.get(ibkr_map, isin)
      name = (ibkr && ibkr.name) || (nordnet && nordnet.name) || "Unknown"
      symbol = (ibkr && Map.get(ibkr, :symbol)) || name
      gap_days = compute_gap_days(nordnet, ibkr)

      %{
        isin: isin,
        name: name,
        symbol: symbol,
        nordnet: nordnet,
        ibkr: ibkr,
        gap_days: gap_days,
        has_gap: gap_days > 0,
        brokers: brokers_list(nordnet, ibkr)
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp compute_gap_days(nil, _ibkr), do: 0
  defp compute_gap_days(_nordnet, nil), do: 0

  defp compute_gap_days(nordnet, ibkr) do
    gap = Date.diff(ibkr.first_date, nordnet.last_date)
    max(gap, 0)
  end

  defp brokers_list(nordnet, ibkr) do
    []
    |> then(fn l -> if nordnet, do: ["nordnet" | l], else: l end)
    |> then(fn l -> if ibkr, do: ["ibkr" | l], else: l end)
  end

  def dividend_gaps do
    dividends =
      Dividend
      |> order_by([d], asc: d.ex_date)
      |> Repo.all()

    dividends
    |> Enum.group_by(fn d -> d.isin || d.symbol end)
    |> Enum.map(fn {key, divs} ->
      sorted = Enum.sort_by(divs, & &1.ex_date, Date)

      gaps =
        sorted
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.filter(fn [a, b] -> Date.diff(b.ex_date, a.ex_date) > 400 end)
        |> Enum.map(fn [a, b] ->
          %{from: a.ex_date, to: b.ex_date, days: Date.diff(b.ex_date, a.ex_date)}
        end)

      %{
        key: key,
        symbol: hd(sorted).symbol,
        first_dividend: hd(sorted).ex_date,
        last_dividend: List.last(sorted).ex_date,
        count: length(sorted),
        gaps: gaps
      }
    end)
    |> Enum.filter(fn d -> d.gaps != [] end)
    |> Enum.sort_by(& &1.symbol)
  end
end
