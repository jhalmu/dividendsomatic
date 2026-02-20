defmodule Mix.Tasks.Migrate.LegacyDividends do
  @moduledoc """
  Migrate dividend data from the legacy `legacy_dividends` table to `dividend_payments`.

  Only migrates symbols that have records in legacy_dividends but zero records
  in dividend_payments. Skips duplicates by symbol + pay_date.

  ## Usage

      mix migrate.legacy_dividends           # Dry run (preview)
      mix migrate.legacy_dividends --commit  # Actually insert records
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{Dividend, DividendPayment, Instrument, InstrumentAlias}
  alias Dividendsomatic.Repo

  @shortdoc "Migrate legacy dividends to dividend_payments"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    commit? = "--commit" in args

    if commit? do
      Mix.shell().info("=== Migrating Legacy Dividends (COMMIT mode) ===\n")
    else
      Mix.shell().info("=== Migrating Legacy Dividends (DRY RUN) ===\n")
      Mix.shell().info("Pass --commit to actually insert records.\n")
    end

    # Find symbols with legacy records but no dividend_payments
    legacy_symbols = legacy_only_symbols()

    if legacy_symbols == [] do
      Mix.shell().info(
        "No symbols to migrate — all legacy symbols already have dividend_payments."
      )

      return_counts(0, 0, 0)
    else
      Mix.shell().info("Symbols to migrate: #{Enum.join(legacy_symbols, ", ")}\n")
      migrate_symbols(legacy_symbols, commit?)
    end
  end

  defp legacy_only_symbols do
    # All symbols in legacy_dividends
    legacy =
      Dividend
      |> select([d], d.symbol)
      |> distinct(true)
      |> Repo.all()
      |> MapSet.new()

    # Symbols already in dividend_payments (via instrument aliases)
    existing =
      DividendPayment
      |> join(:inner, [dp], i in Instrument, on: dp.instrument_id == i.id)
      |> join(:inner, [dp, i], a in InstrumentAlias, on: a.instrument_id == i.id)
      |> select([dp, i, a], a.symbol)
      |> distinct(true)
      |> Repo.all()
      |> MapSet.new()

    legacy
    |> MapSet.difference(existing)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  defp migrate_symbols(symbols, commit?) do
    results =
      Enum.map(symbols, fn symbol ->
        legacy_records =
          Dividend
          |> where([d], d.symbol == ^symbol)
          |> order_by([d], asc: d.pay_date)
          |> Repo.all()

        Mix.shell().info("#{symbol}: #{length(legacy_records)} legacy records")

        if commit? do
          migrate_symbol_records(symbol, legacy_records)
        else
          preview_symbol_records(symbol, legacy_records)
          %{symbol: symbol, migrated: 0, skipped: 0, errors: 0, total: length(legacy_records)}
        end
      end)

    total_migrated = Enum.sum(Enum.map(results, & &1.migrated))
    total_skipped = Enum.sum(Enum.map(results, & &1.skipped))
    total_errors = Enum.sum(Enum.map(results, & &1.errors))

    Mix.shell().info("\n=== Summary ===")
    Mix.shell().info("Migrated: #{total_migrated}")
    Mix.shell().info("Skipped:  #{total_skipped}")
    Mix.shell().info("Errors:   #{total_errors}")

    return_counts(total_migrated, total_skipped, total_errors)
  end

  defp preview_symbol_records(symbol, records) do
    Enum.each(records, fn record ->
      pay_date = record.pay_date || record.ex_date
      amount = record.amount
      currency = record.currency

      Mix.shell().info(
        "  [preview] #{symbol} #{pay_date} #{amount} #{currency} (#{record.amount_type})"
      )
    end)
  end

  defp migrate_symbol_records(symbol, records) do
    first = hd(records)
    instrument = find_or_create_instrument(symbol, first)

    Enum.reduce(records, %{symbol: symbol, migrated: 0, skipped: 0, errors: 0}, fn record, acc ->
      case insert_dividend_payment(instrument, record) do
        {:ok, _} ->
          %{acc | migrated: acc.migrated + 1}

        {:skip, reason} ->
          Mix.shell().info("  [skip] #{symbol} #{record.pay_date || record.ex_date}: #{reason}")
          %{acc | skipped: acc.skipped + 1}

        {:error, reason} ->
          Mix.shell().info(
            "  [error] #{symbol} #{record.pay_date || record.ex_date}: #{inspect(reason)}"
          )

          %{acc | errors: acc.errors + 1}
      end
    end)
  end

  defp find_or_create_instrument(symbol, legacy_record) do
    isin = legacy_record.isin

    case isin && Repo.get_by(Instrument, isin: isin) do
      nil ->
        # No ISIN or not found — create instrument with ISIN from legacy record
        effective_isin = isin || "LEGACY:#{symbol}"

        %Instrument{}
        |> Instrument.changeset(%{isin: effective_isin, name: symbol})
        |> Repo.insert(on_conflict: :nothing, conflict_target: :isin)

        # Re-fetch in case on_conflict triggered
        instrument = Repo.get_by!(Instrument, isin: effective_isin)
        ensure_alias(instrument, symbol)
        instrument

      instrument ->
        ensure_alias(instrument, symbol)
        instrument
    end
  end

  defp ensure_alias(instrument, symbol) do
    case Repo.get_by(InstrumentAlias, instrument_id: instrument.id, symbol: symbol) do
      nil ->
        %InstrumentAlias{}
        |> InstrumentAlias.changeset(%{
          instrument_id: instrument.id,
          symbol: symbol,
          source: "legacy_migration"
        })
        |> Repo.insert()

      _existing ->
        :ok
    end
  end

  defp insert_dividend_payment(instrument, legacy) do
    pay_date = legacy.pay_date || legacy.ex_date

    # Check for existing record (same instrument + pay_date)
    existing =
      DividendPayment
      |> where([d], d.instrument_id == ^instrument.id and d.pay_date == ^pay_date)
      |> Repo.one()

    if existing do
      {:skip, "already exists"}
    else
      {net_amount, per_share} = extract_amounts(legacy)

      attrs = %{
        external_id: "legacy-#{legacy.id}",
        instrument_id: instrument.id,
        ex_date: legacy.ex_date,
        pay_date: pay_date,
        gross_amount: legacy.gross_rate || per_share || net_amount,
        net_amount: net_amount,
        per_share: per_share,
        currency: legacy.currency,
        fx_rate: legacy.fx_rate,
        description: "Migrated from legacy_dividends"
      }

      case %DividendPayment{} |> DividendPayment.changeset(attrs) |> Repo.insert() do
        {:ok, dp} -> {:ok, dp}
        {:error, changeset} -> {:error, changeset.errors}
      end
    end
  end

  defp extract_amounts(legacy) do
    case legacy.amount_type do
      "per_share" ->
        # amount is per-share, net_amount might be total
        per_share = legacy.amount
        net = legacy.net_amount || legacy.amount
        {net, per_share}

      "total_net" ->
        # amount is total net, gross_rate is per-share
        net = legacy.amount
        per_share = legacy.gross_rate
        {net, per_share}

      _ ->
        {legacy.amount, legacy.gross_rate}
    end
  end

  defp return_counts(migrated, skipped, errors) do
    %{migrated: migrated, skipped: skipped, errors: errors}
  end
end
