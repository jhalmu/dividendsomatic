defmodule Dividendsomatic.Portfolio.FlexPortfolioAccrualsParser do
  @moduledoc """
  Parses a combined IBKR Flex CSV that contains both Portfolio positions
  and Dividend Accruals sections.

  The file has two header rows with different columns:
  1. Portfolio section (has MarkPrice, PositionValue, etc.)
  2. Accruals section (has GrossRate, ExDate, PayDate, etc.)

  Splits the file at the second header row, delegates portfolio positions
  to `CsvParser`, and parses accruals to update instrument dividend rates.
  """

  require Logger

  alias Dividendsomatic.Portfolio
  alias Dividendsomatic.Portfolio.{CsvParser, Instrument}
  alias Dividendsomatic.Repo

  import Ecto.Query

  @doc """
  Imports a combined portfolio+accruals CSV.

  Returns `{:ok, %{portfolio: result, accruals: result}}` or `{:error, reason}`.
  """
  def import(csv_string) when is_binary(csv_string) do
    {portfolio_csv, accruals_csv} = split_sections(csv_string)

    portfolio_result = import_portfolio_section(portfolio_csv)
    accruals_result = import_accruals_section(accruals_csv)

    {:ok, %{portfolio: portfolio_result, accruals: accruals_result}}
  end

  @doc """
  Splits a combined CSV into portfolio and accruals sections.

  Returns `{portfolio_csv, accruals_csv}`.
  """
  def split_sections(csv_string) do
    lines = String.split(csv_string, ~r/\r?\n/)

    # Find the second header row (contains GrossRate + ExDate)
    {portfolio_lines, accruals_lines} =
      case find_accruals_header_index(lines) do
        nil ->
          # No accruals section found — entire file is portfolio
          {lines, []}

        idx ->
          {Enum.take(lines, idx), Enum.drop(lines, idx)}
      end

    {Enum.join(portfolio_lines, "\n"), Enum.join(accruals_lines, "\n")}
  end

  defp find_accruals_header_index(lines) do
    lines
    |> Enum.with_index()
    |> Enum.drop(1)
    |> Enum.find_value(fn {line, idx} ->
      trimmed = String.trim(line)

      if String.contains?(trimmed, "GrossRate") and String.contains?(trimmed, "ExDate") do
        idx
      end
    end)
  end

  defp import_portfolio_section(""), do: {:skipped, "empty portfolio section"}

  defp import_portfolio_section(csv) do
    with {:ok, date} <- CsvParser.extract_report_date(csv),
         nil <- Portfolio.get_snapshot_by_date(date),
         {:ok, snapshot} <- Portfolio.create_snapshot_from_csv(csv, date) do
      Logger.info(
        "PortfolioAccruals: imported snapshot #{date} (#{snapshot.positions_count} positions)"
      )

      {:ok, %{date: date, positions: snapshot.positions_count}}
    else
      %Dividendsomatic.Portfolio.PortfolioSnapshot{date: date} ->
        {:skipped, "date #{date} exists"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp import_accruals_section(""), do: {:skipped, "no accruals section"}

  defp import_accruals_section(csv) do
    lines = String.split(csv, ~r/\r?\n/, trim: true)

    case lines do
      [header | data_lines] ->
        headers = parse_header(header)
        records = Enum.map(data_lines, &parse_accrual_row(&1, headers))
        records = Enum.reject(records, &is_nil/1)

        updated =
          Enum.reduce(records, 0, fn record, count ->
            case update_instrument_dividend_rate(record) do
              {:ok, _} -> count + 1
              _ -> count
            end
          end)

        Logger.info(
          "PortfolioAccruals: updated #{updated} instrument dividend rates from accruals"
        )

        {:ok, %{updated: updated, total: length(records)}}

      _ ->
        {:skipped, "empty accruals"}
    end
  end

  defp parse_header(header_line) do
    header_line
    |> String.split(",")
    |> Enum.map(&String.trim(&1, "\""))
    |> Enum.map(&String.trim/1)
    |> Enum.with_index()
    |> Map.new()
  end

  defp parse_accrual_row(line, headers) do
    values =
      line
      |> String.split(",")
      |> Enum.map(&String.trim(&1, "\""))
      |> Enum.map(&String.trim/1)

    get = fn key ->
      case Map.get(headers, key) do
        nil -> nil
        idx -> Enum.at(values, idx)
      end
    end

    symbol = get.("Symbol")
    gross_rate = get.("GrossRate")
    isin = get.("ISIN")
    currency = get.("CurrencyPrimary") || get.("Currency")

    if symbol && gross_rate && gross_rate != "" do
      %{
        symbol: symbol,
        isin: isin,
        currency: currency,
        gross_rate: safe_decimal(gross_rate),
        ex_date: safe_date(get.("ExDate")),
        pay_date: safe_date(get.("PayDate"))
      }
    end
  end

  defp update_instrument_dividend_rate(%{gross_rate: nil}), do: :skip

  defp update_instrument_dividend_rate(record) do
    if Decimal.equal?(record.gross_rate, 0) do
      :skip
    else
      update_instrument_dividend_rate_impl(record)
    end
  end

  defp update_instrument_dividend_rate_impl(record) do
    instrument = find_instrument(record)

    if instrument do
      attrs = %{
        dividend_per_payment: record.gross_rate,
        dividend_source: "ibkr_accruals",
        dividend_updated_at: DateTime.utc_now()
      }

      instrument
      |> Instrument.changeset(attrs)
      |> Repo.update()
    else
      Logger.debug("PortfolioAccruals: no instrument for #{record[:symbol]}")
      :skip
    end
  end

  defp find_instrument(%{isin: isin}) when is_binary(isin) and isin != "" do
    Repo.get_by(Instrument, isin: isin)
  end

  defp find_instrument(%{symbol: symbol}) do
    from(i in Instrument,
      join: a in assoc(i, :aliases),
      where: a.symbol == ^symbol,
      limit: 1
    )
    |> Repo.one()
  end

  defp safe_decimal(nil), do: nil
  defp safe_decimal(""), do: nil

  defp safe_decimal(str) do
    case Decimal.parse(str) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end

  defp safe_date(nil), do: nil
  defp safe_date(""), do: nil

  defp safe_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
