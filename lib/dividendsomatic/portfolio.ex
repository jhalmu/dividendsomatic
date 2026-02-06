defmodule Dividendsomatic.Portfolio do
  @moduledoc """
  Portfolio context for managing snapshots and holdings.
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.{Dividend, Holding, PortfolioSnapshot, SoldPosition}
  alias Dividendsomatic.Repo

  NimbleCSV.define(CSVParser, separator: ",", escape: "\"")

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
  Returns ALL snapshot data for charting (no limit).
  """
  def get_all_chart_data do
    PortfolioSnapshot
    |> order_by([s], asc: s.report_date)
    |> preload(:holdings)
    |> Repo.all()
    |> Enum.map(&snapshot_to_chart_point/1)
  end

  defp snapshot_to_chart_point(snapshot) do
    total_value =
      Enum.reduce(snapshot.holdings, Decimal.new("0"), fn holding, acc ->
        Decimal.add(acc, holding.position_value || Decimal.new("0"))
      end)

    total_cost_basis =
      Enum.reduce(snapshot.holdings, Decimal.new("0"), fn holding, acc ->
        Decimal.add(acc, holding.cost_basis_money || Decimal.new("0"))
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
  Returns growth statistics comparing first and latest snapshots.
  """
  def get_growth_stats do
    first = get_first_snapshot()
    latest = get_latest_snapshot()

    case {first, latest} do
      {nil, _} ->
        nil

      {_, nil} ->
        nil

      {first_snap, latest_snap} ->
        first_value = calculate_total_value(first_snap.holdings)
        latest_value = calculate_total_value(latest_snap.holdings)
        absolute_change = Decimal.sub(latest_value, first_value)

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
          latest_date: latest_snap.report_date,
          first_value: first_value,
          latest_value: latest_value,
          absolute_change: absolute_change,
          percent_change: percent_change
        }
    end
  end

  defp calculate_total_value(holdings) do
    Enum.reduce(holdings || [], Decimal.new("0"), fn holding, acc ->
      Decimal.add(acc, holding.position_value || Decimal.new("0"))
    end)
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
    |> CSVParser.parse_string(skip_headers: false)
    # Skip header row
    |> Enum.drop(1)
    |> Enum.map(fn row ->
      create_holding_from_row(row, snapshot_id)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp create_holding_from_row(row, snapshot_id) do
    attrs = %{
      portfolio_snapshot_id: snapshot_id,
      report_date: parse_date(Enum.at(row, 0)),
      currency_primary: Enum.at(row, 1),
      symbol: Enum.at(row, 2),
      description: Enum.at(row, 3),
      sub_category: Enum.at(row, 4),
      quantity: parse_decimal(Enum.at(row, 5)),
      mark_price: parse_decimal(Enum.at(row, 6)),
      position_value: parse_decimal(Enum.at(row, 7)),
      cost_basis_price: parse_decimal(Enum.at(row, 8)),
      cost_basis_money: parse_decimal(Enum.at(row, 9)),
      open_price: parse_decimal(Enum.at(row, 10)),
      percent_of_nav: parse_decimal(Enum.at(row, 11)),
      fifo_pnl_unrealized: parse_decimal(Enum.at(row, 12)),
      listing_exchange: Enum.at(row, 13),
      asset_class: Enum.at(row, 14),
      fx_rate_to_base: parse_decimal(Enum.at(row, 15)),
      isin: Enum.at(row, 16),
      figi: Enum.at(row, 17)
    }

    %Holding{}
    |> Holding.changeset(attrs)
    |> Repo.insert!()
  end

  defp parse_date(nil), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_decimal(nil), do: Decimal.new("0")
  defp parse_decimal(""), do: Decimal.new("0")

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} ->
        decimal

      :error ->
        Logger.warning("Failed to parse decimal value: #{inspect(value)}, defaulting to 0")
        Decimal.new("0")
    end
  end

  ## Dividends

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
  Gets total dividend income for the current year.
  """
  def total_dividends_this_year do
    year_start = Date.new!(Date.utc_today().year, 1, 1)

    Dividend
    |> where([d], d.ex_date >= ^year_start)
    |> select([d], sum(d.amount))
    |> Repo.one() || Decimal.new("0")
  end

  @doc """
  Gets dividend income grouped by month for the current year.
  """
  def dividends_by_month do
    year_start = Date.new!(Date.utc_today().year, 1, 1)

    Dividend
    |> where([d], d.ex_date >= ^year_start)
    |> group_by([d], fragment("strftime('%Y-%m', ?)", d.ex_date))
    |> select([d], %{
      month: fragment("strftime('%Y-%m', ?)", d.ex_date),
      total: sum(d.amount)
    })
    |> order_by([d], fragment("strftime('%Y-%m', ?)", d.ex_date))
    |> Repo.all()
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
end
