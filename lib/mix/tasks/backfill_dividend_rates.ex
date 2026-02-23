defmodule Mix.Tasks.Backfill.DividendRates do
  @moduledoc """
  Backfill dividend rates from payment history (TTM) and manual overrides.

  Manual overrides are applied first (protected from Yahoo overwrite).
  Then TTM rates are computed from actual dividend_payments for instruments
  that are missing rates or where Yahoo data diverges significantly.

  Usage:
    mix backfill.dividend_rates              # All instruments with payments
    mix backfill.dividend_rates --dry-run    # Preview changes
    mix backfill.dividend_rates --force      # Overwrite even close values
    mix backfill.dividend_rates ISIN         # Single instrument
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{DividendAnalytics, DividendPayment, Instrument}
  alias Dividendsomatic.Repo

  @shortdoc "Backfill dividend rates from payment history and manual overrides"

  # Manual overrides for instruments where Yahoo returns incorrect data.
  # These are set with dividend_source: "manual" and protected from overwrite.
  @manual_overrides %{
    "SE0000667925" => %{dividend_rate: Decimal.new("2.03"), dividend_frequency: "quarterly"},
    # TRIN: base monthly $0.17 × 12 = $2.04 (excludes quarterly supplementals).
    # IBKR reference yield 13.63% uses base rate only.
    "US8964423086" => %{dividend_rate: Decimal.new("2.04"), dividend_frequency: "monthly"},
    # TCPC: quarterly $0.25 × 4 = $1.00. BDC with PIL splits that inflate TTM.
    "US09259E1082" => %{dividend_rate: Decimal.new("1.00"), dividend_frequency: "quarterly"},
    # Nordea: switching to semi-annual in 2026. 0.96 is FY2025 dividend;
    # mid-year 2026 payment TBD (~50% of H1 profit). Update when announced.
    "FI4000297767" => %{dividend_rate: Decimal.new("0.96"), dividend_frequency: "semi_annual"}
  }

  def run(args) do
    Mix.Task.run("app.start")

    dry_run? = "--dry-run" in args
    force? = "--force" in args
    clean_args = Enum.reject(args, &String.starts_with?(&1, "--"))
    target_isin = if clean_args != [], do: hd(clean_args), else: nil

    IO.puts("--- Backfill Dividend Rates #{if dry_run?, do: "(DRY RUN) "}---\n")

    # Phase 1: Manual overrides
    {manual_applied, manual_skipped} = apply_manual_overrides(target_isin, dry_run?)

    # Phase 2: TTM computation from payment history
    {ttm_updated, ttm_skipped, ttm_no_data} =
      compute_ttm_rates(target_isin, dry_run?, force?)

    IO.puts("\n--- Summary ---")
    IO.puts("  Manual overrides applied: #{manual_applied} (skipped: #{manual_skipped})")
    IO.puts("  TTM computed: #{ttm_updated} (skipped: #{ttm_skipped}, no data: #{ttm_no_data})")
  end

  # --- Phase 1: Manual overrides ---

  defp apply_manual_overrides(target_isin, dry_run?) do
    overrides =
      if target_isin do
        case Map.fetch(@manual_overrides, target_isin) do
          {:ok, data} -> [{target_isin, data}]
          :error -> []
        end
      else
        Map.to_list(@manual_overrides)
      end

    IO.puts("Phase 1: Manual overrides (#{length(overrides)} entries)")

    Enum.reduce(overrides, {0, 0}, fn {isin, data}, {applied, skipped} ->
      case Repo.get_by(Instrument, isin: isin) do
        nil ->
          IO.puts("  #{isin} — instrument not found, skipping")
          {applied, skipped + 1}

        instrument ->
          IO.write("  #{instrument.name || isin} (#{isin})")

          if dry_run? do
            IO.puts(" — would set rate=#{data.dividend_rate} freq=#{data.dividend_frequency}")
            {applied + 1, skipped}
          else
            attrs = %{
              dividend_rate: data.dividend_rate,
              dividend_frequency: data.dividend_frequency,
              dividend_source: "manual",
              dividend_updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
            }

            case instrument |> Instrument.changeset(attrs) |> Repo.update() do
              {:ok, _} ->
                IO.puts(" — set rate=#{data.dividend_rate} freq=#{data.dividend_frequency}")
                {applied + 1, skipped}

              {:error, reason} ->
                IO.puts(" — FAILED: #{inspect(reason)}")
                {applied, skipped + 1}
            end
          end
      end
    end)
  end

  # --- Phase 2: TTM computation ---

  defp compute_ttm_rates(target_isin, dry_run?, force?) do
    instruments = instruments_with_payments(target_isin)
    IO.puts("\nPhase 2: TTM computation (#{length(instruments)} instruments with payments)")

    Enum.reduce(instruments, {0, 0, 0}, fn instrument, {updated, skipped, no_data} ->
      if instrument.dividend_source == "manual" do
        IO.puts("  #{instrument.name || instrument.isin} — manual source, skipping")
        {updated, skipped + 1, no_data}
      else
        compute_ttm_for_instrument(instrument, dry_run?, force?, {updated, skipped, no_data})
      end
    end)
  end

  defp compute_ttm_for_instrument(instrument, dry_run?, force?, {updated, skipped, no_data}) do
    {payments, historical?} =
      case recent_payments(instrument.id) do
        [] -> {historical_payments(instrument.id), true}
        recent -> {recent, false}
      end

    if payments == [] do
      {updated, skipped, no_data + 1}
    else
      enriched = adapt_payments(payments)
      frequency = DividendAnalytics.detect_dividend_frequency(enriched)
      freq_atom = frequency_string_to_atom(frequency)

      # DividendAnalytics filters to last 365 days from today, so for
      # historical payments we compute the rate directly from loaded data
      ttm_rate =
        if historical? do
          compute_rate_from_payments(enriched, freq_atom)
        else
          DividendAnalytics.compute_annual_dividend_per_share(enriched, freq_atom)
        end

      if Decimal.compare(ttm_rate, Decimal.new("0")) == :eq do
        {updated, skipped, no_data + 1}
      else
        decide_update(
          instrument,
          ttm_rate,
          frequency,
          dry_run?,
          force?,
          {updated, skipped, no_data}
        )
      end
    end
  end

  # Compute annual rate directly from loaded payments (no date filtering).
  # Deduplicates PIL/withholding splits: same (date, per_share) counted once.
  defp compute_rate_from_payments(enriched, frequency) do
    unique_entries =
      enriched
      |> Enum.map(fn entry ->
        {entry.dividend.ex_date, DividendAnalytics.per_share_amount(entry.dividend)}
      end)
      |> Enum.reject(fn {_, ps} -> Decimal.compare(ps, Decimal.new("0")) == :eq end)
      |> Enum.uniq_by(fn {date, ps} -> {date, Decimal.to_string(ps)} end)

    per_share_values = Enum.map(unique_entries, fn {_, ps} -> ps end)
    sum = Enum.reduce(per_share_values, Decimal.new("0"), &Decimal.add/2)

    payment_count =
      unique_entries |> Enum.map(fn {date, _} -> date end) |> Enum.uniq() |> length()

    expected_annual = DividendAnalytics.frequency_to_count(frequency)

    if expected_annual > 0 and payment_count > 0 and payment_count < expected_annual do
      avg = Decimal.div(sum, Decimal.new(payment_count))
      Decimal.mult(avg, Decimal.new(expected_annual))
    else
      sum
    end
  end

  defp decide_update(
         instrument,
         ttm_rate,
         frequency,
         dry_run?,
         force?,
         {updated, skipped, no_data}
       ) do
    current = instrument.dividend_rate
    name = instrument.name || instrument.isin

    cond do
      # No existing rate — always update
      is_nil(current) || Decimal.compare(current, Decimal.new("0")) == :eq ->
        do_update(instrument, ttm_rate, frequency, dry_run?, "nil→#{ttm_rate}", name)
        {updated + 1, skipped, no_data}

      # Force mode — always update
      force? ->
        do_update(
          instrument,
          ttm_rate,
          frequency,
          dry_run?,
          "#{current}→#{ttm_rate} (forced)",
          name
        )

        {updated + 1, skipped, no_data}

      # Yahoo rate diverges >2x from TTM — TTM is likely more accurate
      diverges?(current, ttm_rate) ->
        do_update(
          instrument,
          ttm_rate,
          frequency,
          dry_run?,
          "#{current}→#{ttm_rate} (diverged >2x)",
          name
        )

        {updated + 1, skipped, no_data}

      true ->
        IO.puts("  #{name} — rate=#{current} ttm=#{ttm_rate} (close enough, skipping)")
        {updated, skipped + 1, no_data}
    end
  end

  defp do_update(instrument, ttm_rate, frequency, dry_run?, reason, name) do
    if dry_run? do
      IO.puts("  #{name} — would update: #{reason} freq=#{frequency}")
    else
      attrs = %{
        dividend_rate: ttm_rate,
        dividend_frequency: frequency,
        dividend_source: "ttm_computed",
        dividend_updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      case instrument |> Instrument.changeset(attrs) |> Repo.update() do
        {:ok, _} -> IO.puts("  #{name} — updated: #{reason} freq=#{frequency}")
        {:error, err} -> IO.puts("  #{name} — FAILED: #{inspect(err)}")
      end
    end
  end

  defp diverges?(current, ttm) do
    ratio = Decimal.div(current, ttm)

    Decimal.compare(ratio, Decimal.new("2")) == :gt ||
      Decimal.compare(ratio, Decimal.new("0.5")) == :lt
  end

  # --- Queries ---

  defp instruments_with_payments(nil) do
    Instrument
    |> join(:inner, [i], dp in DividendPayment, on: dp.instrument_id == i.id)
    |> group_by([i], i.id)
    |> select([i], i)
    |> Repo.all()
  end

  defp instruments_with_payments(isin) do
    case Repo.get_by(Instrument, isin: isin) do
      nil ->
        IO.puts("  Instrument #{isin} not found")
        []

      instrument ->
        [instrument]
    end
  end

  defp recent_payments(instrument_id) do
    cutoff = Date.add(Date.utc_today(), -365)

    DividendPayment
    |> where([dp], dp.instrument_id == ^instrument_id)
    |> where([dp], dp.pay_date >= ^cutoff)
    |> order_by([dp], asc: dp.pay_date)
    |> preload(:instrument)
    |> Repo.all()
  end

  # Fallback: take the most recent 365-day window from historical payments
  defp historical_payments(instrument_id) do
    latest =
      DividendPayment
      |> where([dp], dp.instrument_id == ^instrument_id)
      |> order_by([dp], desc: dp.pay_date)
      |> limit(1)
      |> Repo.one()

    case latest do
      nil ->
        []

      payment ->
        cutoff = Date.add(payment.pay_date, -365)

        DividendPayment
        |> where([dp], dp.instrument_id == ^instrument_id)
        |> where([dp], dp.pay_date >= ^cutoff)
        |> order_by([dp], asc: dp.pay_date)
        |> preload(:instrument)
        |> Repo.all()
    end
  end

  # Adapt DividendPayment records to the shape DividendAnalytics expects:
  # %{dividend: %{ex_date, amount, amount_type, gross_rate, quantity_at_record}, income: ...}
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
