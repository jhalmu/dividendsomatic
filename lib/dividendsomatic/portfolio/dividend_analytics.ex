defmodule Dividendsomatic.Portfolio.DividendAnalytics do
  @moduledoc """
  Shared dividend analytics: annual per-share, yield, yield-on-cost,
  frequency detection, and Rule of 72 doubling time.

  Used by both StockLive (per-stock detail) and PortfolioLive (per-symbol columns).
  """

  @doc """
  Compute trailing 12-month annual dividend per share.
  Expects a list of `%{dividend: %{ex_date: Date, ...}, ...}` entries.
  """
  def compute_annual_dividend_per_share(dividends_with_income) do
    cutoff = Date.add(Date.utc_today(), -365)

    recent =
      Enum.filter(dividends_with_income, fn entry ->
        Date.compare(entry.dividend.ex_date, cutoff) != :lt
      end)

    if recent == [] do
      Decimal.new("0")
    else
      Enum.reduce(recent, Decimal.new("0"), fn entry, acc ->
        Decimal.add(acc, per_share_amount(entry.dividend))
      end)
    end
  end

  @doc """
  Dividend yield = annual_per_share / price * 100.
  Returns nil when price is missing or zero.
  """
  def compute_dividend_yield(_annual_per_share, nil), do: nil

  def compute_dividend_yield(annual_per_share, quote_data) do
    price = quote_data.current_price

    if price && Decimal.compare(price, Decimal.new("0")) == :gt do
      annual_per_share
      |> Decimal.div(price)
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.round(2)
    else
      nil
    end
  end

  @doc """
  Yield on cost = annual_per_share / avg_cost * 100.
  Returns nil when avg_cost is missing or zero.
  """
  def compute_yield_on_cost(_annual_per_share, nil), do: nil

  def compute_yield_on_cost(annual_per_share, holding_stats) do
    avg_cost = holding_stats.avg_cost

    if avg_cost && Decimal.compare(avg_cost, Decimal.new("0")) == :gt do
      annual_per_share
      |> Decimal.div(avg_cost)
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.round(2)
    else
      nil
    end
  end

  @doc """
  Detect dividend frequency from ex_date gaps.
  Returns "monthly", "quarterly", "semi-annual", "annual", "irregular", or "unknown".
  """
  def detect_dividend_frequency(dividends_with_income) when length(dividends_with_income) < 2,
    do: "unknown"

  def detect_dividend_frequency(dividends_with_income) do
    dates =
      dividends_with_income
      |> Enum.map(& &1.dividend.ex_date)
      |> Enum.sort(Date)

    gaps =
      dates
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> Date.diff(b, a) end)

    avg_gap = Enum.sum(gaps) / length(gaps)

    cond do
      avg_gap < 50 -> "monthly"
      avg_gap < 120 -> "quarterly"
      avg_gap < 220 -> "semi-annual"
      avg_gap < 420 -> "annual"
      true -> "irregular"
    end
  end

  @doc """
  Extract per-share value from a dividend, handling total_net amount_type.
  """
  def per_share_amount(dividend) do
    amount = dividend.amount || Decimal.new("0")

    if dividend.amount_type == "total_net" do
      cond do
        dividend.gross_rate && Decimal.compare(dividend.gross_rate, Decimal.new("0")) == :gt ->
          dividend.gross_rate

        dividend.quantity_at_record &&
            Decimal.compare(dividend.quantity_at_record, Decimal.new("0")) == :gt ->
          Decimal.div(amount, dividend.quantity_at_record)

        true ->
          Decimal.new("0")
      end
    else
      amount
    end
  end

  @doc """
  Rule of 72 doubling time calculation.

  Returns `%{rate, exact_years, approx_years, rule_variant, milestones}`.
  The rule_variant selects the best numerator (R69..R74) based on the rate,
  per the Investopedia adjusted-rule guidance.
  """
  def compute_rule72(rate) when is_number(rate) and rate > 0 do
    exact_years = :math.log(2) / :math.log(1 + rate / 100)

    # Adjusted numerator: 72 + round((rate - 8) / 3)
    # Clamp to 69..74 range
    adjustment = round((rate - 8) / 3)
    numerator = max(69, min(74, 72 + adjustment))
    approx_years = numerator / rate

    milestones =
      for n <- 0..4 do
        multiplier = :math.pow(2, n)
        years = exact_years * n
        %{multiplier: round(multiplier), years: Float.round(years, 1)}
      end

    %{
      rate: Float.round(rate + 0.0, 2),
      exact_years: Float.round(exact_years, 1),
      approx_years: Float.round(approx_years, 1),
      rule_variant: "R#{numerator}",
      milestones: milestones
    }
  end

  def compute_rule72(_), do: nil
end
