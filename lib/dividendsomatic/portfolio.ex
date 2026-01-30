defmodule Dividendsomatic.Portfolio do
  @moduledoc """
  Portfolio context for managing snapshots and holdings.
  """

  import Ecto.Query
  alias Dividendsomatic.Repo
  alias Dividendsomatic.Portfolio.{PortfolioSnapshot, Holding}

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
  Returns snapshot data for charting (date and total value).
  """
  def get_chart_data(limit \\ 30) do
    PortfolioSnapshot
    |> order_by([s], desc: s.report_date)
    |> limit(^limit)
    |> preload(:holdings)
    |> Repo.all()
    |> Enum.reverse()
    |> Enum.map(fn snapshot ->
      total_value =
        Enum.reduce(snapshot.holdings, Decimal.new("0"), fn holding, acc ->
          Decimal.add(acc, holding.position_value || Decimal.new("0"))
        end)

      {Date.to_string(snapshot.report_date), Decimal.to_float(total_value)}
    end)
  end

  @doc """
  Creates a portfolio snapshot with holdings from CSV data.
  """
  def create_snapshot_from_csv(csv_data, report_date) do
    Repo.transaction(fn ->
      # Create snapshot
      {:ok, snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{
          report_date: report_date,
          raw_csv_data: csv_data
        })
        |> Repo.insert()

      # Parse and create holdings
      _holdings = parse_csv_holdings(csv_data, snapshot.id)

      {:ok, snapshot}
    end)
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
      {decimal, _} -> decimal
      :error -> Decimal.new("0")
    end
  end
end
