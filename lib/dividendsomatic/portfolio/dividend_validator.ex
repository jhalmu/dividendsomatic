defmodule Dividendsomatic.Portfolio.DividendValidator do
  @moduledoc """
  Validates dividend data integrity.

  Checks currency codes, ISIN-currency consistency, amount reasonableness,
  and cross-source duplicate detection.
  """

  import Ecto.Query

  alias Dividendsomatic.Portfolio.Dividend
  alias Dividendsomatic.Repo

  @valid_currencies ~w(USD EUR CAD GBP GBp JPY HKD NOK SEK DKK CHF AUD NZD SGD TWD)

  @isin_currency_map %{
    "US" => ["USD"],
    "CA" => ["CAD"],
    "SE" => ["SEK"],
    "FI" => ["EUR"],
    "DE" => ["EUR"],
    "FR" => ["EUR"],
    "NL" => ["EUR"],
    "IE" => ["EUR", "USD"],
    "NO" => ["NOK"],
    "JP" => ["JPY"],
    "GB" => ["GBP", "GBp"],
    "HK" => ["HKD"],
    "DK" => ["DKK"],
    "CH" => ["CHF"],
    "AU" => ["AUD"]
  }

  @doc """
  Runs all validations and returns a report.
  """
  def validate do
    dividends = Dividend |> order_by([d], asc: d.ex_date) |> Repo.all()

    issues = [
      invalid_currencies(dividends),
      isin_currency_mismatches(dividends),
      suspicious_amounts(dividends),
      cross_source_duplicates()
    ]

    all_issues = List.flatten(issues)

    %{
      total_checked: length(dividends),
      issue_count: length(all_issues),
      issues: all_issues,
      by_severity: group_by_severity(all_issues)
    }
  end

  @doc """
  Validates that all currency codes are known.
  """
  def invalid_currencies(dividends) do
    dividends
    |> Enum.reject(fn d -> d.currency in @valid_currencies end)
    |> Enum.map(fn d ->
      %{
        severity: :warning,
        type: :invalid_currency,
        symbol: d.symbol,
        ex_date: d.ex_date,
        detail: "Unknown currency: #{d.currency}"
      }
    end)
  end

  @doc """
  Validates that ISIN country prefix matches the dividend currency.
  """
  def isin_currency_mismatches(dividends) do
    dividends
    |> Enum.filter(&(&1.isin && byte_size(&1.isin) >= 2))
    |> Enum.reject(fn d ->
      country = String.slice(d.isin, 0, 2)
      expected = Map.get(@isin_currency_map, country)
      is_nil(expected) or d.currency in expected
    end)
    |> Enum.map(fn d ->
      country = String.slice(d.isin, 0, 2)
      expected = Map.get(@isin_currency_map, country, [])

      %{
        severity: :info,
        type: :isin_currency_mismatch,
        symbol: d.symbol,
        isin: d.isin,
        ex_date: d.ex_date,
        detail: "ISIN #{country} expects #{inspect(expected)}, got #{d.currency}"
      }
    end)
  end

  @doc """
  Flags per-share amounts that seem unreasonably high.
  """
  def suspicious_amounts(dividends) do
    dividends
    |> Enum.filter(fn d ->
      d.amount_type == "per_share" and
        Decimal.compare(d.amount, Decimal.new("1000")) == :gt
    end)
    |> Enum.map(fn d ->
      %{
        severity: :warning,
        type: :suspicious_amount,
        symbol: d.symbol,
        ex_date: d.ex_date,
        detail: "Per-share amount #{d.amount} #{d.currency} seems high"
      }
    end)
  end

  @doc """
  Detects duplicate ISIN+date records across different sources.
  """
  def cross_source_duplicates do
    Dividend
    |> where([d], not is_nil(d.isin))
    |> group_by([d], [d.isin, d.ex_date])
    |> having([d], count(d.id) > 1)
    |> select([d], %{isin: d.isin, ex_date: d.ex_date, count: count(d.id)})
    |> Repo.all()
    |> Enum.map(fn dup ->
      %{
        severity: :warning,
        type: :duplicate,
        isin: dup.isin,
        ex_date: dup.ex_date,
        detail: "#{dup.count} records for ISIN #{dup.isin} on #{dup.ex_date}"
      }
    end)
  end

  defp group_by_severity(issues) do
    issues
    |> Enum.group_by(& &1.severity)
    |> Map.new(fn {severity, items} -> {severity, length(items)} end)
  end
end
