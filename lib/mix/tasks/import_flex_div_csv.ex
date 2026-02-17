defmodule Mix.Tasks.Import.FlexDivCsv do
  @moduledoc """
  Import dividends from a single IBKR Flex Dividend CSV file (11-column format).

  ## Usage

      mix import.flex_div_csv path/to/Dividends.csv

  The new 11-column format includes: Symbol, ISIN, FIGI, AssetClass,
  CurrencyPrimary, FXRateToBase, ExDate, PayDate, Quantity, GrossRate, NetAmount.

  Deduplicates by ISIN+ex_date, then symbol+ex_date.
  """
  use Mix.Task

  alias Dividendsomatic.Portfolio

  @shortdoc "Import IBKR Flex dividend CSV (11-column format)"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [path] ->
        import_file(path)

      _ ->
        Mix.shell().error("Usage: mix import.flex_div_csv path/to/Dividends.csv")
    end
  end

  defp import_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case Portfolio.import_flex_dividends_csv(content) do
          {:ok, %{imported: imported, skipped: skipped}} ->
            Mix.shell().info(
              "Imported #{imported} dividends, #{skipped} duplicates skipped from #{path}"
            )

          {:error, reason} ->
            Mix.shell().error("Parse error: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.shell().error("Cannot read file #{path}: #{reason}")
    end
  end
end
