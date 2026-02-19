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

  defp import_file(_path) do
    Mix.shell().info("Legacy trade CSV import disabled — use mix import.activity instead")
  end
end
