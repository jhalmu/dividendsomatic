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

  # IBKR declared per-share rates as source of truth.
  # dividend_rate = dividend_per_payment × payments_per_year (annual)
  # All rates set with dividend_source: "declared" and protected from overwrite.
  #
  # IBKR Reference (target values):
  # AGNC $0.12/mo, CSWC $0.1934/mo, FSK $0.645/q, KESKOB €0.22/q,
  # MANTA €0.33/yr, NDA FI €0.94/yr, OBDC $0.37/5x, ORC $0.12/mo,
  # TCPC $0.25/q, TRIN $0.17/mo
  @manual_overrides %{
    # AGNC: monthly $0.12 × 12 = $1.44
    "US00123Q1040" => %{
      dividend_per_payment: Decimal.new("0.12"),
      payments_per_year: 12,
      dividend_rate: Decimal.new("1.44"),
      dividend_frequency: "monthly"
    },
    # CSWC: monthly $0.1934 × 12 = $2.3208 (base; supplementals excluded)
    "US22822P1012" => %{
      dividend_per_payment: Decimal.new("0.1934"),
      payments_per_year: 12,
      dividend_rate: Decimal.new("2.3208"),
      dividend_frequency: "monthly"
    },
    # FSK: quarterly $0.645 × 4 = $2.58
    "US3023FL1045" => %{
      dividend_per_payment: Decimal.new("0.645"),
      payments_per_year: 4,
      dividend_rate: Decimal.new("2.58"),
      dividend_frequency: "quarterly"
    },
    # KESKOB: quarterly €0.22 × 4 = €0.88
    "FI0009000202" => %{
      dividend_per_payment: Decimal.new("0.22"),
      payments_per_year: 4,
      dividend_rate: Decimal.new("0.88"),
      dividend_frequency: "quarterly"
    },
    # MANTA: annual €0.33 × 1 = €0.33
    "FI4000540470" => %{
      dividend_per_payment: Decimal.new("0.33"),
      payments_per_year: 1,
      dividend_rate: Decimal.new("0.33"),
      dividend_frequency: "annual"
    },
    # NDA FI (Nordea): annual €0.94 × 1 = €0.94
    "FI4000297767" => %{
      dividend_per_payment: Decimal.new("0.94"),
      payments_per_year: 1,
      dividend_rate: Decimal.new("0.94"),
      dividend_frequency: "annual"
    },
    # OBDC: 5 payments/year $0.37 × 5 = $1.85
    "US27579R1041" => %{
      dividend_per_payment: Decimal.new("0.37"),
      payments_per_year: 5,
      dividend_rate: Decimal.new("1.85"),
      dividend_frequency: "irregular"
    },
    # ORC: monthly $0.12 × 12 = $1.44
    "US68571X3017" => %{
      dividend_per_payment: Decimal.new("0.12"),
      payments_per_year: 12,
      dividend_rate: Decimal.new("1.44"),
      dividend_frequency: "monthly"
    },
    # TCPC: quarterly $0.25 × 4 = $1.00
    "US09259E1082" => %{
      dividend_per_payment: Decimal.new("0.25"),
      payments_per_year: 4,
      dividend_rate: Decimal.new("1.00"),
      dividend_frequency: "quarterly"
    },
    # TRIN: monthly $0.17 × 12 = $2.04 (base only, excludes supplementals)
    "US8964423086" => %{
      dividend_per_payment: Decimal.new("0.17"),
      payments_per_year: 12,
      dividend_rate: Decimal.new("2.04"),
      dividend_frequency: "monthly"
    },
    # ABB: quarterly CHF 2.03/yr (legacy override kept)
    "SE0000667925" => %{
      dividend_per_payment: Decimal.new("0.5075"),
      payments_per_year: 4,
      dividend_rate: Decimal.new("2.03"),
      dividend_frequency: "quarterly"
    }
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

    Enum.reduce(overrides, {0, 0}, fn {isin, data}, acc ->
      case Repo.get_by(Instrument, isin: isin) do
        nil ->
          IO.puts("  #{isin} — instrument not found, skipping")
          increment_skipped(acc)

        instrument ->
          apply_single_override(instrument, isin, data, dry_run?, acc)
      end
    end)
  end

  defp apply_single_override(instrument, isin, data, dry_run?, acc) do
    per_pay = data[:dividend_per_payment]
    freq = data[:payments_per_year]
    IO.write("  #{instrument.name || isin} (#{isin})")

    if dry_run? do
      IO.puts(
        " — would set per_payment=#{per_pay} × #{freq}/yr = #{data.dividend_rate} freq=#{data.dividend_frequency}"
      )

      increment_applied(acc)
    else
      persist_manual_override(instrument, data, acc)
    end
  end

  defp persist_manual_override(instrument, data, acc) do
    attrs =
      %{
        dividend_rate: data.dividend_rate,
        dividend_frequency: data.dividend_frequency,
        dividend_source: "declared",
        dividend_updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> maybe_put(:dividend_per_payment, data[:dividend_per_payment])
      |> maybe_put(:payments_per_year, data[:payments_per_year])

    case instrument |> Instrument.changeset(attrs) |> Repo.update() do
      {:ok, _} ->
        IO.puts(
          " — set per_payment=#{data[:dividend_per_payment]} × #{data[:payments_per_year]}/yr freq=#{data.dividend_frequency}"
        )

        increment_applied(acc)

      {:error, reason} ->
        IO.puts(" — FAILED: #{inspect(reason)}")
        increment_skipped(acc)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp increment_applied({applied, skipped}), do: {applied + 1, skipped}
  defp increment_skipped({applied, skipped}), do: {applied, skipped + 1}

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
    ppy = frequency_to_payments_per_year(frequency)

    per_payment =
      if ppy > 0, do: Decimal.div(ttm_rate, Decimal.new(ppy)), else: nil

    if dry_run? do
      IO.puts("  #{name} — would update: #{reason} freq=#{frequency} ppy=#{ppy}")
    else
      attrs =
        %{
          dividend_rate: ttm_rate,
          dividend_frequency: frequency,
          dividend_source: "ttm_computed",
          dividend_updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
        |> maybe_put(:payments_per_year, if(ppy > 0, do: ppy))
        |> maybe_put(:dividend_per_payment, per_payment)

      case instrument |> Instrument.changeset(attrs) |> Repo.update() do
        {:ok, _} -> IO.puts("  #{name} — updated: #{reason} freq=#{frequency} ppy=#{ppy}")
        {:error, err} -> IO.puts("  #{name} — FAILED: #{inspect(err)}")
      end
    end
  end

  defp frequency_to_payments_per_year("monthly"), do: 12
  defp frequency_to_payments_per_year("quarterly"), do: 4
  defp frequency_to_payments_per_year("semi-annual"), do: 2
  defp frequency_to_payments_per_year("annual"), do: 1
  defp frequency_to_payments_per_year(_), do: 0

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
