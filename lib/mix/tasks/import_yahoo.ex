defmodule Mix.Tasks.Import.Yahoo do
  @moduledoc """
  Import dividend data from yfinance JSON files.

  ## Usage

      mix import.yahoo dividends              # Import all from csv_data/dividends/
      mix import.yahoo dividends KESKOB.HE    # Import specific file

  JSON files are created by `tools/yfinance_fetch.py`.
  """
  use Mix.Task

  require Logger

  @shortdoc "Import yfinance dividend JSON data"

  @impl true
  def run(["dividends" | rest]) do
    Mix.Task.run("app.start")

    files = resolve_dividend_files(rest)

    {imported, skipped, errors} =
      Enum.reduce(files, {0, 0, 0}, fn file, {imp, skip, err} ->
        case import_dividend_file(file) do
          {:ok, new, dup} -> {imp + new, skip + dup, err}
          {:error, _} -> {imp, skip, err + 1}
        end
      end)

    Mix.shell().info(
      "Done: #{imported} imported, #{skipped} duplicates skipped, #{errors} errors"
    )
  end

  def run(_) do
    Mix.shell().info("Usage: mix import.yahoo dividends [SYMBOL]")
  end

  defp resolve_dividend_files([arg]) do
    path =
      if String.ends_with?(arg, ".json") and File.exists?(arg) do
        arg
      else
        Path.join(["csv_data", "dividends", "#{arg}.json"])
      end

    if File.exists?(path),
      do: [path],
      else:
        (
          Mix.shell().error("File not found: #{path}")
          []
        )
  end

  defp resolve_dividend_files([]) do
    dir = Path.join(["csv_data", "dividends"])

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(&Path.join(dir, &1))

      {:error, _} ->
        Mix.shell().error("Directory not found: #{dir}")
        []
    end
  end

  defp import_dividend_file(path) do
    Mix.shell().info("Importing #{path}...")

    with {:ok, content} <- File.read(path),
         {:ok, records} <- Jason.decode(content) do
      {new, dup} = Enum.reduce(records, {0, 0}, &import_record/2)

      Mix.shell().info("  ✓ #{new} new, #{dup} duplicates")
      {:ok, new, dup}
    else
      {:error, reason} ->
        Mix.shell().error("  ✗ Failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp import_record(record, {new_count, dup_count}) do
    attrs = %{
      symbol: record["symbol"],
      ex_date: record["ex_date"],
      amount: record["amount"],
      currency: record["currency"] || "USD",
      source: "yfinance"
    }

    case Dividendsomatic.Portfolio.create_dividend(attrs) do
      {:ok, _} ->
        {new_count + 1, dup_count}

      {:error, %Ecto.Changeset{errors: errors}} ->
        if duplicate_error?(errors) do
          {new_count, dup_count + 1}
        else
          Logger.warning("Failed to import dividend: #{inspect(errors)}")
          {new_count, dup_count}
        end
    end
  end

  defp duplicate_error?(errors) do
    Enum.any?(errors, fn {_field, {msg, _}} ->
      String.contains?(msg, "already been taken") or String.contains?(msg, "already exists")
    end)
  end
end
