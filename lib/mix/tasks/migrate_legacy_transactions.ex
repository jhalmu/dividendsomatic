defmodule Mix.Tasks.Migrate.LegacyTransactions do
  @shortdoc "Migrate legacy_broker_transactions to trades/dividend_payments/cash_flows/corporate_actions"
  @moduledoc """
  One-time migration of legacy_broker_transactions to clean tables.

  - buy/sell → trades (find instrument by ISIN)
  - dividend/withholding_tax/foreign_tax → dividend_payments
  - deposit/withdrawal → cash_flows
  - loan_interest/capital_interest/interest_correction → cash_flows (interest)
  - fx_buy/fx_sell → skip (FX conversions)
  - corporate_action → corporate_actions

  ## Usage

      mix migrate.legacy_transactions
      mix migrate.legacy_transactions --dry-run
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Repo

  alias Dividendsomatic.Portfolio.{
    CashFlow,
    CorporateAction,
    DividendPayment,
    Instrument,
    Trade
  }

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    dry_run? = "--dry-run" in args
    label = if dry_run?, do: "DRY RUN: ", else: ""

    IO.puts("\n=== #{label}Legacy Broker Transaction Migration ===")

    txns = load_all_transactions()
    IO.puts("Total legacy transactions: #{length(txns)}")

    grouped = Enum.group_by(txns, & &1.transaction_type)

    results = %{
      trades:
        migrate_trades(Map.get(grouped, "buy", []) ++ Map.get(grouped, "sell", []), dry_run?),
      dividends:
        migrate_dividends(
          Map.get(grouped, "dividend", []) ++
            Map.get(grouped, "withholding_tax", []) ++
            Map.get(grouped, "foreign_tax", []),
          dry_run?
        ),
      deposits:
        migrate_cash_flows(
          Map.get(grouped, "deposit", []) ++ Map.get(grouped, "withdrawal", []),
          dry_run?
        ),
      interest:
        migrate_interest(
          Map.get(grouped, "loan_interest", []) ++
            Map.get(grouped, "capital_interest", []) ++
            Map.get(grouped, "interest_correction", []),
          dry_run?
        ),
      corporate: migrate_corporate_actions(Map.get(grouped, "corporate_action", []), dry_run?),
      fx_skipped: length(Map.get(grouped, "fx_buy", []) ++ Map.get(grouped, "fx_sell", []))
    }

    IO.puts("\n--- Results ---")
    IO.puts("  Trades:             #{format_result(results.trades)}")
    IO.puts("  Dividends:          #{format_result(results.dividends)}")
    IO.puts("  Deposits/Withdraw:  #{format_result(results.deposits)}")
    IO.puts("  Interest/Fees:      #{format_result(results.interest)}")
    IO.puts("  Corporate actions:  #{format_result(results.corporate)}")
    IO.puts("  FX (skipped):       #{results.fx_skipped}")

    unless dry_run? do
      IO.puts("\nMigration complete. Safe to drop legacy_broker_transactions table.")
    end
  end

  defp format_result(%{migrated: m, skipped: s, errors: e}),
    do: "#{m} migrated, #{s} skipped, #{e} errors"

  defp load_all_transactions do
    Repo.all(
      from(t in "legacy_broker_transactions",
        select: %{
          id: t.id,
          external_id: t.external_id,
          broker: t.broker,
          transaction_type: t.transaction_type,
          raw_type: t.raw_type,
          entry_date: t.entry_date,
          trade_date: t.trade_date,
          settlement_date: t.settlement_date,
          security_name: t.security_name,
          isin: t.isin,
          quantity: t.quantity,
          price: t.price,
          amount: t.amount,
          commission: t.commission,
          currency: t.currency,
          exchange_rate: t.exchange_rate,
          description: t.description,
          confirmation_number: t.confirmation_number
        },
        order_by: [asc: t.trade_date, asc: t.entry_date]
      )
    )
  end

  # --- Trades (buy/sell) ---

  defp migrate_trades(txns, dry_run?) do
    IO.puts("\nMigrating #{length(txns)} buy/sell transactions...")

    Enum.reduce(txns, %{migrated: 0, skipped: 0, errors: 0}, fn txn, acc ->
      process_trade_row(txn, acc, dry_run?)
    end)
  end

  defp process_trade_row(txn, acc, dry_run?) do
    ext_id = make_external_id("trade", txn)

    cond do
      Repo.exists?(from(t in Trade, where: t.external_id == ^ext_id)) ->
        %{acc | skipped: acc.skipped + 1}

      dry_run? ->
        %{acc | migrated: acc.migrated + 1}

      true ->
        insert_trade(txn, ext_id, acc)
    end
  end

  defp insert_trade(txn, ext_id, acc) do
    case find_instrument(txn.isin) do
      nil ->
        %{acc | errors: acc.errors + 1}

      instrument ->
        attrs = build_trade_attrs(txn, ext_id, instrument)

        case Repo.insert(Trade.changeset(%Trade{}, attrs)) do
          {:ok, _} -> %{acc | migrated: acc.migrated + 1}
          {:error, _} -> %{acc | errors: acc.errors + 1}
        end
    end
  end

  defp build_trade_attrs(txn, ext_id, instrument) do
    %{
      external_id: ext_id,
      instrument_id: instrument.id,
      trade_date: txn.trade_date || txn.entry_date,
      settlement_date: txn.settlement_date,
      quantity: txn.quantity || Decimal.new("0"),
      price: txn.price || Decimal.new("0"),
      amount: txn.amount || Decimal.new("0"),
      commission: txn.commission || Decimal.new("0"),
      currency: txn.currency || "EUR",
      fx_rate: txn.exchange_rate,
      description: "Migrated from legacy_broker_transactions (#{txn.broker})",
      raw_data: %{"legacy_id" => Ecto.UUID.cast!(txn.id), "broker" => txn.broker}
    }
  end

  # --- Dividends ---

  defp migrate_dividends(txns, dry_run?) do
    IO.puts("Migrating #{length(txns)} dividend/tax transactions...")

    # Group by ISIN+date to aggregate dividend+tax into single payment
    grouped =
      txns
      |> Enum.filter(& &1.isin)
      |> Enum.group_by(fn txn -> {txn.isin, txn.trade_date || txn.entry_date} end)

    Enum.reduce(grouped, %{migrated: 0, skipped: 0, errors: 0}, fn {{isin, date}, group_txns},
                                                                   acc ->
      process_dividend_group(isin, date, group_txns, acc, dry_run?)
    end)
  end

  defp process_dividend_group(isin, date, group_txns, acc, dry_run?) do
    ext_id = "legacy_bt_div_#{isin}_#{date}"

    cond do
      Repo.exists?(from(dp in DividendPayment, where: dp.external_id == ^ext_id)) ->
        %{acc | skipped: acc.skipped + 1}

      # Also check for existing payment by instrument+date
      already_has_payment?(isin, date) ->
        %{acc | skipped: acc.skipped + 1}

      dry_run? ->
        %{acc | migrated: acc.migrated + 1}

      true ->
        insert_dividend_payment(isin, date, group_txns, ext_id, acc)
    end
  end

  defp insert_dividend_payment(isin, date, group_txns, ext_id, acc) do
    case find_instrument(isin) do
      nil ->
        %{acc | errors: acc.errors + 1}

      instrument ->
        attrs = build_dividend_attrs(instrument, date, group_txns, ext_id)

        case Repo.insert(DividendPayment.changeset(%DividendPayment{}, attrs)) do
          {:ok, _} -> %{acc | migrated: acc.migrated + 1}
          {:error, _} -> %{acc | errors: acc.errors + 1}
        end
    end
  end

  defp build_dividend_attrs(instrument, date, group_txns, ext_id) do
    {gross, tax} = aggregate_dividend_group(group_txns)

    %{
      external_id: ext_id,
      instrument_id: instrument.id,
      ex_date: date,
      pay_date: date,
      gross_amount: gross,
      net_amount: Decimal.sub(gross, Decimal.abs(tax)),
      withholding_tax: Decimal.abs(tax),
      currency: List.first(group_txns).currency || "EUR",
      fx_rate: List.first(group_txns).exchange_rate,
      description: "Migrated from legacy_broker_transactions",
      raw_data: %{"legacy_ids" => Enum.map(group_txns, &Ecto.UUID.cast!(&1.id))}
    }
  end

  defp aggregate_dividend_group(txns) do
    Enum.reduce(txns, {Decimal.new("0"), Decimal.new("0")}, fn txn, {gross, tax} ->
      amount = txn.amount || Decimal.new("0")

      case txn.transaction_type do
        "dividend" ->
          {Decimal.add(gross, Decimal.abs(amount)), tax}

        type when type in ["withholding_tax", "foreign_tax"] ->
          {gross, Decimal.add(tax, Decimal.abs(amount))}

        _ ->
          {gross, tax}
      end
    end)
  end

  defp already_has_payment?(isin, date) do
    case find_instrument(isin) do
      nil ->
        false

      instrument ->
        Repo.exists?(
          from(dp in DividendPayment,
            where: dp.instrument_id == ^instrument.id,
            where: dp.ex_date == ^date or dp.pay_date == ^date
          )
        )
    end
  end

  # --- Cash Flows (deposits/withdrawals) ---

  defp migrate_cash_flows(txns, dry_run?) do
    IO.puts("Migrating #{length(txns)} deposit/withdrawal transactions...")

    Enum.reduce(txns, %{migrated: 0, skipped: 0, errors: 0}, fn txn, acc ->
      process_cash_flow_row(txn, acc, dry_run?)
    end)
  end

  defp process_cash_flow_row(txn, acc, dry_run?) do
    ext_id = make_external_id("cf", txn)

    cond do
      Repo.exists?(from(cf in CashFlow, where: cf.external_id == ^ext_id)) ->
        %{acc | skipped: acc.skipped + 1}

      dry_run? ->
        %{acc | migrated: acc.migrated + 1}

      true ->
        insert_cash_flow(txn, ext_id, acc)
    end
  end

  defp insert_cash_flow(txn, ext_id, acc) do
    flow_type = if txn.transaction_type == "deposit", do: "deposit", else: "withdrawal"

    attrs = %{
      external_id: ext_id,
      flow_type: flow_type,
      date: txn.trade_date || txn.entry_date,
      amount: txn.amount || Decimal.new("0"),
      currency: txn.currency || "EUR",
      fx_rate: txn.exchange_rate,
      description: txn.description || "Migrated from legacy (#{txn.broker})",
      raw_data: %{"legacy_id" => Ecto.UUID.cast!(txn.id), "broker" => txn.broker}
    }

    case Repo.insert(CashFlow.changeset(%CashFlow{}, attrs)) do
      {:ok, _} -> %{acc | migrated: acc.migrated + 1}
      {:error, _} -> %{acc | errors: acc.errors + 1}
    end
  end

  # --- Interest/Fees ---

  defp migrate_interest(txns, dry_run?) do
    IO.puts("Migrating #{length(txns)} interest transactions...")

    Enum.reduce(txns, %{migrated: 0, skipped: 0, errors: 0}, fn txn, acc ->
      process_interest_row(txn, acc, dry_run?)
    end)
  end

  defp process_interest_row(txn, acc, dry_run?) do
    ext_id = make_external_id("int", txn)

    cond do
      Repo.exists?(from(cf in CashFlow, where: cf.external_id == ^ext_id)) ->
        %{acc | skipped: acc.skipped + 1}

      dry_run? ->
        %{acc | migrated: acc.migrated + 1}

      true ->
        insert_interest(txn, ext_id, acc)
    end
  end

  defp insert_interest(txn, ext_id, acc) do
    attrs = %{
      external_id: ext_id,
      flow_type: "interest",
      date: txn.trade_date || txn.entry_date,
      amount: txn.amount || Decimal.new("0"),
      currency: txn.currency || "EUR",
      fx_rate: txn.exchange_rate,
      description: txn.description || "#{txn.transaction_type} (#{txn.broker})",
      raw_data: %{"legacy_id" => Ecto.UUID.cast!(txn.id), "type" => txn.transaction_type}
    }

    case Repo.insert(CashFlow.changeset(%CashFlow{}, attrs)) do
      {:ok, _} -> %{acc | migrated: acc.migrated + 1}
      {:error, _} -> %{acc | errors: acc.errors + 1}
    end
  end

  # --- Corporate Actions ---

  defp migrate_corporate_actions(txns, dry_run?) do
    IO.puts("Migrating #{length(txns)} corporate action transactions...")

    Enum.reduce(txns, %{migrated: 0, skipped: 0, errors: 0}, fn txn, acc ->
      process_corporate_action_row(txn, acc, dry_run?)
    end)
  end

  defp process_corporate_action_row(txn, acc, dry_run?) do
    ext_id = make_external_id("ca", txn)

    cond do
      Repo.exists?(from(ca in CorporateAction, where: ca.external_id == ^ext_id)) ->
        %{acc | skipped: acc.skipped + 1}

      dry_run? ->
        %{acc | migrated: acc.migrated + 1}

      true ->
        insert_corporate_action(txn, ext_id, acc)
    end
  end

  defp insert_corporate_action(txn, ext_id, acc) do
    instrument = if txn.isin, do: find_instrument(txn.isin)

    attrs = %{
      external_id: ext_id,
      action_type: txn.raw_type || "corporate_action",
      date: txn.trade_date || txn.entry_date,
      instrument_id: if(instrument, do: instrument.id),
      description: txn.description || txn.security_name,
      quantity: txn.quantity,
      amount: txn.amount,
      currency: txn.currency,
      raw_data: %{"legacy_id" => Ecto.UUID.cast!(txn.id), "broker" => txn.broker}
    }

    case Repo.insert(CorporateAction.changeset(%CorporateAction{}, attrs)) do
      {:ok, _} -> %{acc | migrated: acc.migrated + 1}
      {:error, _} -> %{acc | errors: acc.errors + 1}
    end
  end

  # --- Helpers ---

  defp find_instrument(nil), do: nil
  defp find_instrument(isin), do: Repo.get_by(Instrument, isin: isin)

  defp make_external_id(prefix, txn) do
    base = txn.external_id || Ecto.UUID.cast!(txn.id)
    "legacy_#{prefix}_#{txn.broker}_#{base}"
  end
end
