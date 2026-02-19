defmodule Dividendsomatic.Portfolio.MarginRates do
  @moduledoc """
  IBKR margin interest rate reference data.

  Rates are Benchmark (BM) + spread, tiered by balance.
  Source: IBKR published margin rates (as of Feb 2026).

  IBKR uses central bank rates as benchmarks:
  - EUR: ECB deposit facility rate
  - USD: Fed Funds effective rate
  - SEK: Riksbank repo rate
  - DKK: Danmarks Nationalbank rate
  - NOK: Norges Bank sight deposit rate
  - GBP: Bank of England base rate
  """

  @doc """
  Returns the spread (above benchmark) for a given currency and loan balance tier.

  IBKR tiered spreads for debit balances (borrowing):
  - Tier 1: 0 - 100K  → BM + 1.5%
  - Tier 2: 100K - 1M → BM + 1.0%
  - Tier 3: 1M - 50M  → BM + 0.75% (not relevant for this portfolio)
  """
  def spread_for_balance(balance) do
    balance_f = Decimal.to_float(balance)

    cond do
      balance_f <= 100_000 -> Decimal.new("1.5")
      balance_f <= 1_000_000 -> Decimal.new("1.0")
      true -> Decimal.new("0.75")
    end
  end

  @doc """
  Returns current benchmark rates by currency.

  These should be updated periodically to reflect central bank rate changes.
  Last updated: 2026-02-19
  """
  def benchmark_rates do
    %{
      "EUR" => Decimal.new("2.75"),
      "USD" => Decimal.new("4.33"),
      "SEK" => Decimal.new("2.25"),
      "DKK" => Decimal.new("2.60"),
      "NOK" => Decimal.new("4.50"),
      "GBP" => Decimal.new("4.50")
    }
  end

  @doc """
  Returns the benchmark rate for a currency, defaulting to EUR.
  """
  def benchmark_rate(currency) do
    Map.get(benchmark_rates(), currency, benchmark_rates()["EUR"])
  end

  @doc """
  Calculates the effective annual interest rate for a margin loan.

  Rate = Benchmark + Spread (tiered by balance)
  """
  def effective_rate(currency, balance) do
    bm = benchmark_rate(currency)
    spread = spread_for_balance(Decimal.abs(balance))
    Decimal.add(bm, spread)
  end

  @doc """
  Calculates expected annual interest cost for a margin loan amount.

  Returns the cost as a positive Decimal (cost to the borrower).
  """
  def expected_annual_cost(currency, loan_amount) do
    abs_loan = Decimal.abs(loan_amount)
    rate = effective_rate(currency, abs_loan)

    abs_loan
    |> Decimal.mult(rate)
    |> Decimal.div(Decimal.new("100"))
    |> Decimal.round(2)
  end

  @doc """
  Calculates expected daily interest cost.
  """
  def expected_daily_cost(currency, loan_amount) do
    expected_annual_cost(currency, loan_amount)
    |> Decimal.div(Decimal.new("365"))
    |> Decimal.round(4)
  end

  @doc """
  Returns a summary of rate information for display.
  """
  def rate_summary(currency, loan_amount) do
    abs_loan = Decimal.abs(loan_amount)
    bm = benchmark_rate(currency)
    spread = spread_for_balance(abs_loan)
    rate = Decimal.add(bm, spread)
    annual_cost = expected_annual_cost(currency, loan_amount)

    %{
      currency: currency,
      benchmark: bm,
      spread: spread,
      effective_rate: rate,
      loan_amount: abs_loan,
      annual_cost: annual_cost,
      monthly_cost: annual_cost |> Decimal.div(Decimal.new("12")) |> Decimal.round(2)
    }
  end
end
