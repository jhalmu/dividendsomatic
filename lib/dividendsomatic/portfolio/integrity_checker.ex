defmodule Dividendsomatic.Portfolio.IntegrityChecker do
  @moduledoc """
  Cross-checks IBKR Actions.csv data against the database for integrity.

  Runs reconciliation checks in memory — no tables needed.
  Compares dividends, trades, and ISINs between Actions.csv and the DB.
  """

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{DividendPayment, FlexActionsCsvParser, Instrument, Trade}
  alias Dividendsomatic.Repo

  @type check_result :: %{
          name: String.t(),
          status: :pass | :fail | :warn,
          message: String.t(),
          details: list()
        }

  @doc """
  Runs all integrity checks against an Actions.csv file.

  Returns a list of check results.
  """
  @spec run_all(String.t()) :: {:ok, [check_result()]} | {:error, term()}
  def run_all(csv_path) do
    case FlexActionsCsvParser.parse_file(csv_path) do
      {:ok, actions_data} -> run_checks(actions_data)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Runs all integrity checks against an Actions CSV string (already in memory).

  Used by Gmail import when CSV data is downloaded directly from email.
  """
  @spec run_all_from_string(String.t()) :: {:ok, [check_result()]} | {:error, term()}
  def run_all_from_string(csv_string) do
    case FlexActionsCsvParser.parse(csv_string) do
      {:ok, actions_data} -> run_checks(actions_data)
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_checks(actions_data) do
    checks = [
      reconcile_dividends(actions_data),
      reconcile_trades(actions_data),
      find_missing_isins(actions_data),
      check_summary_totals(actions_data)
    ]

    {:ok, checks}
  end

  @doc """
  Compares dividend totals in Actions.csv vs database.
  """
  @spec reconcile_dividends(map()) :: check_result()
  def reconcile_dividends(%{transactions: transactions, summary: summary}) do
    actions_dividends = Enum.filter(transactions, &(&1.activity_code in ["DIV", "PIL"]))
    actions_total = sum_amounts(actions_dividends)
    {from_date, to_date} = extract_date_range(summary, transactions)
    db_count = count_db_dividends(from_date, to_date)
    # Summary tracks DIV and PIL in separate columns
    summary_div = summary[:dividends] || Decimal.new("0")
    summary_pil = summary[:payment_in_lieu] || Decimal.new("0")
    summary_total = Decimal.add(summary_div, summary_pil)
    actions_count = length(actions_dividends)

    %{
      name: "Dividend Reconciliation",
      status: dividend_status(actions_count, actions_total, summary_total),
      message:
        "Actions: #{actions_count} records (#{format_decimal(actions_total)} EUR), " <>
          "DB: #{db_count} records in range #{from_date}..#{to_date}, " <>
          "Summary: DIV #{format_decimal(summary_div)} + PIL #{format_decimal(summary_pil)} = #{format_decimal(summary_total)} EUR",
      details:
        Enum.map(actions_dividends, fn txn ->
          "#{txn.date} #{txn.symbol} #{format_decimal(txn.amount)} #{txn.currency}"
        end)
    }
  end

  defp sum_amounts(transactions) do
    transactions
    |> Enum.map(fn txn -> txn.amount || Decimal.new("0") end)
    |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
  end

  defp count_db_dividends(nil, _to), do: 0
  defp count_db_dividends(_from, nil), do: 0

  defp count_db_dividends(from_date, to_date) do
    DividendPayment
    |> where([d], d.ex_date >= ^from_date and d.ex_date <= ^to_date)
    |> Repo.aggregate(:count)
  end

  defp dividend_status(0, _total, _summary), do: :warn

  defp dividend_status(_count, actions_total, summary_total) do
    if Decimal.compare(summary_total, Decimal.new("0")) != :eq do
      discrepancy = Decimal.sub(actions_total, summary_total) |> Decimal.abs()
      if Decimal.compare(discrepancy, Decimal.new("1")) == :gt, do: :fail, else: :pass
    else
      :pass
    end
  end

  @doc """
  Compares trade counts in Actions.csv vs database.
  """
  @spec reconcile_trades(map()) :: check_result()
  def reconcile_trades(%{transactions: transactions, summary: summary}) do
    stock_trades = extract_stock_trades(transactions)
    {from_date, to_date} = extract_date_range(summary, transactions)
    db_count = count_db_trades(from_date, to_date)
    actions_count = length(stock_trades)
    diff = abs(actions_count - db_count)

    %{
      name: "Trade Reconciliation",
      status: trade_status(actions_count, diff),
      message:
        "Actions: #{actions_count} stock trades, DB: #{db_count} IBKR trades " <>
          "in range #{from_date}..#{to_date} (diff: #{diff})",
      details:
        Enum.map(stock_trades, fn txn ->
          "#{txn.date} #{txn.buy_sell} #{txn.symbol} qty=#{txn.trade_quantity} @ #{txn.trade_price}"
        end)
    }
  end

  defp extract_stock_trades(transactions) do
    transactions
    |> Enum.filter(fn txn ->
      (txn.activity_code == "BUY" or txn.buy_sell in ["BUY", "SELL"]) and
        txn.isin != nil and txn.isin != ""
    end)
  end

  defp count_db_trades(nil, _to), do: 0
  defp count_db_trades(_from, nil), do: 0

  defp count_db_trades(from_date, to_date) do
    Trade
    |> where([t], t.trade_date >= ^from_date and t.trade_date <= ^to_date)
    |> Repo.aggregate(:count)
  end

  defp trade_status(0, _diff), do: :warn
  defp trade_status(_count, 0), do: :pass
  defp trade_status(_count, diff) when diff <= 2, do: :warn
  defp trade_status(_count, _diff), do: :fail

  @doc """
  Finds ISINs in Actions.csv that are not in the database.
  """
  @spec find_missing_isins(map()) :: check_result()
  def find_missing_isins(%{transactions: transactions}) do
    actions_isins =
      transactions
      |> Enum.map(& &1.isin)
      |> Enum.reject(fn isin -> is_nil(isin) or isin == "" end)
      |> Enum.uniq()

    # Check which ISINs exist in instruments
    known_isins =
      Instrument
      |> where([i], i.isin in ^actions_isins)
      |> select([i], i.isin)
      |> Repo.all()
      |> MapSet.new()

    missing = Enum.reject(actions_isins, &MapSet.member?(known_isins, &1))

    isin_to_symbol = Map.new(transactions, fn txn -> {txn.isin, txn.symbol} end)

    missing_with_symbols =
      Enum.map(missing, fn isin ->
        {isin, Map.get(isin_to_symbol, isin, "?")}
      end)

    status =
      case length(missing) do
        0 -> :pass
        n when n <= 3 -> :warn
        _ -> :fail
      end

    %{
      name: "Missing ISINs",
      status: status,
      message: "#{length(actions_isins)} ISINs in Actions, #{length(missing)} not in DB",
      details:
        Enum.map(missing_with_symbols, fn {isin, symbol} ->
          "#{isin} (#{symbol})"
        end)
    }
  end

  @doc """
  Cross-checks BASE_SUMMARY totals for consistency.
  """
  @spec check_summary_totals(map()) :: check_result()
  def check_summary_totals(%{summary: summary}) do
    ending_cash = summary[:ending_cash]
    starting_cash = summary[:starting_cash]

    if ending_cash && starting_cash do
      %{
        name: "Summary Totals",
        status: :pass,
        message:
          "Period: #{summary[:from_date]}..#{summary[:to_date]}, " <>
            "Starting cash: #{format_decimal(starting_cash)}, " <>
            "Ending cash: #{format_decimal(ending_cash)}, " <>
            "Dividends: #{format_decimal(summary[:dividends])}, " <>
            "Commissions: #{format_decimal(summary[:commissions])}",
        details: []
      }
    else
      %{
        name: "Summary Totals",
        status: :warn,
        message: "Could not extract summary totals from Actions.csv",
        details: []
      }
    end
  end

  defp extract_date_range(summary, transactions) do
    from = summary[:from_date]
    to = summary[:to_date]

    if from && to do
      {from, to}
    else
      # Fallback: derive from transaction dates
      dates =
        transactions
        |> Enum.map(& &1.date)
        |> Enum.reject(&is_nil/1)

      case dates do
        [] -> {nil, nil}
        dates -> {Enum.min(dates, Date), Enum.max(dates, Date)}
      end
    end
  end

  defp format_decimal(nil), do: "N/A"

  defp format_decimal(decimal) do
    decimal |> Decimal.round(2) |> Decimal.to_string()
  end
end
