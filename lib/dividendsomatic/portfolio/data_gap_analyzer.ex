defmodule Dividendsomatic.Portfolio.DataGapAnalyzer do
  @moduledoc """
  Analyzes data gaps across portfolio snapshots and dividends.

  Provides 364-day chunk analysis, per-stock dividend gaps,
  and snapshot coverage reports.
  """

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{DividendPayment, Instrument, PortfolioSnapshot, Trade}
  alias Dividendsomatic.Repo

  @chunk_days 364

  @doc """
  Returns a full gap analysis report.
  """
  def analyze do
    %{
      chunks: missing_by_year_chunks(),
      dividend_gaps: analyze_dividend_gaps(),
      snapshot_gaps: analyze_snapshot_gaps(),
      summary: summary()
    }
  end

  @doc """
  Returns 364-day chunk analysis covering the full data range.
  """
  def missing_by_year_chunks do
    {min_date, max_date} = data_date_range()

    if is_nil(min_date) do
      []
    else
      build_chunks(min_date, max_date)
    end
  end

  @doc """
  Returns per-stock dividend gap analysis.
  Flags stocks where >400 days pass between consecutive dividends.
  """
  def analyze_dividend_gaps do
    from(dp in DividendPayment,
      join: i in Instrument,
      on: dp.instrument_id == i.id,
      where: not is_nil(dp.ex_date),
      order_by: [asc: dp.ex_date],
      select: %{
        isin: i.isin,
        symbol: i.name,
        ex_date: dp.ex_date
      }
    )
    |> Repo.all()
    |> Enum.group_by(fn d -> d.isin || d.symbol end)
    |> Enum.map(fn {key, divs} ->
      sorted = Enum.sort_by(divs, & &1.ex_date, Date)

      gaps =
        sorted
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.filter(fn [a, b] ->
          a.ex_date && b.ex_date && Date.diff(b.ex_date, a.ex_date) > 400
        end)
        |> Enum.map(fn [a, b] ->
          %{from: a.ex_date, to: b.ex_date, days: Date.diff(b.ex_date, a.ex_date)}
        end)

      %{
        key: key,
        symbol: hd(sorted).symbol,
        count: length(sorted),
        first: hd(sorted).ex_date,
        last: List.last(sorted).ex_date,
        gaps: gaps
      }
    end)
    |> Enum.filter(fn d -> d.gaps != [] end)
    |> Enum.sort_by(& &1.symbol)
  end

  @doc """
  Returns snapshot coverage gaps (periods with no portfolio snapshots).
  """
  def analyze_snapshot_gaps do
    snapshots =
      PortfolioSnapshot
      |> order_by([s], asc: s.date)
      |> select([s], s.date)
      |> Repo.all()

    case snapshots do
      [] ->
        []

      dates ->
        dates
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.filter(fn [a, b] -> Date.diff(b, a) > 7 end)
        |> Enum.map(fn [a, b] ->
          %{from: a, to: b, days: Date.diff(b, a)}
        end)
    end
  end

  @doc """
  Returns summary statistics.
  """
  def summary do
    dividend_count = Repo.aggregate(DividendPayment, :count)
    snapshot_count = Repo.aggregate(PortfolioSnapshot, :count)
    trade_count = Repo.aggregate(Trade, :count)

    dividend_range =
      DividendPayment
      |> select([d], %{min: min(d.ex_date), max: max(d.ex_date)})
      |> Repo.one()

    snapshot_range =
      PortfolioSnapshot
      |> select([s], %{min: min(s.date), max: max(s.date)})
      |> Repo.one()

    %{
      dividend_count: dividend_count,
      snapshot_count: snapshot_count,
      transaction_count: trade_count,
      dividend_range: dividend_range,
      snapshot_range: snapshot_range
    }
  end

  defp data_date_range do
    trade_range =
      Trade
      |> select([t], %{min: min(t.trade_date), max: max(t.trade_date)})
      |> Repo.one()

    snap_range =
      PortfolioSnapshot
      |> select([s], %{min: min(s.date), max: max(s.date)})
      |> Repo.one()

    min_date =
      [trade_range.min, snap_range.min]
      |> Enum.reject(&is_nil/1)
      |> Enum.min(Date, fn -> nil end)

    max_date =
      [trade_range.max, snap_range.max]
      |> Enum.reject(&is_nil/1)
      |> Enum.max(Date, fn -> nil end)

    {min_date, max_date}
  end

  defp build_chunks(min_date, max_date) do
    Stream.unfold(min_date, fn start ->
      if Date.compare(start, max_date) == :gt do
        nil
      else
        chunk_end = Date.add(start, @chunk_days - 1)
        chunk_end = Enum.min([chunk_end, max_date], Date)
        {build_chunk(start, chunk_end), Date.add(chunk_end, 1)}
      end
    end)
    |> Enum.to_list()
  end

  defp build_chunk(from, to) do
    snapshot_count =
      PortfolioSnapshot
      |> where([s], s.date >= ^from and s.date <= ^to)
      |> Repo.aggregate(:count)

    dividend_count =
      DividendPayment
      |> where([d], d.ex_date >= ^from and d.ex_date <= ^to)
      |> Repo.aggregate(:count)

    trade_count =
      Trade
      |> where([t], t.trade_date >= ^from and t.trade_date <= ^to)
      |> Repo.aggregate(:count)

    calendar_days = Date.diff(to, from) + 1
    expected_trading_days = round(calendar_days * 252 / 365)

    sources =
      PortfolioSnapshot
      |> where([s], s.date >= ^from and s.date <= ^to)
      |> select([s], s.source)
      |> distinct(true)
      |> Repo.all()

    coverage =
      if expected_trading_days > 0 do
        Float.round(snapshot_count / expected_trading_days * 100, 1)
      else
        0.0
      end

    %{
      from: from,
      to: to,
      calendar_days: calendar_days,
      expected_trading_days: expected_trading_days,
      snapshot_count: snapshot_count,
      dividend_count: dividend_count,
      transaction_count: trade_count,
      sources: sources,
      coverage_pct: coverage
    }
  end
end
