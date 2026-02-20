defmodule Mix.Tasks.Import.FxRates do
  @moduledoc """
  Import FX rates from various IBKR CSV sources into the fx_rates table.

  ## Usage

      mix import.fx_rates              # Import from all sources
      mix import.fx_rates --flex       # Only Flex portfolio CSVs (data_archive/flex/)
      mix import.fx_rates --activity   # Only Activity Statement CSVs (csv_data/)

  ## Sources

  - **Flex portfolio CSVs** — `FXRateToBase` column, daily rates per currency (Jul 2025 - present)
  - **Activity Statement CSVs** — Mark-to-Market Forex + Base Currency Exchange Rate sections
  """

  use Mix.Task

  alias Dividendsomatic.Portfolio

  require Logger

  @shortdoc "Import FX rates from IBKR CSV sources"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Logger.configure(level: :info)

    {opts, _files, _} = OptionParser.parse(args, switches: [flex: :boolean, activity: :boolean])

    import_all = !opts[:flex] && !opts[:activity]

    total = 0
    total = if(import_all || opts[:flex], do: total + import_flex_rates(), else: total)
    total = if(import_all || opts[:activity], do: total + import_activity_rates(), else: total)

    Mix.shell().info("\nTotal FX rates upserted: #{total}")

    rate_count =
      Dividendsomatic.Repo.aggregate(Portfolio.FxRate, :count)

    Mix.shell().info("Total FX rates in database: #{rate_count}")
  end

  # Parse FXRateToBase from Flex portfolio CSVs in data_archive/flex/
  defp import_flex_rates do
    flex_files =
      (discover_files("data_archive/flex", "flex.490027.Portfolio*.csv") ++
         discover_files("data_archive/flex", "flex.490027.PortfolioForWww*.csv") ++
         discover_files("csv_data", "flex.490027.Portfolio*.csv"))
      |> Enum.uniq()
      |> Enum.sort()

    if flex_files == [] do
      Mix.shell().info("No Flex portfolio CSVs found")
      0
    else
      Mix.shell().info("Importing FX rates from #{length(flex_files)} Flex portfolio CSVs...")
      Enum.reduce(flex_files, 0, fn file, acc -> acc + parse_flex_fx_rates(file) end)
    end
  end

  defp parse_flex_fx_rates(file_path) do
    raw = File.read!(file_path) |> String.replace_prefix("\uFEFF", "")

    case String.split(raw, "\n", trim: true) do
      [header_line | data_lines] ->
        extract_flex_rates(parse_csv_line(header_line), data_lines)

      _ ->
        0
    end
  end

  defp extract_flex_rates(headers, data_lines) do
    date_idx = Enum.find_index(headers, &(&1 == "ReportDate"))
    currency_idx = Enum.find_index(headers, &(&1 == "CurrencyPrimary"))
    fx_idx = Enum.find_index(headers, &(&1 == "FXRateToBase"))

    if date_idx && currency_idx && fx_idx do
      data_lines
      |> Enum.map(&parse_csv_line/1)
      |> collect_unique_rates(date_idx, currency_idx, fx_idx)
      |> Enum.reduce(0, fn {{date, currency}, rate}, acc ->
        acc + upsert_rate(currency, date, rate, "flex_csv")
      end)
    else
      0
    end
  end

  defp collect_unique_rates(rows, date_idx, currency_idx, fx_idx) do
    Enum.reduce(rows, %{}, fn fields, acc ->
      date_str = Enum.at(fields, date_idx, "")
      currency = Enum.at(fields, currency_idx, "")
      rate_str = Enum.at(fields, fx_idx, "")

      with {:ok, date} <- Date.from_iso8601(date_str),
           {rate, _} <- Decimal.parse(rate_str),
           true <- currency not in ["", "EUR"] do
        Map.put_new(acc, {date, currency}, rate)
      else
        _ -> acc
      end
    end)
  end

  # Re-import Activity Statement FX rates (calls existing parser logic)
  defp import_activity_rates do
    files =
      discover_files("csv_data", "U7299935*.csv") ++
        discover_files("csv_data", "AllActions*.csv")

    if files == [] do
      Mix.shell().info("No Activity Statement CSVs found in csv_data/")
      0
    else
      Mix.shell().info("Importing FX rates from #{length(files)} Activity Statement CSVs...")
      Enum.reduce(files, 0, fn file, acc -> acc + parse_activity_fx_rates(file) end)
    end
  end

  defp parse_activity_fx_rates(file_path) do
    alias Dividendsomatic.Portfolio.IbkrActivityParser

    raw = File.read!(file_path) |> String.replace_prefix("\uFEFF", "")
    sections = IbkrActivityParser.split_sections(raw)

    m2m_count = import_m2m_forex(sections)
    bcr_count = import_base_currency(sections)
    total = m2m_count + bcr_count

    if total > 0 do
      Mix.shell().info(
        "  #{Path.basename(file_path)}: #{total} rates (#{m2m_count} M2M, #{bcr_count} BCR)"
      )
    end

    total
  end

  defp import_m2m_forex(sections) do
    rows = Map.get(sections, "Mark-to-Market Performance Summary", [])
    statement_rows = Map.get(sections, "Statement", [])

    forex_rows =
      Enum.filter(rows, fn row -> Enum.at(row, 0, "") |> String.trim() == "Forex" end)

    {start_date, end_date} = extract_period(statement_rows)

    if forex_rows == [] or start_date == nil or end_date == nil do
      0
    else
      Enum.reduce(forex_rows, 0, &upsert_m2m_row(&1, start_date, end_date, &2))
    end
  end

  defp upsert_m2m_row(row, start_date, end_date, acc) do
    currency = Enum.at(row, 1, "") |> String.trim()

    if currency in ["", "EUR"] do
      acc
    else
      prior_price = parse_decimal(Enum.at(row, 4, ""))
      current_price = parse_decimal(Enum.at(row, 5, ""))
      c1 = upsert_rate(currency, start_date, prior_price, "activity_statement")
      c2 = upsert_rate(currency, end_date, current_price, "activity_statement")
      acc + c1 + c2
    end
  end

  defp import_base_currency(sections) do
    rows = Map.get(sections, "Base Currency Exchange Rate", [])
    statement_rows = Map.get(sections, "Statement", [])
    date = extract_end_date(statement_rows)

    if rows == [] or date == nil do
      0
    else
      Enum.reduce(rows, 0, &upsert_bcr_row(&1, date, &2))
    end
  end

  defp upsert_bcr_row(row, date, acc) do
    currency = Enum.at(row, 0, "") |> String.trim()
    rate = parse_decimal(Enum.at(row, 1, ""))

    if currency in ["", "EUR"] or rate == nil do
      acc
    else
      acc + upsert_rate(currency, date, rate, "allactions")
    end
  end

  defp upsert_rate(_currency, _date, nil, _source), do: 0

  defp upsert_rate(currency, date, rate, source) do
    if Decimal.compare(rate, Decimal.new("0")) == :eq do
      0
    else
      case Portfolio.upsert_fx_rate(%{date: date, currency: currency, rate: rate, source: source}) do
        {:ok, _} -> 1
        {:error, _} -> 0
      end
    end
  end

  defp extract_period(statement_rows) do
    Enum.find_value(statement_rows, {nil, nil}, fn row ->
      if Enum.at(row, 0, "") == "Period" do
        parse_period_string(Enum.at(row, 1, ""))
      end
    end)
  end

  defp parse_period_string(period_str) do
    case String.split(period_str, " - ") do
      [start_part, end_part] ->
        {parse_ibkr_date(String.trim(start_part)), parse_ibkr_date(String.trim(end_part))}

      [single] ->
        date = parse_ibkr_date(String.trim(single))
        {date, date}

      _ ->
        {nil, nil}
    end
  end

  defp extract_end_date(statement_rows) do
    Enum.find_value(statement_rows, fn row ->
      if Enum.at(row, 0, "") == "Period" do
        {_, end_date} = parse_period_string(Enum.at(row, 1, ""))
        end_date
      end
    end)
  end

  defp parse_ibkr_date(str) do
    months = %{
      "january" => 1,
      "february" => 2,
      "march" => 3,
      "april" => 4,
      "may" => 5,
      "june" => 6,
      "july" => 7,
      "august" => 8,
      "september" => 9,
      "october" => 10,
      "november" => 11,
      "december" => 12
    }

    with [_, month_name, day_str, year_str] <-
           Regex.run(~r/(\w+)\s+(\d+),?\s+(\d{4})/, str),
         month when not is_nil(month) <- Map.get(months, String.downcase(month_name)),
         {day, _} <- Integer.parse(day_str),
         {year, _} <- Integer.parse(year_str),
         {:ok, date} <- Date.new(year, month, day) do
      date
    else
      _ -> nil
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil
  defp parse_decimal("--"), do: nil

  defp parse_decimal(str) when is_binary(str) do
    case str |> String.replace(",", "") |> Decimal.parse() do
      {decimal, _} -> decimal
      :error -> nil
    end
  end

  defp parse_csv_line(line) do
    line |> String.trim() |> parse_csv_fields([])
  end

  defp parse_csv_fields("", acc), do: Enum.reverse(acc)

  defp parse_csv_fields(<<"\"", rest::binary>>, acc) do
    {field, remaining} = extract_quoted_field(rest, "")
    parse_csv_fields(skip_comma(remaining), [field | acc])
  end

  defp parse_csv_fields(str, acc) do
    case String.split(str, ",", parts: 2) do
      [field] -> Enum.reverse([String.trim(field) | acc])
      [field, rest] -> parse_csv_fields(rest, [String.trim(field) | acc])
    end
  end

  defp extract_quoted_field(<<"\"\"", rest::binary>>, acc),
    do: extract_quoted_field(rest, acc <> "\"")

  defp extract_quoted_field(<<"\"", rest::binary>>, acc), do: {acc, rest}

  defp extract_quoted_field(<<c::utf8, rest::binary>>, acc),
    do: extract_quoted_field(rest, acc <> <<c::utf8>>)

  defp extract_quoted_field("", acc), do: {acc, ""}

  defp skip_comma(<<",", rest::binary>>), do: rest
  defp skip_comma(str), do: str

  defp discover_files(dir, pattern) do
    if File.dir?(dir) do
      Path.wildcard(Path.join(dir, pattern)) |> Enum.sort()
    else
      []
    end
  end
end
