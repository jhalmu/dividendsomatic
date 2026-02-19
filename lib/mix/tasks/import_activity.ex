defmodule Mix.Tasks.Import.Activity do
  @moduledoc """
  Import IBKR Activity Statement CSV files into clean tables.

  ## Usage

      mix import.activity                    # Import all CSVs in csv_data/
      mix import.activity path/to/file.csv   # Import a single file
      mix import.activity --verify           # Import all + run verification

  Uses two-pass import: instruments from ALL files first, then transactions.
  """

  use Mix.Task

  alias Dividendsomatic.Portfolio.IbkrActivityParser

  require Logger

  @shortdoc "Import IBKR Activity Statement CSVs into clean tables"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    # Suppress debug logging during import
    Logger.configure(level: :info)

    {opts, files, _} = OptionParser.parse(args, switches: [verify: :boolean])

    files =
      if files == [] do
        discover_csv_files()
      else
        files
      end

    if files == [] do
      Mix.shell().error("No CSV files found. Place IBKR Activity Statement CSVs in csv_data/")
      exit({:shutdown, 1})
    end

    Mix.shell().info("Importing #{length(files)} IBKR Activity Statement files...\n")

    # Two-pass import via import_all
    results = IbkrActivityParser.import_all(files)

    print_summary(results)

    if opts[:verify] do
      Mix.shell().info("\n--- Verification ---")
      verify()
    end
  end

  defp discover_csv_files do
    csv_dir = Path.join(File.cwd!(), "csv_data")

    if File.dir?(csv_dir) do
      csv_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".csv"))
      |> Enum.sort_by(&extract_date_range/1)
      |> Enum.map(&Path.join(csv_dir, &1))
    else
      []
    end
  end

  defp extract_date_range(filename) do
    case Regex.run(~r/(\d{8})_(\d{8})/, filename) do
      [_, start_date, _end_date] -> start_date
      _ -> filename
    end
  end

  defp print_summary(results) do
    Mix.shell().info("\n=== Import Summary ===")

    totals =
      Enum.reduce(results, %{trades: 0, dividends: 0, cash_flows: 0, interest: 0, fees: 0}, fn r,
                                                                                               acc ->
        %{
          trades: acc.trades + (r.trades[:inserted] || 0),
          dividends: acc.dividends + (r.dividends[:inserted] || 0),
          cash_flows: acc.cash_flows + (r.cash_flows[:inserted] || 0),
          interest: acc.interest + (r.interest[:inserted] || 0),
          fees: acc.fees + (r.fees[:inserted] || 0)
        }
      end)

    Mix.shell().info("  Trades: #{totals.trades}")
    Mix.shell().info("  Dividends: #{totals.dividends}")
    Mix.shell().info("  Cash flows: #{totals.cash_flows}")
    Mix.shell().info("  Interest: #{totals.interest}")
    Mix.shell().info("  Fees: #{totals.fees}")
  end

  defp verify do
    alias Dividendsomatic.Repo

    alias Dividendsomatic.Portfolio.{
      CashFlow,
      DividendPayment,
      Instrument,
      InstrumentAlias,
      Trade
    }

    import Ecto.Query

    instrument_count = Repo.aggregate(Instrument, :count)
    alias_count = Repo.aggregate(InstrumentAlias, :count)
    trade_count = Repo.aggregate(Trade, :count)
    dividend_count = Repo.aggregate(DividendPayment, :count)
    cash_flow_count = Repo.aggregate(CashFlow, :count)

    Mix.shell().info("  Instruments: #{instrument_count}")
    Mix.shell().info("  Aliases: #{alias_count}")
    Mix.shell().info("  Trades: #{trade_count}")
    Mix.shell().info("  Dividend payments: #{dividend_count}")
    Mix.shell().info("  Cash flows: #{cash_flow_count}")

    # Check for orphaned trades (no instrument)
    orphan_trades =
      Repo.one(
        from t in Trade,
          left_join: i in Instrument,
          on: t.instrument_id == i.id,
          where: is_nil(i.id),
          select: count(t.id)
      )

    orphan_divs =
      Repo.one(
        from d in DividendPayment,
          left_join: i in Instrument,
          on: d.instrument_id == i.id,
          where: is_nil(i.id),
          select: count(d.id)
      )

    Mix.shell().info("  Orphaned trades (no instrument): #{orphan_trades}")
    Mix.shell().info("  Orphaned dividends (no instrument): #{orphan_divs}")

    # Dividend totals by currency
    div_totals =
      Repo.all(
        from d in DividendPayment,
          group_by: d.currency,
          select: {d.currency, sum(d.net_amount)},
          order_by: [asc: d.currency]
      )

    Mix.shell().info("\n  Dividend totals by currency:")

    Enum.each(div_totals, fn {currency, total} ->
      Mix.shell().info("    #{currency}: #{Decimal.round(total, 2)}")
    end)
  end
end
