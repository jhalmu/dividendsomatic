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
      inconsistent_amounts_per_stock(dividends),
      mixed_amount_types_per_stock(dividends),
      missing_fx_conversion(dividends),
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

  # ~$50 USD equivalent per-share thresholds by currency
  @suspicious_thresholds %{
    "USD" => "50",
    "EUR" => "50",
    "CAD" => "70",
    "GBP" => "40",
    "GBp" => "4000",
    "CHF" => "50",
    "AUD" => "80",
    "NZD" => "85",
    "SGD" => "70",
    "HKD" => "400",
    "JPY" => "7500",
    "NOK" => "550",
    "SEK" => "550",
    "DKK" => "350",
    "TWD" => "1600"
  }

  @doc """
  Flags per-share amounts that seem unreasonably high (~$50 USD equivalent, currency-aware).
  """
  def suspicious_amounts(dividends) do
    dividends
    |> Enum.filter(fn d ->
      threshold = Map.get(@suspicious_thresholds, d.currency, "50")

      d.amount_type == "per_share" and
        Decimal.compare(d.amount, Decimal.new(threshold)) == :gt
    end)
    |> Enum.map(fn d ->
      threshold = Map.get(@suspicious_thresholds, d.currency, "50")

      %{
        severity: :warning,
        type: :suspicious_amount,
        symbol: d.symbol,
        ex_date: d.ex_date,
        detail: "Per-share amount #{d.amount} #{d.currency} seems high (threshold: #{threshold})"
      }
    end)
  end

  @doc """
  Flags stocks where per_share amounts vary >10x from the median, indicating
  possible misclassified total_net amounts.
  """
  def inconsistent_amounts_per_stock(dividends) do
    dividends
    |> Enum.filter(&(&1.amount_type == "per_share"))
    |> Enum.group_by(fn d -> d.isin || "symbol:#{d.symbol}" end)
    |> Enum.flat_map(fn {_key, group} -> find_outliers(group) end)
  end

  defp find_outliers(group) when length(group) < 2, do: []

  defp find_outliers(group) do
    amounts = Enum.map(group, fn d -> Decimal.to_float(d.amount) end) |> Enum.sort()
    median = Enum.at(amounts, div(length(amounts), 2))

    group
    |> Enum.filter(fn d ->
      val = Decimal.to_float(d.amount)
      median > 0 && (val / median > 10 || median / val > 10)
    end)
    |> Enum.map(fn d ->
      %{
        severity: :warning,
        type: :inconsistent_amount,
        symbol: d.symbol,
        isin: d.isin,
        ex_date: d.ex_date,
        detail: "Per-share amount #{d.amount} varies >10x from median for this stock"
      }
    end)
  end

  @doc """
  Flags stocks that have both per_share and total_net records, which requires
  the UI to handle both types correctly.
  """
  def mixed_amount_types_per_stock(dividends) do
    dividends
    |> Enum.group_by(fn d -> d.isin || "symbol:#{d.symbol}" end)
    |> Enum.flat_map(fn {_key, group} ->
      types = group |> Enum.map(& &1.amount_type) |> Enum.uniq()

      if "per_share" in types and "total_net" in types do
        sample = hd(group)

        [
          %{
            severity: :info,
            type: :mixed_amount_types,
            symbol: sample.symbol,
            isin: sample.isin,
            detail:
              "Stock has both per_share (#{count_type(group, "per_share")}) and total_net (#{count_type(group, "total_net")}) records"
          }
        ]
      else
        []
      end
    end)
  end

  defp count_type(group, type) do
    Enum.count(group, &(&1.amount_type == type))
  end

  @doc """
  Flags total_net dividends in non-EUR currencies where fx_rate is missing or 1.0,
  which would produce inflated income (native amount treated as EUR).
  """
  def missing_fx_conversion(dividends) do
    dividends
    |> Enum.filter(fn d ->
      d.amount_type == "total_net" and d.currency != "EUR" and
        (is_nil(d.fx_rate) or Decimal.equal?(d.fx_rate, Decimal.new("1")))
    end)
    |> Enum.map(fn d ->
      %{
        severity: :warning,
        type: :missing_fx_conversion,
        symbol: d.symbol,
        isin: d.isin,
        ex_date: d.ex_date,
        detail:
          "total_net #{d.currency} dividend without fx_rate — income will be inflated (~#{d.currency} treated as EUR)"
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

  @doc """
  Analyzes flagged dividends and suggests threshold adjustments for currencies
  with 3+ flags. Uses 95th percentile * 1.2 as the suggested threshold.
  """
  def suggest_threshold_adjustments do
    dividends =
      Dividend
      |> where([d], d.amount_type == "per_share")
      |> Repo.all()

    flagged = suspicious_amounts(dividends)

    flagged
    |> Enum.group_by(fn issue ->
      # Extract currency from detail string
      case Regex.run(~r/(\w+) seems high/, issue.detail) do
        [_, currency] -> currency
        _ -> nil
      end
    end)
    |> Map.delete(nil)
    |> Enum.filter(fn {_currency, items} -> length(items) >= 3 end)
    |> Enum.map(fn {currency, items} ->
      # Find actual per_share amounts for flagged items by matching symbol+date
      flagged_keys = MapSet.new(items, fn i -> {i.symbol, i.ex_date} end)

      amounts =
        dividends
        |> Enum.filter(fn d ->
          d.currency == currency and MapSet.member?(flagged_keys, {d.symbol, d.ex_date})
        end)
        |> Enum.map(fn d -> Decimal.to_float(d.amount) end)
        |> Enum.sort()

      p95_index = max(0, ceil(length(amounts) * 0.95) - 1)
      p95 = Enum.at(amounts, p95_index, 0.0)
      suggested = ceil(p95 * 1.2)
      current = Map.get(@suspicious_thresholds, currency, "50")

      %{
        currency: currency,
        current_threshold: current,
        suggested_threshold: Integer.to_string(suggested),
        flagged_count: length(items)
      }
    end)
  end

  defp group_by_severity(issues) do
    issues
    |> Enum.group_by(& &1.severity)
    |> Map.new(fn {severity, items} -> {severity, length(items)} end)
  end
end
