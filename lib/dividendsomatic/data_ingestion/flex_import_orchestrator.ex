defmodule Dividendsomatic.DataIngestion.FlexImportOrchestrator do
  @moduledoc """
  Orchestrates import of all IBKR Flex CSV types from a directory.

  Scans a directory, classifies each CSV by type using `FlexCsvRouter`,
  and routes to the appropriate import pipeline:

  - `:portfolio`           → `Portfolio.create_snapshot_from_csv/2`
  - `:activity_statement`  → `IbkrActivityParser.import_file/1`
  - `:dividends`           → FX rate enrichment on existing dividend_payments
  - `:trades`              → FX rate enrichment on existing trades
  - `:actions`             → `IntegrityChecker.run_all/1` (validation report)
  - `:cash_report`         → log EUR totals for validation

  Replaces `CsvDirectory` as the main import entry point for the worker.
  """

  require Logger

  import Ecto.Query

  alias Dividendsomatic.Portfolio

  alias Dividendsomatic.Portfolio.{
    DividendPayment,
    FlexCsvRouter,
    IbkrActivityParser,
    IntegrityChecker,
    Trade
  }

  alias Dividendsomatic.Portfolio.{FlexDividendCsvParser, FlexTradesCsvParser}
  alias Dividendsomatic.Repo

  @default_dir "csv_data"

  @doc """
  Imports all CSV files from a directory, routing by type.

  Returns `{:ok, summary}` with per-type results.
  """
  @spec import_all(keyword()) :: {:ok, map()} | {:error, term()}
  def import_all(opts \\ []) do
    dir = Keyword.get(opts, :dir, @default_dir)
    archive? = Keyword.get(opts, :archive, false)

    case File.ls(dir) do
      {:ok, files} ->
        csv_files =
          files
          |> Enum.filter(&String.ends_with?(&1, ".csv"))
          |> Enum.sort()

        Logger.info("FlexImportOrchestrator: found #{length(csv_files)} CSV files in #{dir}/")

        results =
          Enum.map(csv_files, fn file ->
            path = Path.join(dir, file)
            result = import_file(path, file)
            maybe_archive(archive?, result, path, dir)
            result
          end)

        summary = build_summary(results)
        Portfolio.invalidate_cache()
        Logger.info("FlexImportOrchestrator: #{inspect(summary)}")
        {:ok, summary}

      {:error, reason} ->
        Logger.warning("FlexImportOrchestrator: cannot read #{dir}: #{inspect(reason)}")
        {:error, {:directory_not_found, dir, reason}}
    end
  end

  @doc """
  Imports a single CSV file, auto-detecting its type.
  """
  @spec import_file(String.t(), String.t()) ::
          {:ok, atom(), map()} | {:skipped, atom(), String.t()} | {:error, String.t()}
  def import_file(path, filename \\ nil) do
    filename = filename || Path.basename(path)

    case File.read(path) do
      {:ok, content} ->
        type = FlexCsvRouter.detect_csv_type(content)
        Logger.info("FlexImportOrchestrator: #{filename} → #{type}")
        route_import(type, content, path, filename)

      {:error, reason} ->
        Logger.warning("FlexImportOrchestrator: cannot read #{filename}: #{inspect(reason)}")
        {:error, "cannot read #{filename}"}
    end
  end

  defp route_import(:portfolio, content, _path, filename) do
    with {:ok, date} <- Portfolio.CsvParser.extract_report_date(content),
         nil <- Portfolio.get_snapshot_by_date(date),
         {:ok, snapshot} <- Portfolio.create_snapshot_from_csv(content, date) do
      Logger.info(
        "FlexImportOrchestrator: imported portfolio snapshot #{date} " <>
          "(#{snapshot.positions_count} positions)"
      )

      {:ok, :portfolio, %{date: date, positions: snapshot.positions_count}}
    else
      %Dividendsomatic.Portfolio.PortfolioSnapshot{date: date} ->
        Logger.info("FlexImportOrchestrator: portfolio #{date} already exists, skipping")
        {:skipped, :portfolio, "#{filename}: date #{date} exists"}

      {:error, reason} ->
        {:error, "portfolio import failed for #{filename}: #{inspect(reason)}"}
    end
  end

  defp route_import(:activity_statement, _content, path, filename) do
    result = IbkrActivityParser.import_file(path)

    Logger.info(
      "FlexImportOrchestrator: #{filename} activity import → " <>
        "trades: #{inspect(result[:trades])}, dividends: #{inspect(result[:dividends])}, " <>
        "cash_flows: #{inspect(result[:cash_flows])}"
    )

    {:ok, :activity_statement, result}
  rescue
    e ->
      {:error, "activity import failed for #{filename}: #{Exception.message(e)}"}
  end

  defp route_import(:dividends, content, _path, filename) do
    {_type, cleaned} = FlexCsvRouter.classify_and_clean(content)
    enriched = enrich_dividend_fx_rates(cleaned)

    Logger.info(
      "FlexImportOrchestrator: #{filename} enriched #{enriched} dividends with FX rates"
    )

    {:ok, :dividends, %{fx_enriched: enriched}}
  end

  defp route_import(:trades, content, _path, filename) do
    {_type, cleaned} = FlexCsvRouter.classify_and_clean(content)
    enriched = enrich_trade_fx_rates(cleaned)

    Logger.info("FlexImportOrchestrator: #{filename} enriched #{enriched} trades with FX rates")

    {:ok, :trades, %{fx_enriched: enriched}}
  end

  defp route_import(:cash_report, content, _path, filename) do
    summary = extract_cash_report_summary(content)

    Logger.info("FlexImportOrchestrator: #{filename} cash report → #{inspect(summary)}")

    {:ok, :cash_report, summary}
  end

  defp route_import(:actions, _content, path, filename) do
    case IntegrityChecker.run_all(path) do
      {:ok, checks} ->
        pass = Enum.count(checks, &(&1.status == :pass))
        fail = Enum.count(checks, &(&1.status == :fail))
        warn = Enum.count(checks, &(&1.status == :warn))

        Logger.info(
          "FlexImportOrchestrator: #{filename} integrity → #{pass} PASS, #{warn} WARN, #{fail} FAIL"
        )

        {:ok, :actions, %{pass: pass, warn: warn, fail: fail, checks: checks}}

      {:error, reason} ->
        {:error, "integrity check failed for #{filename}: #{inspect(reason)}"}
    end
  end

  defp route_import(:unknown, _content, _path, filename) do
    Logger.warning("FlexImportOrchestrator: #{filename} has unknown CSV type, skipping")
    {:skipped, :unknown, "#{filename}: unknown type"}
  end

  defp maybe_archive(true, result, path, dir) when elem(result, 0) != :error do
    archive_file(path, dir)
  end

  defp maybe_archive(_archive?, _result, _path, _dir), do: :noop

  defp archive_file(path, _dir) do
    archive_dir = Path.join([File.cwd!(), "data_archive", "flex"])

    with :ok <- File.mkdir_p(archive_dir) do
      dest = Path.join(archive_dir, Path.basename(path))
      Logger.info("FlexImportOrchestrator: archiving #{Path.basename(path)} → data_archive/flex/")
      File.rename(path, dest)
    end
  end

  # --- FX Rate Enrichment ---

  # Enrich dividend_payments with FX rates from Flex Dividends CSV.
  # Matches by instrument ISIN + pay_date + net_amount, updates fx_rate + amount_eur where NULL.
  defp enrich_dividend_fx_rates(cleaned_csv) do
    case FlexDividendCsvParser.parse(cleaned_csv) do
      {:ok, records} -> count_enriched(records, &enrich_single_dividend/1)
      {:error, _} -> 0
    end
  end

  defp count_enriched(records, enrich_fn) do
    Enum.reduce(records, 0, fn record, count ->
      case enrich_fn.(record) do
        {:ok, _} -> count + 1
        _ -> count
      end
    end)
  end

  defp enrich_single_dividend(record) do
    isin = record[:isin]
    pay_date = record[:pay_date]
    fx_rate = record[:fx_rate] || record[:exchange_rate]

    with true <- is_binary(isin) and isin != "",
         %Date{} <- pay_date,
         %Decimal{} <- fx_rate,
         false <- Decimal.equal?(fx_rate, 0) do
      query =
        from dp in DividendPayment,
          join: i in assoc(dp, :instrument),
          where: i.isin == ^isin and dp.pay_date == ^pay_date and is_nil(dp.fx_rate),
          select: dp

      update_matching_dividends(Repo.all(query), fx_rate)
    else
      _ -> :skip
    end
  end

  defp update_matching_dividends([], _fx_rate), do: :no_match

  defp update_matching_dividends(payments, fx_rate) do
    Enum.each(payments, fn dp ->
      amount_eur = Decimal.div(dp.net_amount, fx_rate)

      dp
      |> Ecto.Changeset.change(%{fx_rate: fx_rate, amount_eur: amount_eur})
      |> Repo.update()
    end)

    {:ok, length(payments)}
  end

  # Enrich trades with FX rates from Flex Trades CSV.
  # Matches by instrument ISIN + trade_date + trade_id, updates fx_rate where NULL.
  defp enrich_trade_fx_rates(cleaned_csv) do
    case FlexTradesCsvParser.parse(cleaned_csv) do
      {:ok, records} -> count_enriched(records, &enrich_single_trade/1)
      {:error, _} -> 0
    end
  end

  defp enrich_single_trade(record) do
    isin = record[:isin]
    trade_date = record[:trade_date]
    fx_rate = record[:exchange_rate]
    trade_id = get_in(record, [:raw_data, "trade_id"])

    with true <- is_binary(isin) and isin != "",
         %Date{} <- trade_date,
         %Decimal{} <- fx_rate,
         false <- Decimal.equal?(fx_rate, 0) do
      query =
        from t in Trade,
          join: i in assoc(t, :instrument),
          where: i.isin == ^isin and t.trade_date == ^trade_date and is_nil(t.fx_rate)

      query = maybe_filter_by_trade_id(query, trade_id)
      update_matching_trades(Repo.all(query), fx_rate)
    else
      _ -> :skip
    end
  end

  defp maybe_filter_by_trade_id(query, trade_id) when is_binary(trade_id) and trade_id != "" do
    from t in query,
      where: fragment("?->>'trade_id' = ?", t.raw_data, ^trade_id)
  end

  defp maybe_filter_by_trade_id(query, _trade_id), do: query

  defp update_matching_trades([], _fx_rate), do: :no_match

  defp update_matching_trades(trades, fx_rate) do
    Enum.each(trades, fn t ->
      t
      |> Ecto.Changeset.change(%{fx_rate: fx_rate})
      |> Repo.update()
    end)

    {:ok, length(trades)}
  end

  # --- Cash Report Summary ---

  # Extracts summary totals from a Cash Report CSV.
  # Looks for the BASE_SUMMARY row with EUR totals.
  defp extract_cash_report_summary(content) do
    lines =
      content
      |> String.split(~r/\r?\n/, trim: true)
      |> Enum.map(&String.trim/1)

    case lines do
      [header | data_lines] ->
        headers =
          header
          |> String.split(",")
          |> Enum.map(&String.trim(&1, "\""))

        # Find BASE_SUMMARY row (has pre-computed EUR totals)
        base_row =
          Enum.find(data_lines, fn line ->
            String.contains?(line, "BASE_SUMMARY")
          end)

        if base_row do
          values =
            base_row
            |> String.split(",")
            |> Enum.map(&String.trim(&1, "\""))

          pairs = Enum.zip(headers, values) |> Map.new()

          %{
            level: "BASE_SUMMARY",
            starting_cash: pairs["StartingCash"],
            ending_cash: pairs["EndingCash"],
            dividends: pairs["Dividends"],
            interest: pairs["BrokerInterest"],
            deposits_withdrawals: pairs["Deposits/Withdrawals"]
          }
        else
          %{level: "no_base_summary", raw_rows: length(data_lines)}
        end

      _ ->
        %{level: "empty"}
    end
  end

  defp build_summary(results) do
    count = fn type ->
      results |> Enum.filter(&match?({:ok, ^type, _}, &1)) |> length()
    end

    %{
      portfolio: count.(:portfolio),
      activity_statement: count.(:activity_statement),
      dividends: count.(:dividends),
      trades: count.(:trades),
      actions: count.(:actions),
      cash_report: count.(:cash_report),
      skipped: results |> Enum.filter(&match?({:skipped, _, _}, &1)) |> length(),
      errors: results |> Enum.filter(&match?({:error, _}, &1)) |> length()
    }
  end
end
