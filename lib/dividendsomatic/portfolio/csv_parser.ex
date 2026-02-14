defmodule Dividendsomatic.Portfolio.CsvParser do
  @moduledoc """
  Header-based CSV parser for Interactive Brokers Flex reports.

  Parses CSV by column name (not position), supporting both format variants:
  - Format A (17 cols): older reports with HoldingPeriodDateTime, no Description/FifoPnlUnrealized
  - Format B (18 cols): newer reports with Description and FifoPnlUnrealized

  Unknown columns are logged but not treated as errors (forward-compatible).
  """

  require Logger

  NimbleCSV.define(IBParser, separator: ",", escape: "\"")

  # Maps CSV headers to Position schema field names
  @header_map %{
    "ReportDate" => :_report_date,
    "CurrencyPrimary" => :currency,
    "Symbol" => :symbol,
    "Description" => :name,
    "SubCategory" => :_sub_category,
    "Quantity" => :quantity,
    "MarkPrice" => :price,
    "PositionValue" => :value,
    "CostBasisPrice" => :cost_price,
    "CostBasisMoney" => :cost_basis,
    "OpenPrice" => :_open_price,
    "PercentOfNAV" => :weight,
    "FifoPnlUnrealized" => :unrealized_pnl,
    "ListingExchange" => :exchange,
    "AssetClass" => :asset_class,
    "FXRateToBase" => :fx_rate,
    "ISIN" => :isin,
    "FIGI" => :figi,
    "HoldingPeriodDateTime" => :_holding_period
  }

  # Fields prefixed with _ are parsed but dropped from output
  @dropped_fields [:_report_date, :_sub_category, :_open_price, :_holding_period]

  @decimal_fields [
    :quantity,
    :price,
    :value,
    :cost_price,
    :cost_basis,
    :_open_price,
    :weight,
    :unrealized_pnl,
    :fx_rate
  ]

  @doc """
  Parses CSV string and returns a list of attribute maps ready for Position changeset.

  Each map contains the snapshot_id, date, and all parsed fields from the CSV row.
  """
  def parse(csv_data, snapshot_id, report_date) do
    rows = IBParser.parse_string(csv_data, skip_headers: false)

    case rows do
      [] ->
        []

      [header_row | data_rows] ->
        column_index = build_column_index(header_row)
        Enum.map(data_rows, &row_to_attrs(&1, column_index, snapshot_id, report_date))
    end
  end

  @doc """
  Extracts the report date from CSV data.

  Reads the first data row and extracts the ReportDate field using header mapping.
  """
  def extract_report_date(csv_data) do
    rows = IBParser.parse_string(csv_data, skip_headers: false)

    case rows do
      [] ->
        {:error, "no data rows"}

      [_header] ->
        {:error, "no data rows"}

      [header_row | [first_data_row | _]] ->
        column_index = build_column_index(header_row)

        case Map.get(column_index, :_report_date) do
          nil ->
            {:error, "no ReportDate column"}

          idx ->
            date_str = Enum.at(first_data_row, idx)
            parse_date_value(date_str)
        end
    end
  end

  @doc """
  Returns the detected CSV format based on headers.

  - `:format_a` - older format with HoldingPeriodDateTime (17 cols, no Description)
  - `:format_b` - newer format with Description and FifoPnlUnrealized (18 cols)
  - `:unknown` - unrecognized format
  """
  def detect_format(csv_data) do
    rows = IBParser.parse_string(csv_data, skip_headers: false)

    case rows do
      [] ->
        :unknown

      [header_row | _] ->
        headers = MapSet.new(Enum.map(header_row, &String.trim/1))

        cond do
          MapSet.member?(headers, "HoldingPeriodDateTime") -> :format_a
          MapSet.member?(headers, "Description") -> :format_b
          true -> :unknown
        end
    end
  end

  # Builds a map of %{field_atom => column_index} from the header row
  defp build_column_index(header_row) do
    header_row
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {header, idx}, acc ->
      header = String.trim(header)

      case Map.get(@header_map, header) do
        nil ->
          Logger.debug("Unknown CSV column: #{header}")
          acc

        field ->
          Map.put(acc, field, idx)
      end
    end)
  end

  defp row_to_attrs(row, column_index, snapshot_id, report_date) do
    attrs =
      Enum.reduce(column_index, %{portfolio_snapshot_id: snapshot_id}, fn {field, idx}, acc ->
        value = Enum.at(row, idx)
        Map.put(acc, field, convert_value(field, value))
      end)

    attrs
    |> Map.put(:date, report_date)
    |> Map.put(:data_source, "ibkr_flex")
    |> Map.drop(@dropped_fields)
  end

  defp convert_value(:_report_date, value), do: parse_date(value)

  defp convert_value(field, value) when field in @decimal_fields, do: parse_decimal(value)

  defp convert_value(_field, value), do: value

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date_value(nil), do: {:error, "invalid date: nil"}
  defp parse_date_value(""), do: {:error, "invalid date: empty"}

  defp parse_date_value(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, "invalid date: #{value}"}
    end
  end

  defp parse_decimal(nil), do: Decimal.new("0")
  defp parse_decimal(""), do: Decimal.new("0")

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} ->
        decimal

      :error ->
        Logger.warning("Failed to parse decimal: #{inspect(value)}, defaulting to 0")
        Decimal.new("0")
    end
  end
end
