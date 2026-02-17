defmodule Mix.Tasks.Import.FlexTrades do
  @moduledoc """
  Import trades from an IBKR Flex Trades CSV file.

  ## Usage

      mix import.flex_trades path/to/Trades.csv

  The 14-column format includes: ISIN, FIGI, CUSIP, Conid, Symbol,
  CurrencyPrimary, FXRateToBase, TradeID, TradeDate, Quantity,
  TradePrice, Taxes, Buy/Sell, ListingExchange.

  Deduplicates by broker+external_id. FX trades (EUR.SEK, EUR.HKD)
  are classified as fx_buy/fx_sell.
  """
  use Mix.Task

  alias Dividendsomatic.Portfolio

  @shortdoc "Import IBKR Flex trades CSV"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [path] ->
        import_file(path)

      _ ->
        Mix.shell().error("Usage: mix import.flex_trades path/to/Trades.csv")
    end
  end

  defp import_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case Portfolio.import_flex_trades_csv(content) do
          {:ok, %{imported: imported, skipped: skipped}} ->
            Mix.shell().info(
              "Imported #{imported} trades, #{skipped} duplicates skipped from #{path}"
            )

          {:error, reason} ->
            Mix.shell().error("Parse error: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.shell().error("Cannot read file #{path}: #{reason}")
    end
  end
end
