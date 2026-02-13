defmodule Dividendsomatic.Portfolio do
  @moduledoc """
  Portfolio context for managing snapshots and holdings.
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.{
    BrokerTransaction,
    Cost,
    CsvParser,
    Dividend,
    Holding,
    PortfolioSnapshot,
    PositionReconstructor,
    SoldPosition
  }

  alias Dividendsomatic.Repo
  alias Dividendsomatic.Stocks

  ## Portfolio Snapshots

  @doc """
  Returns the latest portfolio snapshot.
  """
  def get_latest_snapshot do
    PortfolioSnapshot
    |> order_by([s], desc: s.report_date)
    |> limit(1)
    |> preload(:holdings)
    |> Repo.one()
  end

  @doc """
  Returns snapshot for a specific date.
  """
  def get_snapshot_by_date(date) do
    Repo.get_by(PortfolioSnapshot, report_date: date)
    |> Repo.preload(:holdings)
  end

  @doc """
  Returns snapshot before given date (for navigation).
  """
  def get_previous_snapshot(date) do
    PortfolioSnapshot
    |> where([s], s.report_date < ^date)
    |> order_by([s], desc: s.report_date)
    |> limit(1)
    |> preload(:holdings)
    |> Repo.one()
  end

  @doc """
  Returns snapshot after given date (for navigation).
  """
  def get_next_snapshot(date) do
    PortfolioSnapshot
    |> where([s], s.report_date > ^date)
    |> order_by([s], asc: s.report_date)
    |> limit(1)
    |> preload(:holdings)
    |> Repo.one()
  end

  @doc """
  Returns the snapshot N positions before the given date.
  """
  def get_snapshot_back(date, n) do
    PortfolioSnapshot
    |> where([s], s.report_date < ^date)
    |> order_by([s], desc: s.report_date)
    |> offset(^(n - 1))
    |> limit(1)
    |> preload(:holdings)
    |> Repo.one()
  end

  @doc """
  Returns the snapshot N positions after the given date.
  """
  def get_snapshot_forward(date, n) do
    PortfolioSnapshot
    |> where([s], s.report_date > ^date)
    |> order_by([s], asc: s.report_date)
    |> offset(^(n - 1))
    |> limit(1)
    |> preload(:holdings)
    |> Repo.one()
  end

  @doc """
  Lists all snapshots ordered by date descending.
  """
  def list_snapshots do
    PortfolioSnapshot
    |> order_by([s], desc: s.report_date)
    |> Repo.all()
  end

  @doc """
  Checks if a snapshot exists before the given date.
  More efficient than get_previous_snapshot when you only need to know existence.
  """
  def has_previous_snapshot?(date) do
    PortfolioSnapshot
    |> where([s], s.report_date < ^date)
    |> Repo.exists?()
  end

  @doc """
  Checks if a snapshot exists after the given date.
  More efficient than get_next_snapshot when you only need to know existence.
  """
  def has_next_snapshot?(date) do
    PortfolioSnapshot
    |> where([s], s.report_date > ^date)
    |> Repo.exists?()
  end

  @doc """
  Returns snapshot data for charting (date and total value).
  """
  def get_chart_data(limit \\ 30) do
    PortfolioSnapshot
    |> order_by([s], desc: s.report_date)
    |> limit(^limit)
    |> preload(:holdings)
    |> Repo.all()
    |> Enum.reverse()
    |> Enum.map(&snapshot_to_chart_point/1)
  end

  @doc """
  Returns ALL chart data: reconstructed Nordnet data + IBKR snapshot data.

  Merges two data sources:
  - Nordnet era (2017-2022): Reconstructed from broker_transactions + historical prices
  - IBKR era (2025+): Direct from portfolio_snapshots

  Gap between eras is preserved as-is (honest representation).
  """
  def get_all_chart_data do
    reconstructed = get_reconstructed_chart_data()
    ibkr = get_ibkr_chart_data()
    reconstructed ++ ibkr
  end

  @doc """
  Returns IBKR snapshot data for charting (original behavior).
  """
  def get_ibkr_chart_data do
    PortfolioSnapshot
    |> order_by([s], asc: s.report_date)
    |> preload(:holdings)
    |> Repo.all()
    |> Enum.map(&snapshot_to_chart_point/1)
  end

  @doc """
  Returns reconstructed chart data from Nordnet broker transactions.

  Uses PositionReconstructor to rebuild positions, then prices them
  using historical price data and FX rates.
  """
  def get_reconstructed_chart_data do
    positions_over_time = PositionReconstructor.reconstruct()

    positions_over_time
    |> Enum.map(&price_reconstructed_point/1)
    |> Enum.reject(&is_nil/1)
  end

  defp price_reconstructed_point(%{date: date, positions: positions}) do
    {total_value, total_cost_basis} =
      Enum.reduce(positions, {Decimal.new("0"), Decimal.new("0")}, fn pos, {val_acc, cost_acc} ->
        case get_position_value(pos, date) do
          {:ok, value} ->
            {Decimal.add(val_acc, value), Decimal.add(cost_acc, pos.cost_basis)}

          :skip ->
            {val_acc, Decimal.add(cost_acc, pos.cost_basis)}
        end
      end)

    # Only include points where we have at least some price data
    if Decimal.compare(total_value, Decimal.new("0")) == :gt do
      %{
        date: date,
        date_string: Date.to_string(date),
        value: total_value,
        value_float: Decimal.to_float(total_value),
        cost_basis_float: Decimal.to_float(total_cost_basis),
        source: :nordnet
      }
    else
      nil
    end
  end

  defp get_position_value(position, date) do
    # Resolve ISIN to Finnhub symbol
    mapping = Stocks.get_symbol_mapping(position.isin)

    symbol =
      case mapping do
        %{status: "resolved", finnhub_symbol: s} -> s
        _ -> nil
      end

    if symbol do
      case Stocks.get_close_price(symbol, date) do
        {:ok, close_price} ->
          value = Decimal.mult(position.quantity, close_price)

          # Apply FX conversion if non-EUR
          eur_value = apply_fx_conversion(value, position.currency, date)
          {:ok, eur_value}

        {:error, _} ->
          :skip
      end
    else
      :skip
    end
  end

  defp apply_fx_conversion(value, "EUR", _date), do: value

  defp apply_fx_conversion(value, currency, date) do
    pair = "OANDA:EUR_#{currency}"

    case Stocks.get_fx_rate(pair, date) do
      {:ok, rate} ->
        # EUR/XXX rate means 1 EUR = X units of currency
        # To convert from currency to EUR: value / rate
        if Decimal.compare(rate, Decimal.new("0")) == :gt do
          Decimal.div(value, rate)
        else
          value
        end

      {:error, _} ->
        # No FX data, return unconverted (approximate)
        value
    end
  end

  defp snapshot_to_chart_point(snapshot) do
    total_value =
      Enum.reduce(snapshot.holdings, Decimal.new("0"), fn holding, acc ->
        Decimal.add(acc, to_base_currency(holding.position_value, holding.fx_rate_to_base))
      end)

    total_cost_basis =
      Enum.reduce(snapshot.holdings, Decimal.new("0"), fn holding, acc ->
        Decimal.add(acc, to_base_currency(holding.cost_basis_money, holding.fx_rate_to_base))
      end)

    %{
      date: snapshot.report_date,
      date_string: Date.to_string(snapshot.report_date),
      value: total_value,
      value_float: Decimal.to_float(total_value),
      cost_basis_float: Decimal.to_float(total_cost_basis)
    }
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
        first_value = calculate_total_value(first_snap.holdings)
        current_value = calculate_total_value(current_snap.holdings)
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
          first_date: first_snap.report_date,
          latest_date: current_snap.report_date,
          first_value: first_value,
          latest_value: current_value,
          absolute_change: absolute_change,
          percent_change: percent_change
        }
    end
  end

  defp calculate_total_value(holdings) do
    Enum.reduce(holdings || [], Decimal.new("0"), fn holding, acc ->
      Decimal.add(acc, to_base_currency(holding.position_value, holding.fx_rate_to_base))
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
    |> order_by([s], asc: s.report_date)
    |> limit(1)
    |> preload(:holdings)
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
    |> where([s], s.report_date <= ^date)
    |> Repo.aggregate(:count)
  end

  @doc """
  Creates a portfolio snapshot with holdings from CSV data.

  Returns `{:ok, snapshot}` on success, `{:error, reason}` on failure.
  """
  def create_snapshot_from_csv(csv_data, report_date) do
    Repo.transaction(fn ->
      case create_snapshot(report_date, csv_data) do
        {:ok, snapshot} ->
          parse_csv_holdings(csv_data, snapshot.id)
          snapshot

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp create_snapshot(report_date, csv_data) do
    %PortfolioSnapshot{}
    |> PortfolioSnapshot.changeset(%{
      report_date: report_date,
      raw_csv_data: csv_data
    })
    |> Repo.insert()
  end

  ## Private Functions

  defp parse_csv_holdings(csv_data, snapshot_id) do
    csv_data
    |> CsvParser.parse(snapshot_id)
    |> Enum.map(fn attrs ->
      %Holding{}
      |> Holding.changeset(attrs)
      |> Repo.insert!()
    end)
  end

  ## Dividends

  @doc """
  Lists all holdings for a specific symbol (from most recent snapshots).
  Returns the latest holding record per snapshot for the given symbol.
  """
  def list_holdings_by_symbol(symbol) do
    Holding
    |> where([h], h.symbol == ^symbol)
    |> order_by([h], desc: h.report_date)
    |> Repo.all()
  end

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
  Returns list of `%{dividend: %Dividend{}, income: Decimal}`.
  """
  def list_dividends_with_income do
    year_start = Date.new!(Date.utc_today().year, 1, 1)
    today = Date.utc_today()

    dividends =
      Dividend
      |> where([d], d.ex_date >= ^year_start and d.ex_date <= ^today)
      |> order_by([d], desc: d.ex_date)
      |> Repo.all()

    holdings_data = build_holdings_map(year_start, today)

    dividends
    |> Enum.map(fn div ->
      income = compute_dividend_income(div, holdings_data)
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
    year_end = if year == Date.utc_today().year, do: Date.utc_today(), else: Date.new!(year, 12, 31)

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
  Multiplies per-share amounts by shares held and converts to base currency.
  """
  def dividends_by_month(from_date, to_date) do
    # Get dividends in range
    dividends =
      Dividend
      |> where([d], d.ex_date >= ^from_date and d.ex_date <= ^to_date)
      |> order_by([d], asc: d.ex_date)
      |> Repo.all()

    # Get holdings snapshots in range to know shares held
    holdings_map = build_holdings_map(from_date, to_date)

    # Calculate actual income per dividend
    dividends
    |> Enum.map(fn div ->
      month = Calendar.strftime(div.ex_date, "%Y-%m")
      income = compute_dividend_income(div, holdings_map)
      {month, income}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {month, incomes} ->
      %{month: month, total: Enum.reduce(incomes, Decimal.new("0"), &Decimal.add/2)}
    end)
    |> Enum.sort_by(& &1.month)
  end

  # Build a list of {date, symbol, quantity, fx_rate} tuples for dividend income lookup.
  # Includes the most recent snapshot before from_date so early dividends can find holdings.
  defp build_holdings_map(from_date, to_date) do
    # Include the last snapshot before the range for lookback
    lookback_snapshot =
      PortfolioSnapshot
      |> where([s], s.report_date < ^from_date)
      |> order_by([s], desc: s.report_date)
      |> limit(1)
      |> preload(:holdings)
      |> Repo.all()

    range_snapshots =
      PortfolioSnapshot
      |> where([s], s.report_date >= ^from_date and s.report_date <= ^to_date)
      |> preload(:holdings)
      |> order_by([s], asc: s.report_date)
      |> Repo.all()

    (lookback_snapshot ++ range_snapshots)
    |> Enum.flat_map(fn snapshot ->
      Enum.map(snapshot.holdings, fn h ->
        {snapshot.report_date, h.symbol, h.quantity, h.fx_rate_to_base}
      end)
    end)
  end

  defp compute_dividend_income(dividend, holdings_data) do
    # Find the nearest holding with matching symbol, closest to ex_date
    matching =
      holdings_data
      |> Enum.filter(fn {_date, symbol, _qty, _fx} -> symbol == dividend.symbol end)
      |> Enum.min_by(
        fn {date, _, _, _} -> abs(Date.diff(date, dividend.ex_date)) end,
        fn -> nil end
      )

    case matching do
      {_date, _symbol, quantity, fx_rate} ->
        qty = quantity || Decimal.new("0")
        fx = fx_rate || Decimal.new("1")
        amount = dividend.amount || Decimal.new("0")
        # income = per_share_amount * shares * fx_rate_to_base
        Decimal.mult(Decimal.mult(amount, qty), fx)

      nil ->
        # No matching holding found - return 0 (user didn't hold this stock)
        Decimal.new("0")
    end
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

  ## FX Exposure

  @doc """
  Computes FX exposure breakdown from holdings.
  Groups by currency, calculates EUR value, FX rate, and % of portfolio.
  Returns list sorted by EUR value descending.
  """
  def compute_fx_exposure(holdings) do
    total_eur =
      Enum.reduce(holdings, Decimal.new("0"), fn h, acc ->
        fx = h.fx_rate_to_base || Decimal.new("1")
        Decimal.add(acc, Decimal.mult(h.position_value || Decimal.new("0"), fx))
      end)

    holdings
    |> Enum.group_by(& &1.currency_primary)
    |> Enum.map(fn {currency, group} -> build_currency_group(currency, group, total_eur) end)
    |> Enum.sort_by(fn e -> Decimal.to_float(e.eur_value) end, :desc)
  end

  defp build_currency_group(currency, group, total_eur) do
    local_value =
      Enum.reduce(group, Decimal.new("0"), fn h, acc ->
        Decimal.add(acc, h.position_value || Decimal.new("0"))
      end)

    eur_value =
      Enum.reduce(group, Decimal.new("0"), fn h, acc ->
        fx = h.fx_rate_to_base || Decimal.new("1")
        Decimal.add(acc, Decimal.mult(h.position_value || Decimal.new("0"), fx))
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

  defp weighted_fx_rate(local_value, eur_value, fallback_holding) do
    if Decimal.compare(local_value, Decimal.new("0")) != :eq,
      do: eur_value |> Decimal.div(local_value) |> Decimal.round(4),
      else: fallback_holding.fx_rate_to_base || Decimal.new("1")
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

  @doc """
  Lists all sold positions.
  """
  def list_sold_positions do
    SoldPosition
    |> order_by([s], desc: s.sale_date)
    |> Repo.all()
  end

  @doc """
  Returns sold positions grouped by symbol with aggregated stats.

  Each entry: `%{symbol, trades, total_quantity, total_pnl, first_date, last_date, avg_held_days}`
  Sorted by total_pnl descending (biggest winners first).
  """
  def list_sold_positions_grouped do
    SoldPosition
    |> group_by([s], s.symbol)
    |> select([s], %{
      symbol: s.symbol,
      trades: count(s.id),
      total_quantity: sum(s.quantity),
      total_pnl: sum(s.realized_pnl),
      first_date: min(s.purchase_date),
      last_date: max(s.sale_date)
    })
    |> order_by([s], desc: sum(s.realized_pnl))
    |> Repo.all()
  end

  @doc """
  Returns count of sold positions.
  """
  def count_sold_positions do
    Repo.aggregate(SoldPosition, :count)
  end

  @doc """
  Lists sold positions for a specific symbol.
  """
  def list_sold_positions_by_symbol(symbol) do
    SoldPosition
    |> where([s], s.symbol == ^symbol)
    |> order_by([s], desc: s.sale_date)
    |> Repo.all()
  end

  @doc """
  Creates a sold position record.
  """
  def create_sold_position(attrs) do
    %SoldPosition{}
    |> SoldPosition.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a sold position record.
  """
  def update_sold_position(%SoldPosition{} = sold_position, attrs) do
    sold_position
    |> SoldPosition.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a sold position record.
  """
  def delete_sold_position(%SoldPosition{} = sold_position) do
    Repo.delete(sold_position)
  end

  @doc """
  Gets a sold position by ID.
  """
  def get_sold_position(id) do
    Repo.get(SoldPosition, id)
  end

  @doc """
  Calculates total realized P&L from all sold positions.
  """
  def total_realized_pnl do
    SoldPosition
    |> select([s], sum(s.realized_pnl))
    |> Repo.one() || Decimal.new("0")
  end

  @doc """
  Calculates hypothetical value of sold positions at current prices.

  Requires a map of symbol => current_price to calculate.
  Returns the total value if positions were never sold.
  """
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

  @doc """
  Calculates the opportunity cost (or gain) from selling positions.

  Returns negative if selling was a mistake (would be worth more now).
  Returns positive if selling was a good decision (would be worth less now).
  """
  def what_if_opportunity_cost(current_prices) when is_map(current_prices) do
    list_sold_positions()
    |> Enum.reduce(Decimal.new("0"), fn sold, acc ->
      current_price = Map.get(current_prices, sold.symbol)

      if current_price do
        # What we got from selling
        sale_proceeds = Decimal.mult(sold.quantity, sold.sale_price)
        # What it would be worth now
        hypothetical_value = Decimal.mult(sold.quantity, current_price)
        # Positive = good decision to sell, negative = bad decision
        opportunity = Decimal.sub(sale_proceeds, hypothetical_value)
        Decimal.add(acc, opportunity)
      else
        acc
      end
    end)
  end

  @doc """
  Gets What-If analysis summary.

  Returns a map with:
  - `sold_positions_count` - Number of sold positions
  - `total_realized_pnl` - Total P&L from sales
  - `hypothetical_value` - What sold positions would be worth now
  - `opportunity_cost` - Difference between sale proceeds and current value
  """
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
  Creates a broker transaction.
  """
  def create_broker_transaction(attrs) do
    %BrokerTransaction{}
    |> BrokerTransaction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Upserts a broker transaction (idempotent by broker + external_id).
  """
  def upsert_broker_transaction(attrs) do
    %BrokerTransaction{}
    |> BrokerTransaction.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:broker, :external_id])
  end

  @doc """
  Lists broker transactions with optional filters.
  """
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

  ## Costs

  @doc """
  Creates a cost record.
  """
  def create_cost(attrs) do
    %Cost{}
    |> Cost.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists all costs.
  """
  def list_costs do
    Cost
    |> order_by([c], desc: c.date)
    |> Repo.all()
  end

  @doc """
  Lists costs by type.
  """
  def list_costs_by_type(cost_type) do
    Cost
    |> where([c], c.cost_type == ^cost_type)
    |> order_by([c], desc: c.date)
    |> Repo.all()
  end

  @doc """
  Lists costs by symbol.
  """
  def list_costs_by_symbol(symbol) do
    Cost
    |> where([c], c.symbol == ^symbol)
    |> order_by([c], desc: c.date)
    |> Repo.all()
  end

  @doc """
  Returns total costs grouped by type.
  """
  def total_costs_by_type do
    Cost
    |> group_by([c], c.cost_type)
    |> select([c], {c.cost_type, sum(c.amount)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns a cost summary with totals.
  """
  def costs_summary do
    by_type = total_costs_by_type()

    total =
      by_type
      |> Map.values()
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

    %{by_type: by_type, total: total, count: Repo.aggregate(Cost, :count)}
  end

  ## Data Gaps Analysis

  @doc """
  Returns broker coverage data for gap analysis.
  """
  def broker_coverage do
    nordnet_range =
      BrokerTransaction
      |> where([t], t.broker == "nordnet")
      |> select([t], %{min_date: min(t.trade_date), max_date: max(t.trade_date), count: count()})
      |> Repo.one()

    ibkr_range =
      PortfolioSnapshot
      |> select([s], %{
        min_date: min(s.report_date),
        max_date: max(s.report_date),
        count: count()
      })
      |> Repo.one()

    %{nordnet: nordnet_range, ibkr: ibkr_range}
  end

  @doc """
  Returns per-stock gap analysis.
  Shows first/last dates per broker, and gap periods.
  """
  def stock_gaps(opts \\ []) do
    current_only = Keyword.get(opts, :current_only, false)

    nordnet_stocks = fetch_nordnet_stock_ranges()
    ibkr_stocks = fetch_ibkr_stock_ranges()
    current_isins = if current_only, do: current_holding_isins(), else: nil

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
    Holding
    |> where([h], not is_nil(h.isin))
    |> group_by([h], [h.isin, h.symbol])
    |> select([h], %{
      isin: h.isin,
      name: h.symbol,
      first_date: min(h.report_date),
      last_date: max(h.report_date),
      broker: "ibkr"
    })
    |> Repo.all()
  end

  defp current_holding_isins do
    case get_latest_snapshot() do
      nil ->
        MapSet.new()

      snapshot ->
        snapshot.holdings
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
      gap_days = compute_gap_days(nordnet, ibkr)

      %{
        isin: isin,
        name: name,
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
    # Gap = time between Nordnet last date and IBKR first date
    gap = Date.diff(ibkr.first_date, nordnet.last_date)
    max(gap, 0)
  end

  defp brokers_list(nordnet, ibkr) do
    []
    |> then(fn l -> if nordnet, do: ["nordnet" | l], else: l end)
    |> then(fn l -> if ibkr, do: ["ibkr" | l], else: l end)
  end

  @doc """
  Returns dividend coverage gaps for stocks.
  """
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
