defmodule Mix.Tasks.Import.YahooDividends do
  @moduledoc """
  Import dividend data from Yahoo Finance JSON files in the archive directory.

  ## Usage

      mix import.yahoo_dividends                              # Import from csv_data/archive/dividends/
      mix import.yahoo_dividends path/to/directory            # Import from specific directory

  JSON files are created by `tools/yfinance_fetch.py`.
  Records are stored with `amount_type: "per_share"`.
  """
  use Mix.Task

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.{Dividend, YahooDividendParser}
  alias Dividendsomatic.Repo

  @shortdoc "Import Yahoo Finance dividend JSON files from archive"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    dir = List.first(args) || "csv_data/archive/dividends"

    case File.ls(dir) do
      {:ok, files} ->
        json_files =
          files
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.sort()

        Mix.shell().info("Found #{length(json_files)} Yahoo dividend JSON files in #{dir}/")

        {total_imported, total_skipped} =
          Enum.reduce(json_files, {0, 0}, fn file, {imp, skip} ->
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
    case YahooDividendParser.parse_file(path) do
      {:ok, records} ->
        {new, dup} = count_results(records)
        if new > 0, do: Mix.shell().info("  #{filename}: #{new} new, #{dup} skipped")
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
    if is_nil(record.ex_date) or dividend_exists?(record) do
      :skipped
    else
      attrs = %{
        symbol: record.symbol,
        ex_date: record.ex_date,
        amount: record.amount,
        currency: record.currency,
        source: "yfinance",
        isin: record.isin,
        amount_type: "per_share"
      }

      case %Dividend{} |> Dividend.changeset(attrs) |> Repo.insert() do
        {:ok, _} -> :created
        {:error, _} -> :skipped
      end
    end
  end

  defp dividend_exists?(record) do
    by_isin =
      if record.isin do
        Dividend
        |> where([d], d.isin == ^record.isin and d.ex_date == ^record.ex_date)
        |> Repo.exists?()
      else
        false
      end

    if by_isin do
      true
    else
      Dividend
      |> where([d], d.symbol == ^record.symbol and d.ex_date == ^record.ex_date)
      |> Repo.exists?()
    end
  end
end
