defmodule Mix.Tasks.Merge.LegacyInstruments do
  @moduledoc """
  Merge LEGACY: instruments into their proper counterparts.

  When `mix migrate.legacy_dividends` ran, it created instruments with ISINs
  like `LEGACY:CVZ`, `LEGACY:AKTIA` etc. Meanwhile, the same stocks have proper
  instruments (from IBKR Activity Statements) with real ISINs — but zero
  dividend_payments linked to them.

  This task:
  1. Finds all instruments with `LEGACY:%` ISIN
  2. Finds proper counterpart via instrument_aliases (same symbol, real ISIN)
  3. Reassigns dividend_payments, trades, corporate_actions to the proper instrument
  4. Merges aliases (skips duplicates)
  5. Handles duplicate dividend_payments after merge (same instrument + pay_date)
  6. Deletes the LEGACY: instrument
  7. Optionally backfills per_share on dividend_payments

  ## Usage

      mix merge.legacy_instruments              # Dry run (preview)
      mix merge.legacy_instruments --commit     # Execute merge
      mix merge.legacy_instruments --backfill   # Also backfill per_share
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{
    CorporateAction,
    DividendPayment,
    Instrument,
    InstrumentAlias,
    Trade
  }

  alias Dividendsomatic.Repo

  @shortdoc "Merge LEGACY: instruments into proper counterparts"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    commit? = "--commit" in args
    backfill? = "--backfill" in args

    mode = if commit?, do: "COMMIT", else: "DRY RUN"
    Mix.shell().info("=== Merge Legacy Instruments (#{mode}) ===\n")

    unless commit? do
      Mix.shell().info("Pass --commit to execute. Add --backfill to also backfill per_share.\n")
    end

    legacy_instruments = find_legacy_instruments()

    if legacy_instruments == [] do
      Mix.shell().info("No LEGACY: instruments found. Nothing to do.")
    else
      Mix.shell().info("Found #{length(legacy_instruments)} LEGACY: instruments\n")

      results = Enum.map(legacy_instruments, &process_legacy_instrument(&1, commit?))

      merged = Enum.count(results, &(&1.status == :merged))
      unmatched = Enum.count(results, &(&1.status == :unmatched))
      errors = Enum.count(results, &(&1.status == :error))

      Mix.shell().info("\n=== Summary ===")
      Mix.shell().info("Merged:    #{merged}")
      Mix.shell().info("Unmatched: #{unmatched}")
      Mix.shell().info("Errors:    #{errors}")

      if unmatched > 0 do
        unmatched_list =
          results
          |> Enum.filter(&(&1.status == :unmatched))
          |> Enum.map(& &1.isin)

        Mix.shell().info("\nUnmatched LEGACY instruments (no proper counterpart):")
        Enum.each(unmatched_list, &Mix.shell().info("  #{&1}"))
      end

      if backfill? and commit? do
        Mix.shell().info("\n=== Backfilling per_share ===")
        backfill_per_share()
      end
    end
  end

  defp find_legacy_instruments do
    Instrument
    |> where([i], like(i.isin, "LEGACY:%"))
    |> preload(:aliases)
    |> Repo.all()
  end

  defp process_legacy_instrument(legacy, commit?) do
    symbol = extract_symbol(legacy)
    Mix.shell().info("#{legacy.isin} (symbol: #{symbol})")

    case find_proper_counterpart(legacy, symbol) do
      nil ->
        Mix.shell().info("  -> No proper counterpart found")
        %{isin: legacy.isin, status: :unmatched}

      proper ->
        Mix.shell().info("  -> Merging into #{proper.isin} (#{proper.name})")
        counts = count_records(legacy)
        Mix.shell().info("    dividend_payments: #{counts.dividends}")
        Mix.shell().info("    trades: #{counts.trades}")
        Mix.shell().info("    corporate_actions: #{counts.corporate_actions}")
        Mix.shell().info("    aliases: #{counts.aliases}")

        if commit? do
          case do_merge(legacy, proper) do
            {:ok, stats} ->
              Mix.shell().info("    Merged OK (dupes removed: #{stats.dupes_removed})")
              %{isin: legacy.isin, status: :merged}

            {:error, reason} ->
              Mix.shell().info("    ERROR: #{inspect(reason)}")
              %{isin: legacy.isin, status: :error}
          end
        else
          %{isin: legacy.isin, status: :merged}
        end
    end
  end

  defp extract_symbol(legacy) do
    case legacy.isin do
      "LEGACY:" <> symbol -> symbol
      _ -> legacy.name
    end
  end

  defp find_proper_counterpart(legacy, symbol) do
    # Find instrument_aliases for this symbol that point to non-LEGACY instruments
    alias_matches =
      InstrumentAlias
      |> where([a], a.symbol == ^symbol)
      |> join(:inner, [a], i in Instrument, on: a.instrument_id == i.id)
      |> where([a, i], not like(i.isin, "LEGACY:%"))
      |> select([a, i], i)
      |> Repo.all()
      |> Enum.uniq_by(& &1.id)

    # Also try aliases from the legacy instrument itself
    legacy_aliases = Enum.map(legacy.aliases, & &1.symbol)

    all_matches =
      if alias_matches == [] do
        # Try each alias symbol
        Enum.flat_map(legacy_aliases, fn alias_sym ->
          InstrumentAlias
          |> where([a], a.symbol == ^alias_sym)
          |> join(:inner, [a], i in Instrument, on: a.instrument_id == i.id)
          |> where([a, i], not like(i.isin, "LEGACY:%"))
          |> where([a, i], i.id != ^legacy.id)
          |> select([a, i], i)
          |> Repo.all()
        end)
        |> Enum.uniq_by(& &1.id)
      else
        alias_matches
      end

    # Return the best match (prefer one with trades/dividends already)
    case all_matches do
      [] -> nil
      [single] -> single
      multiples -> pick_best_match(multiples)
    end
  end

  defp pick_best_match(instruments) do
    # Prefer the instrument that already has the most dividend_payments or trades
    instruments
    |> Enum.map(fn i ->
      divs = Repo.aggregate(from(d in DividendPayment, where: d.instrument_id == ^i.id), :count)
      trades = Repo.aggregate(from(t in Trade, where: t.instrument_id == ^i.id), :count)
      {i, divs + trades}
    end)
    |> Enum.max_by(fn {_i, count} -> count end)
    |> elem(0)
  end

  defp count_records(instrument) do
    %{
      dividends:
        Repo.aggregate(
          from(d in DividendPayment, where: d.instrument_id == ^instrument.id),
          :count
        ),
      trades: Repo.aggregate(from(t in Trade, where: t.instrument_id == ^instrument.id), :count),
      corporate_actions:
        Repo.aggregate(
          from(c in CorporateAction, where: c.instrument_id == ^instrument.id),
          :count
        ),
      aliases: length(instrument.aliases)
    }
  end

  defp do_merge(legacy, proper) do
    Repo.transaction(fn ->
      # 1. Reassign dividend_payments
      from(d in DividendPayment, where: d.instrument_id == ^legacy.id)
      |> Repo.update_all(set: [instrument_id: proper.id])

      # 2. Reassign trades
      from(t in Trade, where: t.instrument_id == ^legacy.id)
      |> Repo.update_all(set: [instrument_id: proper.id])

      # 3. Reassign corporate_actions
      from(c in CorporateAction, where: c.instrument_id == ^legacy.id)
      |> Repo.update_all(set: [instrument_id: proper.id])

      # 4. Merge aliases (skip duplicates)
      merge_aliases(legacy, proper)

      # 5. Remove duplicate dividend_payments (same instrument + pay_date after merge)
      dupes_removed = remove_duplicate_dividends(proper)

      # 6. Delete the LEGACY: instrument (aliases already merged/deleted)
      from(a in InstrumentAlias, where: a.instrument_id == ^legacy.id) |> Repo.delete_all()
      Repo.delete!(legacy)

      %{dupes_removed: dupes_removed}
    end)
  end

  defp merge_aliases(legacy, proper) do
    existing_aliases =
      InstrumentAlias
      |> where([a], a.instrument_id == ^proper.id)
      |> Repo.all()
      |> MapSet.new(fn a -> {a.symbol, a.exchange} end)

    legacy_aliases =
      InstrumentAlias
      |> where([a], a.instrument_id == ^legacy.id)
      |> Repo.all()

    Enum.each(legacy_aliases, fn alias_rec ->
      key = {alias_rec.symbol, alias_rec.exchange}

      unless MapSet.member?(existing_aliases, key) do
        %InstrumentAlias{}
        |> InstrumentAlias.changeset(%{
          instrument_id: proper.id,
          symbol: alias_rec.symbol,
          exchange: alias_rec.exchange,
          valid_from: alias_rec.valid_from,
          valid_to: alias_rec.valid_to,
          source: alias_rec.source || "legacy_merge"
        })
        |> Repo.insert!()
      end
    end)
  end

  defp remove_duplicate_dividends(instrument) do
    # Find pay_dates that have multiple records for this instrument
    dupes =
      DividendPayment
      |> where([d], d.instrument_id == ^instrument.id)
      |> group_by([d], d.pay_date)
      |> having([d], count(d.id) > 1)
      |> select([d], d.pay_date)
      |> Repo.all()

    Enum.reduce(dupes, 0, fn pay_date, acc ->
      records =
        DividendPayment
        |> where([d], d.instrument_id == ^instrument.id and d.pay_date == ^pay_date)
        |> order_by([d], asc: d.inserted_at)
        |> Repo.all()

      # Keep the IBKR-sourced one (non-legacy external_id), or the first one
      {keep, remove} = split_keep_remove(records)

      Mix.shell().info(
        "    Dedup #{pay_date}: keeping #{keep.external_id}, removing #{length(remove)} dupes"
      )

      Enum.each(remove, &Repo.delete!/1)
      acc + length(remove)
    end)
  end

  defp split_keep_remove(records) do
    # Prefer non-legacy (IBKR-sourced) records
    case Enum.split_with(records, fn r -> not String.starts_with?(r.external_id, "legacy-") end) do
      {[ibkr | _rest_ibkr], legacy} ->
        {ibkr, legacy}

      {[], [first | rest]} ->
        {first, rest}
    end
  end

  # --- per_share backfill ---

  defp backfill_per_share do
    records =
      DividendPayment
      |> where(
        [d],
        is_nil(d.per_share) and not is_nil(d.quantity) and not is_nil(d.net_amount)
      )
      |> where([d], d.quantity > 0)
      |> Repo.all()

    Mix.shell().info("Found #{length(records)} dividend_payments missing per_share")

    updated =
      Enum.count(records, fn record ->
        per_share = Decimal.div(record.net_amount, record.quantity)

        case record
             |> DividendPayment.changeset(%{per_share: per_share})
             |> Repo.update() do
          {:ok, _} -> true
          {:error, _} -> false
        end
      end)

    Mix.shell().info("Backfilled per_share on #{updated} records")
  end
end
