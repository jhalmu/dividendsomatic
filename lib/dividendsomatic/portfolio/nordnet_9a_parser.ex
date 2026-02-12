defmodule Dividendsomatic.Portfolio.Nordnet9aParser do
  @moduledoc """
  Parser for Nordnet 9A tax report (Finnish tax authority format).

  Parses the UTF-16 tab-separated 9A report containing realized trades
  with exact EUR figures. Dates in Finnish format (D.M.YYYY).

  Columns:
  - Arvopaperi (Security)
  - Määrä (Quantity)
  - Hankintapäivä (Purchase date)
  - Luovutuspäivä (Sale date)
  - Luovutushinta EUR (Sale price EUR)
  - Hankintahinta EUR (Purchase price EUR)
  - Hankintakulut (Purchase costs)
  - Luovutuskulut (Sale costs)
  - Hankintameno-olettama (Deemed cost)
  - Voitto/tappio EUR (P&L EUR)
  """

  require Logger

  @doc """
  Parses a 9A tax report file.

  Returns `{:ok, trades}` where trades is a list of maps with:
  - `:security_name` - Name of the security
  - `:quantity` - Number of shares (Decimal)
  - `:purchase_date` - Date of purchase
  - `:sale_date` - Date of sale
  - `:sale_price` - Total sale price in EUR (Decimal)
  - `:purchase_price` - Total purchase price in EUR (Decimal)
  - `:purchase_costs` - Purchase transaction costs (Decimal)
  - `:sale_costs` - Sale transaction costs (Decimal)
  - `:deemed_cost` - Hankintameno-olettama (Decimal)
  - `:pnl` - Profit/loss in EUR (Decimal)
  """
  def parse_file(path) do
    content = read_file(path)

    case content do
      {:ok, text} ->
        trades = parse_content(text)
        {:ok, trades}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Converts parsed 9A trades to sold_position attributes.

  Returns a list of maps suitable for upserting into sold_positions.
  """
  def to_sold_position_attrs(trades) do
    Enum.map(trades, fn trade ->
      # Calculate per-share prices from total prices
      quantity = trade.quantity
      per_share_purchase = safe_div(trade.purchase_price, quantity)
      per_share_sale = safe_div(trade.sale_price, quantity)

      %{
        symbol: extract_symbol(trade.security_name),
        description: trade.security_name,
        quantity: quantity,
        purchase_price: per_share_purchase,
        purchase_date: trade.purchase_date,
        sale_price: per_share_sale,
        sale_date: trade.sale_date,
        currency: "EUR",
        realized_pnl: trade.pnl,
        source: "nordnet_9a",
        notes:
          "9A report: costs #{Decimal.to_string(trade.purchase_costs)}+#{Decimal.to_string(trade.sale_costs)}"
      }
    end)
  end

  # Read file handling UTF-16 LE encoding (common for Nordnet exports)
  defp read_file(path) do
    case File.read(path) do
      {:ok, binary} ->
        text =
          cond do
            # UTF-16 LE BOM
            String.starts_with?(binary, <<0xFF, 0xFE>>) ->
              binary
              |> String.slice(2..-1//1)
              |> :unicode.characters_to_binary(:utf16, :utf8)
              |> handle_unicode_result()

            # UTF-16 BE BOM
            String.starts_with?(binary, <<0xFE, 0xFF>>) ->
              binary
              |> String.slice(2..-1//1)
              |> :unicode.characters_to_binary({:utf16, :big}, :utf8)
              |> handle_unicode_result()

            # UTF-8 (possibly with BOM)
            String.starts_with?(binary, <<0xEF, 0xBB, 0xBF>>) ->
              String.slice(binary, 3..-1//1)

            true ->
              binary
          end

        {:ok, text}

      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  defp handle_unicode_result(result) when is_binary(result), do: result

  defp handle_unicode_result({:error, _, _}) do
    Logger.error("Failed to decode UTF-16 content")
    ""
  end

  defp handle_unicode_result({:incomplete, converted, _}) do
    Logger.warning("Incomplete UTF-16 conversion, using partial result")
    converted
  end

  defp parse_content(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> parse_rows()
  end

  defp parse_rows([header | data_rows]) do
    columns = String.split(header, "\t") |> Enum.map(&String.trim/1)

    col_indices = detect_columns(columns)

    data_rows
    |> Enum.map(&String.split(&1, "\t"))
    |> Enum.filter(&(length(&1) >= 6))
    |> Enum.map(&parse_row(&1, col_indices))
    |> Enum.reject(&is_nil/1)
  end

  defp parse_rows([]), do: []

  defp detect_columns(columns) do
    # Try to detect columns by known Finnish headers
    %{
      security: find_col_index(columns, ["Arvopaperi", "Nimi", "Security"]),
      quantity: find_col_index(columns, ["Määrä", "Quantity"]),
      purchase_date: find_col_index(columns, ["Hankintapäivä", "Purchase date"]),
      sale_date: find_col_index(columns, ["Luovutuspäivä", "Sale date"]),
      sale_price: find_col_index(columns, ["Luovutushinta", "Sale price"]),
      purchase_price: find_col_index(columns, ["Hankintahinta", "Purchase price"]),
      purchase_costs: find_col_index(columns, ["Hankintakulut", "Purchase costs"]),
      sale_costs: find_col_index(columns, ["Luovutuskulut", "Sale costs"]),
      deemed_cost: find_col_index(columns, ["Hankintameno-olettama", "Deemed cost"]),
      pnl: find_col_index(columns, ["Voitto/tappio", "Voitto", "P&L"])
    }
  end

  defp find_col_index(columns, candidates) do
    Enum.find_value(candidates, fn candidate ->
      Enum.find_index(columns, fn col ->
        String.contains?(String.downcase(col), String.downcase(candidate))
      end)
    end)
  end

  defp parse_row(fields, col_indices) do
    %{
      security_name: get_field(fields, col_indices.security) |> String.trim(),
      quantity: get_field(fields, col_indices.quantity) |> parse_finnish_decimal(),
      purchase_date: get_field(fields, col_indices.purchase_date) |> parse_finnish_date(),
      sale_date: get_field(fields, col_indices.sale_date) |> parse_finnish_date(),
      sale_price: get_field(fields, col_indices.sale_price) |> parse_finnish_decimal(),
      purchase_price: get_field(fields, col_indices.purchase_price) |> parse_finnish_decimal(),
      purchase_costs: get_field(fields, col_indices.purchase_costs) |> parse_finnish_decimal(),
      sale_costs: get_field(fields, col_indices.sale_costs) |> parse_finnish_decimal(),
      deemed_cost: get_field(fields, col_indices.deemed_cost) |> parse_finnish_decimal(),
      pnl: get_field(fields, col_indices.pnl) |> parse_finnish_decimal()
    }
  rescue
    _ -> nil
  end

  defp get_field(_fields, nil), do: ""
  defp get_field(fields, index) when index < length(fields), do: Enum.at(fields, index)
  defp get_field(_fields, _index), do: ""

  # Parse Finnish decimal format: "1 234,56" → Decimal
  defp parse_finnish_decimal(str) do
    cleaned =
      str
      |> String.trim()
      |> String.replace(~r/\s/, "")
      |> String.replace(",", ".")
      |> String.replace(~r/[^\d.\-]/, "")

    case cleaned do
      "" -> Decimal.new("0")
      val -> Decimal.new(val)
    end
  end

  # Parse Finnish date format: "D.M.YYYY" or "DD.MM.YYYY" → Date
  defp parse_finnish_date(str) do
    trimmed = String.trim(str)

    case String.split(trimmed, ".") do
      [day, month, year] ->
        d = String.to_integer(day)
        m = String.to_integer(month)
        y = String.to_integer(year)
        Date.new!(y, m, d)

      _ ->
        # Try ISO format as fallback
        case Date.from_iso8601(trimmed) do
          {:ok, date} -> date
          _ -> nil
        end
    end
  end

  # Extract a reasonable symbol from security name (first word, uppercase)
  defp extract_symbol(name) do
    name
    |> String.split(~r/[\s,]+/)
    |> List.first("")
    |> String.upcase()
  end

  defp safe_div(numerator, denominator) do
    if Decimal.compare(denominator, Decimal.new("0")) == :eq do
      Decimal.new("0")
    else
      Decimal.div(numerator, denominator)
    end
  end
end
