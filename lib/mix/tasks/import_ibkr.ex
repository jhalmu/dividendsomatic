defmodule Mix.Tasks.Import.Ibkr do
  @moduledoc """
  Import IBKR Transaction History CSV/PDF into database.

  Usage:
    mix import.ibkr                           # Default: csv_data/ibkr/
    mix import.ibkr path/to/file.csv          # Single CSV file
    mix import.ibkr path/to/file.pdf          # Single PDF file
    mix import.ibkr path/to/directory/         # All CSVs + PDFs in directory
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{BrokerTransaction, IbkrCsvParser, IbkrPdfParser}

  alias Dividendsomatic.Portfolio.Processors.{
    CostProcessor,
    DividendProcessor,
    SoldPositionProcessor
  }

  alias Dividendsomatic.Repo

  @shortdoc "Import IBKR Transaction History CSV/PDF"

  def run(args) do
    Mix.Task.run("app.start")

    path = List.first(args) || "csv_data/ibkr/"
    files = resolve_files(path)

    if files == [] do
      IO.puts("No CSV/PDF files found at: #{path}")
    else
      import_files(files)
    end
  end

  defp import_files(files) do
    IO.puts("Found #{length(files)} file(s)")

    {total_txns, total_new} =
      Enum.reduce(files, {0, 0}, fn file, {txn_acc, new_acc} ->
        {parsed, new} = import_single_file(file)
        {txn_acc + parsed, new_acc + new}
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
    print_type_breakdown()
  end

  defp import_single_file(file) do
    IO.puts("\nParsing #{Path.basename(file)}...")

    parser = if String.ends_with?(file, ".pdf"), do: IbkrPdfParser, else: IbkrCsvParser

    case parser.parse_file(file) do
      {:ok, transactions} ->
        IO.puts("  Parsed #{length(transactions)} transactions")
        new_count = upsert_transactions(transactions)
        IO.puts("  Upserted #{new_count} new transactions")
        {length(transactions), new_count}

      {:error, reason} ->
        IO.puts("  Error: #{reason}")
        {0, 0}
    end
  end

  defp print_type_breakdown do
    counts =
      BrokerTransaction
      |> where([t], t.broker == "ibkr")
      |> group_by([t], t.transaction_type)
      |> select([t], {t.transaction_type, count(t.id)})
      |> Repo.all()

    if counts != [] do
      IO.puts("\n  IBKR transaction breakdown:")

      Enum.each(Enum.sort(counts), fn {type, count} ->
        IO.puts("    #{type}: #{count}")
      end)
    end
  end

  defp resolve_files(path) do
    cond do
      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.filter(fn f -> String.ends_with?(f, ".csv") || String.ends_with?(f, ".pdf") end)
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
