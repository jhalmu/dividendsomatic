defmodule Dividendsomatic.Portfolio do
  @moduledoc """
  Portfolio context for managing snapshots and positions.
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.{
    CashFlow,
    CsvParser,
    DividendAnalytics,
    DividendPayment,
    FxRate,
    Instrument,
    InstrumentAlias,
    MarginEquitySnapshot,
    MarginRates,
    PortfolioSnapshot,
    Position,
    SoldPosition,
    Trade
  }

  alias Dividendsomatic.Repo

  ## Persistent Term Cache
  # Historical portfolio data is immutable after import — safe to cache indefinitely.
  # Invalidated only on import via invalidate_cache/0.

  @portfolio_cache_keys [
    :portfolio_all_chart_data,
    :portfolio_first_snapshot,
    :portfolio_snapshot_count,
    :portfolio_costs_summary
  ]

  defp cached(key, compute_fn) do
    case :persistent_term.get(key, nil) do
      nil ->
        value = compute_fn.()
        :persistent_term.put(key, value)
        value

      value ->
        value
    end
  end

  defp cached_by_year(base_key, year, compute_fn) do
    key = {base_key, year}
    if year < Date.utc_today().year, do: cached(key, compute_fn), else: compute_fn.()
  end

  @doc """
  Invalidates all portfolio caches. Call after any import that changes snapshot/cost data.
  """
  def invalidate_cache do
    Enum.each(@portfolio_cache_keys, &safe_erase/1)

    Enum.each(2017..Date.utc_today().year, fn year ->
      safe_erase({:portfolio_costs_for_year, year})
    end)

    :ok
  end

  defp safe_erase(key) do
    :persistent_term.erase(key)
  rescue
    ArgumentError -> :ok
  end

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
    cached(:portfolio_all_chart_data, fn ->
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
    end)
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
    cached(:portfolio_first_snapshot, fn ->
      PortfolioSnapshot
      |> order_by([s], asc: s.date)
      |> limit(1)
      |> preload(:positions)
      |> Repo.one()
    end)
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
    cached(:portfolio_snapshot_count, fn ->
      Repo.aggregate(PortfolioSnapshot, :count)
    end)
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
    result =
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

    if match?({:ok, _}, result), do: invalidate_cache()
    result
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

  ## Dividends — powered by dividend_payments + instruments tables

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
  Lists all dividends ordered by pay_date descending.
  Returns maps compatible with legacy Dividend shape.
  """
  def list_dividends do
    DividendPayment
    |> order_by([d], desc: d.pay_date)
    |> preload(instrument: :aliases)
    |> Repo.all()
    |> adapt_payments_to_dividends()
  end

  @doc """
  Lists dividends for a specific symbol.
  Looks up instrument via aliases, returns adapted maps.
  """
  def list_dividends_by_symbol(symbol) do
    instrument_ids =
      InstrumentAlias
      |> where([a], a.symbol == ^symbol)
      |> select([a], a.instrument_id)
      |> Repo.all()

    case instrument_ids do
      [] ->
        []

      ids ->
        DividendPayment
        |> where([d], d.instrument_id in ^ids)
        |> order_by([d], desc: d.pay_date)
        |> preload(instrument: :aliases)
        |> Repo.all()
        |> adapt_payments_to_dividends()
    end
  end

  @doc """
  Lists dividends for the current year.
  """
  def list_dividends_this_year do
    year_start = Date.new!(Date.utc_today().year, 1, 1)

    DividendPayment
    |> where([d], d.pay_date >= ^year_start)
    |> order_by([d], desc: d.pay_date)
    |> preload(instrument: :aliases)
    |> Repo.all()
    |> adapt_payments_to_dividends()
  end

  @doc """
  Lists dividends for the current year with computed income.
  With dividend_payments, net_amount is already the income per event.
  """
  def list_dividends_with_income do
    year_start = Date.new!(Date.utc_today().year, 1, 1)
    today = Date.utc_today()

    dividends = load_dividends_in_range(year_start, today)
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
  Gets total dividend income for the current year (base currency EUR).
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
    DividendPayment
    |> where([d], not is_nil(d.pay_date))
    |> select([d], fragment("DISTINCT EXTRACT(YEAR FROM ?)::integer", d.pay_date))
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
    dividends = load_dividends_in_range(from_date, to_date)
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
        {snapshot.date, p.symbol, p.quantity, p.fx_rate, p.currency, p.isin}
      end)
    end)
  end

  defp compute_dividend_income(dividend, positions_data) do
    amount = dividend.amount || Decimal.new("0")

    # Find matching position for fx_rate and quantity
    matching = find_matching_position(dividend, positions_data)

    {matched_qty, holding_fx, holding_currency} =
      case matching do
        {_date, _symbol, quantity, fx_rate, currency, _isin} ->
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
    div_isin = Map.get(dividend, :isin)

    # Match by ISIN first, then by symbol; within -7..+45 days of ex_date
    Enum.filter(positions_data, fn {date, symbol, _qty, _fx, _cur, isin} ->
      matches =
        (div_isin && isin && div_isin == isin) || symbol == dividend.symbol

      if matches do
        diff = Date.diff(dividend.ex_date, date)
        diff >= -7 and diff <= 45
      end
    end)
    |> Enum.min_by(
      fn {date, _, _, _, _, _} -> abs(Date.diff(date, dividend.ex_date)) end,
      fn -> nil end
    )
  end

  @doc """
  Gets a dividend payment by ID with preloaded instrument.
  """
  def get_dividend(id) do
    DividendPayment
    |> preload(instrument: :aliases)
    |> Repo.get(id)
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

    # Per-symbol yield needs TTM data (365 days), not just the year range
    ttm_start = Date.add(today, -365)
    full_from = Enum.min([widest_from, ttm_start], Date)

    positions_map = build_positions_map(full_from, widest_to)
    all_dividends = load_dividends_in_range(full_from, widest_to)

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
    DividendPayment
    |> where([d], d.pay_date >= ^from and d.pay_date <= ^to)
    |> order_by([d], asc: d.pay_date)
    |> preload(instrument: :aliases)
    |> Repo.all()
    |> adapt_payments_to_dividends()
  end

  # Adapts DividendPayment records to maps compatible with the old Dividend shape.
  # This lets existing computation logic (compute_dividend_income, per_share_amount, etc.)
  # work unchanged with the new table data.
  defp adapt_payments_to_dividends(payments) do
    Enum.map(payments, fn payment ->
      symbol = payment_symbol(payment)

      %{
        symbol: symbol,
        isin: payment.instrument.isin,
        ex_date: payment.pay_date,
        pay_date: payment.pay_date,
        amount: payment.net_amount,
        amount_type: "total_net",
        currency: payment.currency,
        fx_rate: payment.fx_rate,
        per_share: payment.per_share,
        gross_rate: payment.per_share,
        gross_amount: payment.gross_amount,
        withholding_tax: payment.withholding_tax,
        net_amount: payment.net_amount,
        quantity_at_record: payment.quantity,
        description: payment.description
      }
    end)
  end

  defp payment_symbol(payment) do
    payment.instrument.symbol ||
      case payment.instrument.aliases do
        [alias_record | _] -> alias_record.symbol
        [] -> payment.instrument.name
      end
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
    instrument_div_map = build_instrument_dividend_map()

    # ISIN-to-position-symbol map for cross-matching when adapted symbol differs
    isin_to_pos_symbol =
      positions
      |> Enum.filter(& &1.isin)
      |> Map.new(fn p -> {p.isin, p.symbol} end)

    # Resolve each dividend to the position symbol (by symbol or ISIN fallback)
    divs_by_symbol =
      all_dividends
      |> Enum.map(fn d ->
        pos_symbol =
          if MapSet.member?(current_symbols, d.symbol) do
            d.symbol
          else
            Map.get(isin_to_pos_symbol, d.isin)
          end

        {pos_symbol, d}
      end)
      |> Enum.reject(fn {pos_symbol, _d} -> is_nil(pos_symbol) end)
      |> Enum.group_by(fn {pos_symbol, _d} -> pos_symbol end, fn {_ps, d} -> d end)

    pos_map = Map.new(positions, fn p -> {p.symbol, p} end)

    Map.new(divs_by_symbol, fn {symbol, divs} ->
      pos = Map.get(pos_map, symbol)
      divs_with_income = build_divs_with_income(divs, positions_map)
      {symbol, build_symbol_dividend_data(divs_with_income, divs, pos, instrument_div_map)}
    end)
  end

  defp build_divs_with_income(divs, positions_map) do
    Enum.map(divs, fn div ->
      %{dividend: div, income: compute_dividend_income(div, positions_map)}
    end)
  end

  defp build_symbol_dividend_data(divs_with_income, raw_divs, pos, instrument_div_map) do
    # Enrich total_net dividends that lack per_share: derive from net_amount / position qty
    enriched = enrich_missing_per_share(divs_with_income, pos)
    detected = detect_payment_frequency(raw_divs)

    # Fall back to stored instrument frequency when detection can't determine it
    frequency =
      if detected == :unknown do
        isin = if pos, do: pos.isin, else: nil
        stored = if isin, do: get_in(instrument_div_map, [isin, :dividend_frequency])
        stored_to_frequency(stored) || :unknown
      else
        detected
      end

    {annual_per_share, source} =
      compute_best_annual_per_share(enriched, raw_divs, pos, instrument_div_map, frequency)

    div_fx_rate = latest_dividend_fx_rate(raw_divs)
    yield_on_cost = symbol_yield_on_cost(annual_per_share, pos, div_fx_rate)
    current_yield = symbol_current_yield(annual_per_share, pos, div_fx_rate)
    projected_annual = symbol_projected_annual(annual_per_share, pos, div_fx_rate)
    ytd_paid = symbol_ytd_paid(enriched)

    %{
      est_monthly: symbol_est_monthly(projected_annual),
      annual_per_share: annual_per_share,
      projected_annual: projected_annual,
      est_remaining: symbol_est_remaining(projected_annual, ytd_paid),
      yield_on_cost: yield_on_cost,
      current_yield: current_yield,
      rule72: symbol_rule72(yield_on_cost),
      payment_frequency: frequency,
      dividend_source: source
    }
  end

  defp compute_best_annual_per_share(enriched, _raw_divs, pos, instrument_div_map, frequency) do
    isin = if pos, do: pos.isin, else: nil
    instrument_data = if isin, do: Map.get(instrument_div_map, isin), else: nil

    stored_rate =
      if instrument_data, do: instrument_data.dividend_rate, else: nil

    stored_source =
      if instrument_data, do: instrument_data.dividend_source, else: nil

    has_stored_rate? =
      stored_rate && Decimal.compare(stored_rate, Decimal.new("0")) == :gt

    ttm = DividendAnalytics.compute_annual_dividend_per_share(enriched, frequency)

    ttm_source =
      if frequency in [:monthly, :quarterly, :semi_annual],
        do: "ttm_extrapolated",
        else: "ttm_sum"

    cond do
      # 1. Manual or TTM-computed stored rate — trusted, use immediately
      has_stored_rate? && stored_source in ["manual", "ttm_computed"] ->
        {stored_rate, stored_source}

      # 2. Yahoo rate with TTM available — check for divergence
      has_stored_rate? && Decimal.compare(ttm, Decimal.new("0")) == :gt ->
        if yahoo_ttm_diverges?(stored_rate, ttm) do
          {ttm, ttm_source}
        else
          {stored_rate, "declared"}
        end

      # 3. Yahoo rate, no TTM data
      has_stored_rate? ->
        {stored_rate, "declared"}

      # 4. No stored rate — TTM fallback
      true ->
        {ttm, ttm_source}
    end
  end

  defp yahoo_ttm_diverges?(yahoo_rate, ttm_rate) do
    ratio = Decimal.div(yahoo_rate, ttm_rate)

    Decimal.compare(ratio, Decimal.new("2")) == :gt ||
      Decimal.compare(ratio, Decimal.new("0.5")) == :lt
  end

  defp build_instrument_dividend_map do
    Instrument
    |> where([i], not is_nil(i.dividend_rate))
    |> select(
      [i],
      {i.isin,
       %{
         dividend_rate: i.dividend_rate,
         dividend_frequency: i.dividend_frequency,
         dividend_source: i.dividend_source
       }}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp detect_payment_frequency(divs) when length(divs) < 3, do: :unknown

  defp detect_payment_frequency(divs) do
    divs
    |> Enum.sort_by(& &1.ex_date, Date)
    |> Enum.map(& &1.ex_date)
    |> Enum.uniq()
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

  defp stored_to_frequency("monthly"), do: :monthly
  defp stored_to_frequency("quarterly"), do: :quarterly
  defp stored_to_frequency("semi_annual"), do: :semi_annual
  defp stored_to_frequency("annual"), do: :annual
  defp stored_to_frequency(_), do: nil

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

  # For total_net dividends where NO payment has per_share data, derive per_share
  # from net_amount / position quantity. Only enriches when ALL dividends lack per_share
  # to avoid double-counting when IBKR splits a dividend into multiple entries
  # (e.g., "Payment in Lieu" + regular dividend with per_share).
  defp enrich_missing_per_share(divs_with_income, nil), do: divs_with_income

  defp enrich_missing_per_share(divs_with_income, pos) do
    has_per_share =
      Enum.any?(divs_with_income, fn e ->
        d = e.dividend
        d[:gross_rate] && Decimal.compare(d.gross_rate, Decimal.new("0")) == :gt
      end)

    qty = pos.quantity

    if has_per_share || is_nil(qty) || Decimal.compare(qty, Decimal.new("0")) != :gt do
      divs_with_income
    else
      Enum.map(divs_with_income, fn entry ->
        d = entry.dividend

        if d.amount_type == "total_net" do
          derived = Decimal.div(d.amount || Decimal.new("0"), qty)
          %{entry | dividend: Map.put(d, :gross_rate, derived)}
        else
          entry
        end
      end)
    end
  end

  defp symbol_est_remaining(projected_annual, ytd_paid) do
    Decimal.sub(projected_annual, ytd_paid)
    |> Decimal.max(Decimal.new("0"))
    |> Decimal.round(2)
  end

  defp symbol_yield_on_cost(_annual_per_share, nil, _div_fx_rate), do: nil

  defp symbol_yield_on_cost(annual_per_share, pos, div_fx_rate) do
    avg_cost = pos.cost_price
    div_fx = div_fx_rate || pos.fx_rate || Decimal.new("1")
    pos_fx = pos.fx_rate || Decimal.new("1")

    if avg_cost && Decimal.compare(avg_cost, Decimal.new("0")) == :gt do
      # Normalize both to EUR: (annual * div_fx) / (cost * pos_fx)
      annual_per_share
      |> Decimal.mult(div_fx)
      |> Decimal.div(Decimal.mult(avg_cost, pos_fx))
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.round(2)
    else
      nil
    end
  end

  defp symbol_current_yield(_annual_per_share, nil, _div_fx_rate), do: nil

  defp symbol_current_yield(annual_per_share, pos, div_fx_rate) do
    market_price = pos.price
    div_fx = div_fx_rate || pos.fx_rate || Decimal.new("1")
    pos_fx = pos.fx_rate || Decimal.new("1")

    if market_price && Decimal.compare(market_price, Decimal.new("0")) == :gt do
      annual_per_share
      |> Decimal.mult(div_fx)
      |> Decimal.div(Decimal.mult(market_price, pos_fx))
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.round(2)
    else
      nil
    end
  end

  defp symbol_projected_annual(_annual_per_share, nil, _div_fx_rate), do: Decimal.new("0")

  defp symbol_projected_annual(annual_per_share, pos, div_fx_rate) do
    qty = pos.quantity || Decimal.new("0")

    if Decimal.compare(qty, Decimal.new("0")) == :gt do
      fx = div_fx_rate || pos.fx_rate || Decimal.new("1")
      annual_per_share |> Decimal.mult(qty) |> Decimal.mult(fx)
    else
      Decimal.new("0")
    end
  end

  defp latest_dividend_fx_rate(divs) do
    divs
    |> Enum.sort_by(& &1.ex_date, {:desc, Date})
    |> Enum.find_value(fn d -> d.fx_rate end)
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

  ## FX Rate Lookup

  @doc """
  Returns the FX rate for a currency on a given date (1 unit = rate EUR).

  - EUR always returns `Decimal.new("1")`
  - Looks up exact date first, then falls back to nearest preceding date
  - Returns `nil` if no rate found
  """
  def get_fx_rate("EUR", _date), do: Decimal.new("1")

  def get_fx_rate(currency, date) when is_binary(currency) do
    # Try exact date first, then nearest preceding
    FxRate
    |> where([f], f.currency == ^currency and f.date <= ^date)
    |> order_by([f], desc: f.date)
    |> limit(1)
    |> select([f], f.rate)
    |> Repo.one()
  end

  def get_fx_rate(_, _), do: nil

  @doc """
  Upserts an FX rate record. If a rate for the same date+currency exists, updates it.
  """
  def upsert_fx_rate(attrs) do
    %FxRate{}
    |> FxRate.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:rate, :source, :updated_at]},
      conflict_target: [:date, :currency]
    )
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

  ## Trades (from new trades table)

  def list_trades(opts \\ []) do
    query = Trade |> order_by([t], desc: t.trade_date)

    query =
      case Keyword.get(opts, :instrument_id) do
        nil -> query
        id -> where(query, [t], t.instrument_id == ^id)
      end

    query =
      case Keyword.get(opts, :currency) do
        nil -> query
        currency -> where(query, [t], t.currency == ^currency)
      end

    Repo.all(query)
  end

  ## Costs — now from cash_flows table (interest + fee)

  @doc """
  Returns total costs for a specific year (interest + fees from cash_flows).
  """
  def total_costs_for_year(year) do
    cached_by_year(:portfolio_costs_for_year, year, fn ->
      year_start = Date.new!(year, 1, 1)

      year_end =
        if year == Date.utc_today().year, do: Date.utc_today(), else: Date.new!(year, 12, 31)

      CashFlow
      |> where([c], c.flow_type in ["interest", "fee"])
      |> where([c], c.date >= ^year_start and c.date <= ^year_end)
      |> select([c], sum(fragment("ABS(COALESCE(?, ?))", c.amount_eur, c.amount)))
      |> Repo.one() || Decimal.new("0")
    end)
  end

  def list_costs do
    CashFlow
    |> where([c], c.flow_type in ["interest", "fee"])
    |> order_by([c], desc: c.date)
    |> Repo.all()
  end

  def list_costs_by_type(flow_type) do
    CashFlow
    |> where([c], c.flow_type == ^flow_type)
    |> order_by([c], desc: c.date)
    |> Repo.all()
  end

  def total_costs_by_type(opts \\ []) do
    query =
      CashFlow
      |> where([c], c.flow_type in ["interest", "fee"])

    query =
      case Keyword.get(opts, :source) do
        nil -> query
        source -> where(query, [c], c.source == ^source)
      end

    query
    |> group_by([c], c.flow_type)
    |> select([c], {c.flow_type, sum(fragment("ABS(COALESCE(?, ?))", c.amount_eur, c.amount))})
    |> Repo.all()
    |> Map.new()
  end

  def costs_summary do
    cached(:portfolio_costs_summary, fn ->
      by_type = total_costs_by_type()

      total =
        by_type
        |> Map.values()
        |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

      count =
        CashFlow
        |> where([c], c.flow_type in ["interest", "fee"])
        |> Repo.aggregate(:count)

      %{by_type: by_type, total: total, count: count}
    end)
  end

  ## Investment Summary

  @doc """
  Returns total deposits and withdrawals from cash_flows.

  Options:
    - `:source` — filter by source (e.g., "ibkr"). Default: all sources.
  """
  def total_deposits_withdrawals(opts \\ []) do
    zero = Decimal.new("0")

    query =
      CashFlow
      |> where([c], c.flow_type in ["deposit", "withdrawal"])

    query =
      case Keyword.get(opts, :source) do
        nil -> query
        source -> where(query, [c], c.source == ^source)
      end

    results =
      query
      |> select([c], %{flow_type: c.flow_type, amount: c.amount, amount_eur: c.amount_eur})
      |> Repo.all()

    {deposits, withdrawals} =
      Enum.reduce(results, {zero, zero}, fn cf, {dep_acc, wd_acc} ->
        amt = Decimal.abs(cf.amount_eur || cf.amount || zero)

        case cf.flow_type do
          "deposit" -> {Decimal.add(dep_acc, amt), wd_acc}
          "withdrawal" -> {dep_acc, Decimal.add(wd_acc, amt)}
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
  Returns costs grouped by month for a date range (interest + fees from cash_flows).
  """
  def costs_by_month(from_date, to_date) do
    CashFlow
    |> where([c], c.flow_type in ["interest", "fee"])
    |> where([c], c.date >= ^from_date and c.date <= ^to_date)
    |> group_by([c], fragment("to_char(?, 'YYYY-MM')", c.date))
    |> select([c], {fragment("to_char(?, 'YYYY-MM')", c.date), sum(fragment("ABS(?)", c.amount))})
    |> Repo.all()
    |> Map.new()
  end

  defp deposits_withdrawals_by_month(from_date, to_date) do
    zero = Decimal.new("0")

    CashFlow
    |> where([c], c.flow_type in ["deposit", "withdrawal"])
    |> where([c], c.date >= ^from_date and c.date <= ^to_date)
    |> select([c], %{
      month: fragment("to_char(?, 'YYYY-MM')", c.date),
      flow_type: c.flow_type,
      amount: c.amount
    })
    |> Repo.all()
    |> Enum.group_by(& &1.month)
    |> Map.new(fn {month, entries} ->
      {month, sum_deposits_withdrawals(entries, zero)}
    end)
  end

  defp sum_deposits_withdrawals(entries, zero) do
    {deposits, withdrawals} =
      Enum.reduce(entries, {zero, zero}, fn cf, {dep, wd} ->
        amt = Decimal.abs(cf.amount || zero)

        case cf.flow_type do
          "deposit" -> {Decimal.add(dep, amt), wd}
          "withdrawal" -> {dep, Decimal.add(wd, amt)}
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

  ## Data Coverage Analysis

  def broker_coverage do
    ibkr_snapshot_range =
      PortfolioSnapshot
      |> select([s], %{
        min_date: min(s.date),
        max_date: max(s.date),
        count: count()
      })
      |> Repo.one()

    trade_range =
      Trade
      |> select([t], %{
        min_date: min(t.trade_date),
        max_date: max(t.trade_date),
        count: count()
      })
      |> Repo.one()

    %{nordnet: nil, ibkr: ibkr_snapshot_range, ibkr_txns: trade_range}
  end

  def dividend_gaps do
    payments =
      DividendPayment
      |> order_by([d], asc: d.pay_date)
      |> preload(instrument: :aliases)
      |> Repo.all()

    payments
    |> Enum.group_by(fn d -> d.instrument.isin end)
    |> Enum.map(fn {isin, divs} ->
      sorted = Enum.sort_by(divs, & &1.pay_date, Date)
      symbol = payment_symbol(hd(sorted))

      gaps =
        sorted
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.filter(fn [a, b] -> Date.diff(b.pay_date, a.pay_date) > 400 end)
        |> Enum.map(fn [a, b] ->
          %{from: a.pay_date, to: b.pay_date, days: Date.diff(b.pay_date, a.pay_date)}
        end)

      %{
        key: isin,
        symbol: symbol,
        first_dividend: hd(sorted).pay_date,
        last_dividend: List.last(sorted).pay_date,
        count: length(sorted),
        gaps: gaps
      }
    end)
    |> Enum.filter(fn d -> d.gaps != [] end)
    |> Enum.sort_by(& &1.symbol)
  end

  ## Margin & Equity Tracking

  @doc """
  Returns the latest margin equity snapshot.
  """
  def get_latest_margin_equity do
    MarginEquitySnapshot
    |> order_by([m], desc: m.date)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Returns margin equity snapshot for a specific date.
  """
  def get_margin_equity_for_date(date) do
    Repo.get_by(MarginEquitySnapshot, date: date)
  end

  @doc """
  Returns the margin equity snapshot nearest to the given date.
  """
  def get_margin_equity_nearest_date(target_date) do
    before =
      MarginEquitySnapshot
      |> where([m], m.date <= ^target_date)
      |> order_by(desc: :date)
      |> limit(1)
      |> Repo.one()

    after_s =
      MarginEquitySnapshot
      |> where([m], m.date >= ^target_date)
      |> order_by(asc: :date)
      |> limit(1)
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
  Lists all margin equity snapshots ordered by date.
  """
  def list_margin_equity_snapshots do
    MarginEquitySnapshot
    |> order_by([m], desc: m.date)
    |> Repo.all()
  end

  @doc """
  Creates a margin equity snapshot.
  """
  def create_margin_equity_snapshot(attrs) do
    %MarginEquitySnapshot{}
    |> MarginEquitySnapshot.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Upserts a margin equity snapshot (by date).
  """
  def upsert_margin_equity_snapshot(attrs) do
    %MarginEquitySnapshot{}
    |> MarginEquitySnapshot.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:date]
    )
  end

  @doc """
  Returns a comprehensive margin & equity summary for display.

  Combines latest margin equity data with actual interest costs and rate comparison.
  """
  def margin_equity_summary do
    zero = Decimal.new("0")
    margin_snapshot = get_latest_margin_equity()

    actual_interest = total_actual_margin_interest()
    # IBKR-only: margin equity is an IBKR concept, Nordnet deposits are irrelevant
    dw = total_deposits_withdrawals(source: "ibkr")

    case margin_snapshot do
      nil ->
        # No margin data yet — return what we can derive
        %{
          has_data: false,
          net_invested: dw.net_invested,
          deposits: dw.deposits,
          withdrawals: dw.withdrawals,
          actual_interest_total: actual_interest,
          actual_interest_by_month: margin_interest_by_month()
        }

      snapshot ->
        margin_loan = snapshot.margin_loan || zero
        rate_info = MarginRates.rate_summary("EUR", margin_loan)

        %{
          has_data: true,
          date: snapshot.date,
          cash_balance: snapshot.cash_balance,
          margin_loan: margin_loan,
          net_liquidation_value: snapshot.net_liquidation_value,
          own_equity: snapshot.own_equity,
          leverage_ratio: snapshot.leverage_ratio,
          loan_to_value: snapshot.loan_to_value,
          net_invested: dw.net_invested,
          deposits: dw.deposits,
          withdrawals: dw.withdrawals,
          actual_interest_total: actual_interest,
          actual_interest_by_month: margin_interest_by_month(),
          expected_rate: rate_info,
          payback: compute_payback(snapshot.own_equity)
        }
    end
  end

  @doc """
  Returns total actual margin interest paid (from cash_flows).
  """
  def total_actual_margin_interest do
    CashFlow
    |> where([c], c.flow_type == "interest" and c.source == "ibkr")
    |> select([c], sum(fragment("ABS(?)", c.amount)))
    |> Repo.one() || Decimal.new("0")
  end

  @doc """
  Returns margin interest charges grouped by month.
  """
  def margin_interest_by_month do
    CashFlow
    |> where([c], c.flow_type == "interest" and c.source == "ibkr")
    |> group_by([c], fragment("to_char(?, 'YYYY-MM')", c.date))
    |> select([c], %{
      month: fragment("to_char(?, 'YYYY-MM')", c.date),
      amount: fragment("ABS(SUM(?))", c.amount)
    })
    |> order_by([c], fragment("to_char(?, 'YYYY-MM')", c.date))
    |> Repo.all()
  end

  @doc """
  Returns margin interest total for a specific year.
  """
  def margin_interest_for_year(year) do
    year_start = Date.new!(year, 1, 1)

    year_end =
      if year == Date.utc_today().year, do: Date.utc_today(), else: Date.new!(year, 12, 31)

    CashFlow
    |> where([c], c.flow_type == "interest" and c.source == "ibkr")
    |> where([c], c.date >= ^year_start and c.date <= ^year_end)
    |> select([c], sum(fragment("ABS(?)", c.amount)))
    |> Repo.one() || Decimal.new("0")
  end

  @doc """
  Computes payback timeline: how much of own invested capital has been earned back.

  Cumulative earnings = dividends + realized P&L - costs (including margin interest)
  Payback % = cumulative earnings / own_equity
  """
  def compute_payback(own_equity) do
    zero = Decimal.new("0")

    if is_nil(own_equity) or Decimal.compare(own_equity, zero) != :gt do
      %{
        own_equity: own_equity || zero,
        cumulative_earnings: zero,
        payback_pct: zero,
        projected_payback_date: nil
      }
    else
      total_dividends =
        dividend_years()
        |> Enum.reduce(zero, fn year, acc ->
          Decimal.add(acc, total_dividends_for_year(year))
        end)

      realized_pnl = total_realized_pnl()
      total_costs = costs_summary().total

      cumulative_earnings =
        realized_pnl
        |> Decimal.add(total_dividends)
        |> Decimal.sub(total_costs)

      payback_pct =
        cumulative_earnings
        |> Decimal.div(own_equity)
        |> Decimal.mult(Decimal.new("100"))
        |> Decimal.round(1)

      projected_date = project_payback_date(cumulative_earnings, own_equity)

      %{
        own_equity: own_equity,
        cumulative_earnings: cumulative_earnings,
        payback_pct: payback_pct,
        projected_payback_date: projected_date
      }
    end
  end

  defp project_payback_date(cumulative_earnings, own_equity) do
    zero = Decimal.new("0")

    with true <- Decimal.compare(cumulative_earnings, zero) == :gt,
         %{date: first_date} <- get_first_snapshot(),
         days_active when days_active > 0 <- Date.diff(Date.utc_today(), first_date) do
      compute_payback_date(cumulative_earnings, own_equity, days_active)
    else
      _ -> nil
    end
  end

  defp compute_payback_date(cumulative_earnings, own_equity, days_active) do
    zero = Decimal.new("0")
    daily_rate = Decimal.div(cumulative_earnings, Decimal.new(days_active))
    remaining = Decimal.sub(own_equity, cumulative_earnings)

    if Decimal.compare(remaining, zero) == :gt and Decimal.compare(daily_rate, zero) == :gt do
      days_to_payback =
        remaining |> Decimal.div(daily_rate) |> Decimal.round(0) |> Decimal.to_integer()

      Date.add(Date.utc_today(), days_to_payback)
    else
      nil
    end
  end

  # stock_gaps is still used by DataGapsLive — returns [] until reimplemented with new tables
  def stock_gaps(_opts \\ []), do: []
end
