defmodule Mix.Tasks.Import.FlexDividends do
  @moduledoc """
  Import dividend data from IBKR Flex dividend CSV reports.

  ## Usage

      mix import.flex_dividends                          # Import from csv_data/Dividends-2019-2024/
      mix import.flex_dividends path/to/directory        # Import from specific directory

  These CSVs contain total net amounts (post-withholding) with FX rates.
  Records are stored with `amount_type: "total_net"`.
  """
  use Mix.Task

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.{Dividend, IbkrFlexDividendParser}
  alias Dividendsomatic.Repo

  @shortdoc "Import IBKR Flex dividend CSV reports"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    dir = List.first(args) || "csv_data/Dividends-2019-2024"

    case File.ls(dir) do
      {:ok, files} ->
        csv_files =
          files
          |> Enum.filter(&String.ends_with?(&1, ".csv"))
          |> Enum.sort()

        Mix.shell().info("Found #{length(csv_files)} Flex dividend CSV files in #{dir}/")

        {total_imported, total_skipped} =
          Enum.reduce(csv_files, {0, 0}, fn file, {imp, skip} ->
            path = Path.join(dir, file)
            {new, dup} = import_file(path, file)
            {imp + new, skip + dup}
          end)

        Mix.shell().info(
          "\nDone: #{total_imported} imported, #{total_skipped} duplicates skipped"
        )

      {:error, reason} ->
        Mix.shell().error("Error reading directory #{dir}: #{reason}")
    end
  end

  defp import_file(path, filename) do
    case IbkrFlexDividendParser.parse_file(path) do
      {:ok, records} ->
        {new, dup} = count_results(records)
        Mix.shell().info("  #{filename}: #{new} new, #{dup} skipped")
        {new, dup}

      {:error, reason} ->
        Mix.shell().error("  #{filename}: FAILED (#{inspect(reason)})")
        {0, 0}
    end
  end

  defp count_results(records) do
    Enum.reduce(records, {0, 0}, fn record, {n, d} ->
      case insert_dividend(record) do
        :created -> {n + 1, d}
        :skipped -> {n, d + 1}
      end
    end)
  end

  defp insert_dividend(record) do
    # Dedup by ISIN + pay_date, or symbol + pay_date
    if dividend_exists?(record) do
      :skipped
    else
      attrs = %{
        symbol: record.symbol,
        ex_date: record.pay_date || Date.utc_today(),
        pay_date: record.pay_date,
        amount: record.net_amount,
        currency: derive_currency(record),
        source: "ibkr_flex_dividend",
        isin: record.isin,
        amount_type: "total_net"
      }

      case %Dividend{} |> Dividend.changeset(attrs) |> Repo.insert() do
        {:ok, _} -> :created
        {:error, _} -> :skipped
      end
    end
  end

  defp dividend_exists?(record) do
    date = record.pay_date

    if is_nil(date) do
      false
    else
      by_isin =
        if record.isin do
          Dividend
          |> where([d], d.isin == ^record.isin and d.ex_date == ^date)
          |> Repo.exists?()
        else
          false
        end

      if by_isin do
        true
      else
        Dividend
        |> where([d], d.symbol == ^record.symbol and d.ex_date == ^date)
        |> Repo.exists?()
      end
    end
  end

  @isin_prefix_to_currency %{
    "US" => "USD",
    "CA" => "CAD",
    "SE" => "SEK",
    "FI" => "EUR"
  }

  defp derive_currency(record) do
    isin_currency(record.isin) || fx_rate_currency(record.fx_rate) || "USD"
  end

  defp isin_currency(nil), do: nil

  defp isin_currency(isin) do
    prefix = String.slice(isin, 0, 2)
    Map.get(@isin_prefix_to_currency, prefix)
  end

  defp fx_rate_currency(nil), do: nil

  defp fx_rate_currency(fx_rate) do
    if Decimal.equal?(fx_rate, Decimal.new("1")), do: "EUR"
  end
end
