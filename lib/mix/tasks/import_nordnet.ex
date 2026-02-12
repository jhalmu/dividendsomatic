defmodule Mix.Tasks.Import.Nordnet do
  @moduledoc """
  Import Nordnet transaction CSV into database.

  Usage:
    mix import.nordnet                              # Default: csv_data/nordnet/
    mix import.nordnet path/to/file.csv             # Single file
    mix import.nordnet path/to/directory/            # All CSVs in directory
  """
  use Mix.Task

  import Ecto.Query
  alias Dividendsomatic.Portfolio.{BrokerTransaction, NordnetCsvParser}

  alias Dividendsomatic.Portfolio.Processors.{
    CostProcessor,
    DividendProcessor,
    SoldPositionProcessor
  }

  alias Dividendsomatic.Repo

  @shortdoc "Import Nordnet transaction CSV"
  def run(args) do
    Mix.Task.run("app.start")

    path = List.first(args) || "csv_data/nordnet/"

    files = resolve_files(path)

    if files == [] do
      IO.puts("No CSV files found at: #{path}")
    else
      import_files(files)
    end
  end

  defp import_files(files) do
    IO.puts("Found #{length(files)} CSV file(s)")

    {total_txns, total_new} =
      Enum.reduce(files, {0, 0}, fn file, {txn_acc, new_acc} ->
        IO.puts("\nParsing #{Path.basename(file)}...")

        case NordnetCsvParser.parse_file(file) do
          {:ok, transactions} ->
            IO.puts("  Parsed #{length(transactions)} transactions")
            new_count = upsert_transactions(transactions)
            IO.puts("  Upserted #{new_count} new transactions")
            {txn_acc + length(transactions), new_acc + new_count}

          {:error, reason} ->
            IO.puts("  Error: #{reason}")
            {txn_acc, new_acc}
        end
      end)

    IO.puts("\n--- Running processors ---")

    {:ok, div_count} = DividendProcessor.process()
    IO.puts("  Dividends: #{div_count} new")

    {:ok, sold_count} = SoldPositionProcessor.process()
    IO.puts("  Sold positions: #{sold_count} new")

    {:ok, cost_count} = CostProcessor.process()
    IO.puts("  Costs: #{cost_count} new")

    IO.puts("\n--- Summary ---")
    IO.puts("  Transactions: #{total_txns} parsed, #{total_new} new")
    IO.puts("  Dividends: #{div_count}")
    IO.puts("  Sold positions: #{sold_count}")
    IO.puts("  Costs: #{cost_count}")
  end

  defp resolve_files(path) do
    cond do
      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".csv"))
        |> Enum.map(&Path.join(path, &1))
        |> Enum.sort()

      File.exists?(path) ->
        [path]

      true ->
        []
    end
  end

  defp upsert_transactions(transactions) do
    Enum.reduce(transactions, 0, fn attrs, count ->
      case upsert_transaction(attrs) do
        {:ok, :inserted} -> count + 1
        _ -> count
      end
    end)
  end

  defp upsert_transaction(attrs) do
    # Check existence first since binary_id is generated client-side
    # and on_conflict: :nothing won't signal skips with UUIDs
    exists =
      attrs[:external_id] &&
        Repo.exists?(
          from(t in BrokerTransaction,
            where: t.broker == ^attrs.broker and t.external_id == ^attrs.external_id
          )
        )

    if exists do
      {:ok, :skipped}
    else
      changeset = BrokerTransaction.changeset(%BrokerTransaction{}, attrs)

      case Repo.insert(changeset) do
        {:ok, _} -> {:ok, :inserted}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end
end
