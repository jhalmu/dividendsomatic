defmodule Mix.Tasks.Audit.Dividends do
  @moduledoc """
  Audit dividend data quality across the portfolio.

  Sections:
  1. Active positions without dividend_rate
  2. Instruments with payments but no rate
  3. Source breakdown (yahoo, ttm_computed, manual, nil)
  4. Yahoo vs TTM discrepancies (>30% divergence)
  5. Stale data (dividend_updated_at > 90 days ago)

  Usage:
    mix audit.dividends
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{
    DividendAnalytics,
    DividendPayment,
    Instrument,
    Position,
    PortfolioSnapshot
  }

  alias Dividendsomatic.Repo

  @shortdoc "Audit dividend data quality"

  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("=== Dividend Data Audit ===\n")

    active_without_rate()
    payments_without_rate()
    source_breakdown()
    yahoo_ttm_discrepancies()
    stale_data()
  end

  # --- Section 1: Active positions without dividend_rate ---

  defp active_without_rate do
    IO.puts("--- 1. Active Positions Without Dividend Rate ---")

    latest_snapshot =
      PortfolioSnapshot
      |> order_by([s], desc: s.date)
      |> limit(1)
      |> Repo.one()

    case latest_snapshot do
      nil ->
        IO.puts("  No snapshots found\n")

      snapshot ->
        results =
          Position
          |> join(:left, [p], i in Instrument, on: p.isin == i.isin)
          |> where([p], p.portfolio_snapshot_id == ^snapshot.id)
          |> where([p, i], is_nil(i.dividend_rate) or i.dividend_rate == ^Decimal.new("0"))
          |> select([p, i], {p.isin, p.symbol, i.name, i.dividend_source})
          |> Repo.all()
          |> Enum.uniq_by(fn {isin, _, _, _} -> isin end)

        if results == [] do
          IO.puts("  All active positions have dividend rates\n")
        else
          IO.puts("  #{length(results)} positions missing rates:")

          Enum.each(results, fn {isin, symbol, name, source} ->
            IO.puts("    #{symbol || "?"} (#{name || isin}) [source: #{source || "nil"}]")
          end)

          IO.puts("")
        end
    end
  end

  # --- Section 2: Instruments with payments but no rate ---

  defp payments_without_rate do
    IO.puts("--- 2. Instruments With Payments But No Rate ---")

    results =
      Instrument
      |> join(:inner, [i], dp in DividendPayment, on: dp.instrument_id == i.id)
      |> where([i], is_nil(i.dividend_rate) or i.dividend_rate == ^Decimal.new("0"))
      |> group_by([i], [i.id, i.isin, i.name, i.symbol])
      |> select([i, dp], {i.isin, i.name, i.symbol, count(dp.id)})
      |> Repo.all()

    if results == [] do
      IO.puts("  All instruments with payments have rates\n")
    else
      IO.puts("  #{length(results)} instruments — candidates for mix backfill.dividend_rates:")

      Enum.each(results, fn {isin, name, symbol, payment_count} ->
        IO.puts("    #{symbol || "?"} (#{name || isin}) — #{payment_count} payments")
      end)

      IO.puts("")
    end
  end

  # --- Section 3: Source breakdown ---

  defp source_breakdown do
    IO.puts("--- 3. Source Breakdown ---")

    results =
      Instrument
      |> where([i], not is_nil(i.dividend_rate))
      |> where([i], i.dividend_rate > ^Decimal.new("0"))
      |> group_by([i], i.dividend_source)
      |> select([i], {i.dividend_source, count(i.id)})
      |> Repo.all()

    nil_count =
      Instrument
      |> where([i], is_nil(i.dividend_rate) or i.dividend_rate == ^Decimal.new("0"))
      |> select([i], count(i.id))
      |> Repo.one()

    total = Enum.reduce(results, nil_count, fn {_, c}, acc -> acc + c end)

    Enum.each(results, fn {source, count} ->
      IO.puts("  #{source || "nil"}: #{count}")
    end)

    IO.puts("  no rate: #{nil_count}")
    IO.puts("  total instruments: #{total}\n")
  end

  # --- Section 4: Yahoo vs TTM discrepancies ---

  defp yahoo_ttm_discrepancies do
    IO.puts("--- 4. Yahoo vs TTM Discrepancies (>30%) ---")

    instruments =
      Instrument
      |> where([i], i.dividend_source == "yahoo")
      |> where([i], not is_nil(i.dividend_rate))
      |> where([i], i.dividend_rate > ^Decimal.new("0"))
      |> Repo.all()

    discrepancies =
      Enum.reduce(instruments, [], fn instrument, acc ->
        payments = recent_payments(instrument.id)

        if payments == [] do
          acc
        else
          enriched = adapt_payments(payments)
          frequency = DividendAnalytics.detect_dividend_frequency(enriched)
          freq_atom = frequency_string_to_atom(frequency)
          ttm_rate = DividendAnalytics.compute_annual_dividend_per_share(enriched, freq_atom)

          if Decimal.compare(ttm_rate, Decimal.new("0")) == :gt do
            ratio = Decimal.div(instrument.dividend_rate, ttm_rate)

            if Decimal.compare(ratio, Decimal.new("1.3")) == :gt ||
                 Decimal.compare(ratio, Decimal.new("0.7")) == :lt do
              [{instrument, ttm_rate, ratio} | acc]
            else
              acc
            end
          else
            acc
          end
        end
      end)

    if discrepancies == [] do
      IO.puts("  No significant discrepancies found\n")
    else
      IO.puts("  #{length(discrepancies)} discrepancies found:")

      Enum.each(discrepancies, fn {instrument, ttm_rate, ratio} ->
        pct = Decimal.mult(ratio, Decimal.new("100")) |> Decimal.round(0)

        IO.puts(
          "    #{instrument.symbol || "?"} (#{instrument.name || instrument.isin}) — " <>
            "yahoo=#{instrument.dividend_rate} ttm=#{ttm_rate} (#{pct}%)"
        )
      end)

      IO.puts("")
    end
  end

  # --- Section 5: Stale data ---

  defp stale_data do
    IO.puts("--- 5. Stale Data (>90 days) ---")

    cutoff = DateTime.add(DateTime.utc_now(), -90 * 24 * 3600, :second)

    results =
      Instrument
      |> where([i], not is_nil(i.dividend_rate))
      |> where([i], i.dividend_rate > ^Decimal.new("0"))
      |> where(
        [i],
        is_nil(i.dividend_updated_at) or i.dividend_updated_at < ^cutoff
      )
      |> select([i], {i.isin, i.name, i.symbol, i.dividend_source, i.dividend_updated_at})
      |> Repo.all()

    if results == [] do
      IO.puts("  All dividend data is recent\n")
    else
      IO.puts("  #{length(results)} instruments with stale data:")

      Enum.each(results, fn {isin, name, symbol, source, updated_at} ->
        age =
          if updated_at,
            do: "#{div(DateTime.diff(DateTime.utc_now(), updated_at, :second), 86400)}d ago",
            else: "never"

        IO.puts("    #{symbol || "?"} (#{name || isin}) [#{source || "nil"}] updated: #{age}")
      end)

      IO.puts("")
    end
  end

  # --- Helpers ---

  defp recent_payments(instrument_id) do
    cutoff = Date.add(Date.utc_today(), -365)

    DividendPayment
    |> where([dp], dp.instrument_id == ^instrument_id)
    |> where([dp], dp.pay_date >= ^cutoff)
    |> order_by([dp], asc: dp.pay_date)
    |> preload(:instrument)
    |> Repo.all()
  end

  defp adapt_payments(payments) do
    Enum.map(payments, fn payment ->
      %{
        dividend: %{
          ex_date: payment.pay_date,
          amount: payment.net_amount,
          amount_type: "total_net",
          gross_rate: payment.per_share,
          quantity_at_record: payment.quantity
        },
        income: payment.net_amount
      }
    end)
  end

  defp frequency_string_to_atom("monthly"), do: :monthly
  defp frequency_string_to_atom("quarterly"), do: :quarterly
  defp frequency_string_to_atom("semi-annual"), do: :semi_annual
  defp frequency_string_to_atom("annual"), do: :annual
  defp frequency_string_to_atom(_), do: :unknown
end
