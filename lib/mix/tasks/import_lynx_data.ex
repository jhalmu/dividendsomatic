defmodule Mix.Tasks.Import.LynxData do
  @moduledoc """
  Import Lynx dividend data extracted from PDFs.

  Reads JSON files produced by `scripts/extract_lynx_pdfs.py`.

  ## Usage

      mix import.lynx_data                          # Import from data_revisited/lynx/
      mix import.lynx_data path/to/directory         # Import from specific directory
  """
  use Mix.Task

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.Dividend
  alias Dividendsomatic.Repo

  @shortdoc "Import Lynx PDF-extracted dividend data"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    dir = List.first(args) || "data_revisited/lynx"

    dividends_path = Path.join(dir, "dividends.json")

    if File.exists?(dividends_path) do
      import_dividends(dividends_path)
    else
      Mix.shell().info("No #{dividends_path} found. Run scripts/extract_lynx_pdfs.py first.")
    end
  end

  defp import_dividends(path) do
    Mix.shell().info("Importing Lynx dividends from #{path}...")

    case Jason.decode(File.read!(path)) do
      {:ok, records} when is_list(records) ->
        {new, skipped} = count_results(records)
        Mix.shell().info("Done: #{new} imported, #{skipped} skipped")

      _ ->
        Mix.shell().error("Failed to parse #{path}")
    end
  end

  defp count_results(records) do
    Enum.reduce(records, {0, 0}, fn record, {n, s} ->
      case insert_dividend(record) do
        :created -> {n + 1, s}
        :skipped -> {n, s + 1}
      end
    end)
  end

  defp insert_dividend(record) do
    with symbol when not is_nil(symbol) <- record["symbol"],
         date_str when not is_nil(date_str) <- record["date"],
         amount when not is_nil(amount) and amount > 0 <- record["amount"],
         {:ok, date} <- Date.from_iso8601(date_str),
         false <- dividend_exists?(symbol, date) do
      do_insert(symbol, date, amount, record)
    else
      _ -> :skipped
    end
  end

  defp do_insert(symbol, date, amount, record) do
    attrs = %{
      symbol: symbol,
      ex_date: date,
      amount: Decimal.new(to_string(amount)),
      currency: record["currency"] || "EUR",
      source: "lynx_pdf",
      amount_type: "total_net"
    }

    case %Dividend{} |> Dividend.changeset(attrs) |> Repo.insert() do
      {:ok, _} -> :created
      {:error, _} -> :skipped
    end
  end

  defp dividend_exists?(symbol, date) do
    Dividend
    |> where([d], d.symbol == ^symbol and d.ex_date == ^date)
    |> Repo.exists?()
  end
end
