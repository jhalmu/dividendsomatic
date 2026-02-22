defmodule Mix.Tasks.Import.NordnetCashFlows do
  @moduledoc """
  Import Nordnet cash flows (deposits, withdrawals, interest) from the
  transactions CSV export. Records are tagged with source="nordnet".

  These are legitimate cash flows at a separate broker that ran in parallel
  with IBKR (2017-2024). They are excluded from the IBKR balance check but
  preserved for complete financial history.

  ## Usage

      mix import.nordnet_cash_flows                    # Dry-run
      mix import.nordnet_cash_flows --execute          # Actually import
  """
  use Mix.Task

  alias Dividendsomatic.Portfolio.{CashFlow, NordnetCsvParser}
  alias Dividendsomatic.Repo

  @shortdoc "Import Nordnet cash flows from transactions CSV"

  @nordnet_file "data_archive/nordnet/transactions-and-notes-export.csv"

  # Map Nordnet transaction types to cash_flow flow_types
  @flow_type_map %{
    "deposit" => "deposit",
    "withdrawal" => "withdrawal",
    "loan_interest" => "interest",
    "capital_interest" => "interest",
    "interest_correction" => "interest"
  }

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    execute? = "--execute" in args
    mode = if execute?, do: "EXECUTE", else: "DRY RUN"
    Mix.shell().info("=== Import Nordnet Cash Flows (#{mode}) ===\n")

    path = Path.join(File.cwd!(), @nordnet_file)

    case NordnetCsvParser.parse_file(path) do
      {:ok, transactions} ->
        cash_flows =
          transactions
          |> Enum.filter(fn txn -> Map.has_key?(@flow_type_map, txn.transaction_type) end)
          |> Enum.map(&to_cash_flow_attrs/1)

        Mix.shell().info("Found #{length(cash_flows)} Nordnet cash flow records\n")
        show_summary(cash_flows)

        if execute? do
          {inserted, skipped, errors} = insert_records(cash_flows)

          Mix.shell().info(
            "\nInserted: #{inserted}, Skipped (dupe): #{skipped}, Errors: #{errors}"
          )

          show_db_counts()
        else
          Mix.shell().info("\nRun with --execute to import.")
        end

      {:error, reason} ->
        Mix.shell().error("Failed to parse: #{reason}")
    end
  end

  defp to_cash_flow_attrs(txn) do
    flow_type = Map.fetch!(@flow_type_map, txn.transaction_type)

    %{
      external_id: "nordnet_cf_#{txn.external_id}",
      flow_type: flow_type,
      date: txn.entry_date || txn.trade_date,
      amount: txn.amount,
      currency: txn.currency || "EUR",
      description: txn.description || txn.raw_type,
      source: "nordnet",
      raw_data: %{
        "broker" => "nordnet",
        "nordnet_id" => txn.external_id,
        "raw_type" => txn.raw_type
      }
    }
  end

  defp insert_records(records) do
    Enum.reduce(records, {0, 0, 0}, fn attrs, {ins, skip, errs} ->
      changeset = CashFlow.changeset(%CashFlow{}, attrs)

      case Repo.insert(changeset) do
        {:ok, _} ->
          {ins + 1, skip, errs}

        {:error, %Ecto.Changeset{errors: [{:external_id, _} | _]}} ->
          {ins, skip + 1, errs}

        {:error, changeset} ->
          Mix.shell().error("  Error: #{inspect(changeset.errors)}")
          {ins, skip, errs + 1}
      end
    end)
  end

  defp show_summary(records) do
    records
    |> Enum.group_by(& &1.flow_type)
    |> Enum.sort_by(fn {type, _} -> type end)
    |> Enum.each(fn {type, recs} ->
      total =
        recs
        |> Enum.map(fn r -> Decimal.abs(r.amount || Decimal.new("0")) end)
        |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
        |> Decimal.round(2)

      Mix.shell().info("  #{type}: #{length(recs)} records, €#{total}")
    end)
  end

  defp show_db_counts do
    Mix.shell().info("\n=== Cash flows by source ===")

    %{rows: rows} =
      Repo.query!("""
      SELECT COALESCE(source, 'unknown'), flow_type, COUNT(*),
             SUM(ABS(COALESCE(amount_eur, amount)))::numeric(12,2)
      FROM cash_flows
      GROUP BY source, flow_type
      ORDER BY source, flow_type
      """)

    for [src, ft, cnt, total] <- rows do
      Mix.shell().info("  [#{src}] #{ft}: #{cnt} records, €#{total}")
    end
  end
end
