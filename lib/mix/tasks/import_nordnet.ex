defmodule Mix.Tasks.Import.Nordnet do
  @moduledoc """
  Import Nordnet transaction CSV into database.

  Usage:
    mix import.nordnet                              # Default: csv_data/nordnet/
    mix import.nordnet path/to/file.csv             # Single file
    mix import.nordnet path/to/directory/            # All CSVs in directory
    mix import.nordnet --9a path/to/9a-report.csv   # Import 9A tax report
  """
  use Mix.Task

  import Ecto.Query

  alias Dividendsomatic.Portfolio.{
    BrokerTransaction,
    Nordnet9aParser,
    NordnetCsvParser,
    SoldPosition
  }

  alias Dividendsomatic.Portfolio.Processors.{
    CostProcessor,
    DividendProcessor,
    SoldPositionProcessor
  }

  alias Dividendsomatic.Repo

  @shortdoc "Import Nordnet transaction CSV"
  def run(args) do
    Mix.Task.run("app.start")

    if "--9a" in args do
      args_without_flag = Enum.reject(args, &(&1 == "--9a"))
      import_9a(args_without_flag)
    else
      path = List.first(args) || "csv_data/nordnet/"

      files = resolve_files(path)

      if files == [] do
        IO.puts("No CSV files found at: #{path}")
      else
        import_files(files)
      end
    end
  end

  defp import_9a(args) do
    path = List.first(args) || "csv_data/nordnet/"
    files = resolve_files(path)

    if files == [] do
      IO.puts("No 9A report files found at: #{path}")
    else
      Enum.each(files, &import_9a_file/1)
    end
  end

  defp import_9a_file(file) do
    IO.puts("Parsing 9A report: #{Path.basename(file)}...")

    case Nordnet9aParser.parse_file(file) do
      {:ok, trades} ->
        IO.puts("  Parsed #{length(trades)} realized trades")
        attrs_list = Nordnet9aParser.to_sold_position_attrs(trades)
        upserted = upsert_9a_positions(attrs_list)
        IO.puts("  Upserted #{upserted} sold positions")

      {:error, reason} ->
        IO.puts("  Error: #{reason}")
    end
  end

  defp upsert_9a_positions(attrs_list) do
    Enum.reduce(attrs_list, 0, &upsert_single_9a_position/2)
  end

  defp upsert_single_9a_position(attrs, count) do
    exists =
      Repo.exists?(
        from(s in SoldPosition,
          where:
            s.source == "nordnet_9a" and
              s.symbol == ^attrs.symbol and
              s.sale_date == ^attrs.sale_date and
              s.quantity == ^attrs.quantity
        )
      )

    if exists do
      count
    else
      case %SoldPosition{} |> SoldPosition.changeset(attrs) |> Repo.insert() do
        {:ok, _} -> count + 1
        {:error, _} -> count
      end
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

    Dividendsomatic.Portfolio.invalidate_chart_cache()

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
