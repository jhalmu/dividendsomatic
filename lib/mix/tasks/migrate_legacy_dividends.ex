defmodule Mix.Tasks.Migrate.LegacyDividends do
  @shortdoc "Migrate broker dividends from legacy_dividends to dividend_payments"
  @moduledoc """
  One-time migration:
  - Broker records (ibkr/nordnet/ibkr_flex_dividend): insert into dividend_payments if not already there
  - YFinance records (5,835): export to JSON archive (superseded by instruments.dividend_rate)

  ## Usage

      mix migrate.legacy_dividends
      mix migrate.legacy_dividends --dry-run
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Repo
  alias Dividendsomatic.Portfolio.{DividendPayment, Instrument}

  @broker_sources ~w(ibkr nordnet ibkr_flex_dividend)

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    dry_run? = "--dry-run" in args

    IO.puts(
      if dry_run?,
        do: "\n=== DRY RUN: Legacy Dividend Migration ===",
        else: "\n=== Legacy Dividend Migration ==="
    )

    migrate_broker_dividends(dry_run?)
    archive_yfinance_dividends(dry_run?)

    unless dry_run? do
      IO.puts("\nMigration complete. Safe to drop legacy_dividends table.")
    end
  end

  defp migrate_broker_dividends(dry_run?) do
    broker_records =
      Repo.all(
        from(d in "legacy_dividends",
          where: d.source in ^@broker_sources,
          select: %{
            id: d.id,
            symbol: d.symbol,
            isin: d.isin,
            ex_date: d.ex_date,
            pay_date: d.pay_date,
            amount: d.amount,
            currency: d.currency,
            source: d.source,
            amount_type: d.amount_type,
            gross_rate: d.gross_rate,
            net_amount: d.net_amount,
            quantity_at_record: d.quantity_at_record,
            fx_rate: d.fx_rate
          },
          order_by: [asc: d.ex_date]
        )
      )

    IO.puts("\nBroker dividends: #{length(broker_records)}")

    results =
      Enum.reduce(
        broker_records,
        %{migrated: 0, skipped_dup: 0, no_instrument: 0, errors: 0},
        fn rec, acc ->
          instrument = if rec.isin, do: Repo.get_by(Instrument, isin: rec.isin)

          cond do
            is_nil(instrument) ->
              IO.puts("  SKIP (no instrument): #{rec.isin || rec.symbol} #{rec.ex_date}")
              %{acc | no_instrument: acc.no_instrument + 1}

            already_exists?(instrument.id, rec) ->
              %{acc | skipped_dup: acc.skipped_dup + 1}

            dry_run? ->
              IO.puts("  WOULD CREATE: #{rec.isin} #{rec.ex_date} #{rec.amount} #{rec.currency}")
              %{acc | migrated: acc.migrated + 1}

            true ->
              attrs = build_payment_attrs(instrument.id, rec)

              case Repo.insert(DividendPayment.changeset(%DividendPayment{}, attrs)) do
                {:ok, _} ->
                  %{acc | migrated: acc.migrated + 1}

                {:error, cs} ->
                  IO.puts("  ERROR: #{rec.isin} #{rec.ex_date} -> #{inspect(cs.errors)}")
                  %{acc | errors: acc.errors + 1}
              end
          end
        end
      )

    IO.puts("\n--- Broker Dividend Results ---")
    IO.puts("  Migrated:       #{results.migrated}")
    IO.puts("  Skipped (dup):  #{results.skipped_dup}")
    IO.puts("  No instrument:  #{results.no_instrument}")
    IO.puts("  Errors:         #{results.errors}")
  end

  defp archive_yfinance_dividends(dry_run?) do
    yfinance_count =
      Repo.one(from(d in "legacy_dividends", where: d.source == "yfinance", select: count()))

    IO.puts("\nYFinance records: #{yfinance_count} (superseded by instruments.dividend_rate)")

    if yfinance_count > 0 and not dry_run? do
      yfinance_data =
        Repo.all(
          from(d in "legacy_dividends",
            where: d.source == "yfinance",
            select: %{
              symbol: d.symbol,
              isin: d.isin,
              ex_date: d.ex_date,
              pay_date: d.pay_date,
              amount: d.amount,
              currency: d.currency
            },
            order_by: [asc: d.symbol, asc: d.ex_date]
          )
        )

      # Serialize Decimal fields to strings for JSON
      serializable_data =
        Enum.map(yfinance_data, fn rec ->
          %{
            symbol: rec.symbol,
            isin: rec.isin,
            ex_date: to_string(rec.ex_date),
            pay_date: if(rec.pay_date, do: to_string(rec.pay_date)),
            amount: if(rec.amount, do: Decimal.to_string(rec.amount)),
            currency: rec.currency
          }
        end)

      archive_path = Path.join(File.cwd!(), "data_archive/yfinance_dividend_history.json")
      File.mkdir_p!(Path.dirname(archive_path))
      File.write!(archive_path, Jason.encode!(serializable_data, pretty: true))
      IO.puts("  Archived to: #{archive_path}")
    end
  end

  defp already_exists?(instrument_id, rec) do
    date = rec.ex_date || rec.pay_date

    Repo.exists?(
      from(dp in DividendPayment,
        where: dp.instrument_id == ^instrument_id,
        where: dp.ex_date == ^date or dp.pay_date == ^date
      )
    )
  end

  defp build_payment_attrs(instrument_id, rec) do
    # Legacy per_share amount → gross_amount uses amount * quantity if available
    {gross, net, per_share} =
      case rec.amount_type do
        "per_share" ->
          per_share = rec.amount
          quantity = rec.quantity_at_record

          gross =
            if quantity && Decimal.gt?(quantity, Decimal.new("0")),
              do: Decimal.mult(per_share, quantity),
              else: per_share

          net = rec.net_amount || gross
          {gross, net, per_share}

        _ ->
          net = rec.net_amount || rec.amount
          gross = rec.gross_rate || net
          {gross, net, nil}
      end

    external_id = "legacy_#{rec.source}_#{rec.isin}_#{rec.ex_date || rec.pay_date}"

    %{
      external_id: external_id,
      instrument_id: instrument_id,
      ex_date: rec.ex_date,
      pay_date: rec.pay_date || rec.ex_date,
      gross_amount: gross,
      net_amount: net,
      withholding_tax: Decimal.new("0"),
      currency: rec.currency || "EUR",
      fx_rate: rec.fx_rate,
      quantity: rec.quantity_at_record,
      per_share: per_share,
      description: "Migrated from legacy_dividends (#{rec.source})",
      raw_data: %{"legacy_source" => rec.source, "legacy_id" => Ecto.UUID.cast!(rec.id)}
    }
  end
end
