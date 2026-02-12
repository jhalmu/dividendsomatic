defmodule Dividendsomatic.Portfolio.IbkrPdfParser do
  @moduledoc """
  Parser for IBKR Transaction History PDF exports.

  Uses `pdftotext -layout` to extract text, then parses the fixed-width layout.
  Each transaction spans multiple lines: context lines (description, ISIN, type
  fragments) wrap above and below the date line which contains numeric fields.

  Produces the same BrokerTransaction-compatible attribute maps as IbkrCsvParser.
  """

  require Logger

  alias Dividendsomatic.Portfolio.IbkrCsvParser

  # Matches date lines: "  2021-01-29       U***9935   ..."
  @date_regex ~r/^\s*(\d{4}-\d{2}-\d{2})\s+(U\S+)\s+(.*)/

  # Page headers to filter from context
  @page_header_regex ~r/Transaction History\s+Page:/

  # ISIN: 2 uppercase letters + 10 alphanumeric chars (may have spaces from line breaks)
  @isin_regex ~r/\(([A-Z]{2}[A-Z0-9]{10})\)/

  @doc """
  Parses an IBKR Transaction History PDF file from disk.

  Returns `{:ok, [transaction_map]}` or `{:error, reason}`.
  """
  def parse_file(path) do
    case System.cmd("pdftotext", ["-layout", path, "-"], stderr_to_stdout: true) do
      {text, 0} -> parse(text)
      {error, code} -> {:error, "pdftotext failed (exit #{code}): #{String.trim(error)}"}
    end
  rescue
    _e in ErlangError -> {:error, "pdftotext not found. Install poppler: brew install poppler"}
    e -> {:error, "Failed to run pdftotext: #{Exception.message(e)}"}
  end

  @doc """
  Parses IBKR PDF text content (output of pdftotext -layout).

  Returns `{:ok, [transaction_map]}` or `{:error, reason}`.
  """
  def parse(text) when is_binary(text) do
    lines = String.split(text, "\n")
    date_indices = find_date_indices(lines)

    if date_indices == [] do
      {:ok, []}
    else
      transactions = parse_records(lines, date_indices)
      {:ok, IbkrCsvParser.assign_external_ids(transactions)}
    end
  rescue
    e -> {:error, "Parse error: #{Exception.message(e)}"}
  end

  # Find line indices that contain transaction date lines
  defp find_date_indices(lines) do
    lines
    |> Enum.with_index()
    |> Enum.filter(fn {line, _} -> Regex.match?(@date_regex, line) end)
    |> Enum.map(fn {_, idx} -> idx end)
  end

  defp parse_records(lines, date_indices) do
    total = length(date_indices)
    total_lines = length(lines)

    date_indices
    |> Enum.with_index()
    |> Enum.map(fn {line_idx, i} ->
      prev_idx = if i > 0, do: Enum.at(date_indices, i - 1), else: -1
      next_idx = if i < total - 1, do: Enum.at(date_indices, i + 1), else: total_lines

      {before_ctx, after_ctx} = gather_context(lines, line_idx, prev_idx, next_idx)
      parse_transaction(Enum.at(lines, line_idx), before_ctx, after_ctx)
    end)
    |> Enum.filter(& &1)
  end

  # Gather context lines for a record, using midpoints to separate from neighbors
  defp gather_context(lines, line_idx, prev_idx, next_idx) do
    mid_before = div(prev_idx + line_idx, 2) + 1
    mid_after = div(line_idx + next_idx, 2)

    before_lines =
      if mid_before < line_idx do
        Enum.slice(lines, mid_before..(line_idx - 1))
      else
        []
      end

    after_lines =
      if line_idx + 1 <= mid_after do
        Enum.slice(lines, (line_idx + 1)..mid_after)
      else
        []
      end

    filter_fn = fn line ->
      trimmed = String.trim(line)
      trimmed != "" && !noise_line?(trimmed)
    end

    {
      before_lines |> Enum.filter(filter_fn) |> Enum.map(&String.trim/1),
      after_lines |> Enum.filter(filter_fn) |> Enum.map(&String.trim/1)
    }
  end

  defp parse_transaction(line, before_ctx, after_ctx) do
    case Regex.run(@date_regex, line) do
      [_, date_str, account, rest] ->
        tokens = String.split(rest)

        if length(tokens) < 8 do
          Logger.warning("IbkrPdfParser: skipping line with < 8 tokens: #{String.trim(line)}")
          nil
        else
          build_transaction(date_str, account, tokens, before_ctx, after_ctx)
        end

      _ ->
        nil
    end
  end

  defp build_transaction(date_str, account, tokens, before_ctx, after_ctx) do
    total = length(tokens)

    # Last 8 tokens are always: quantity, price, currency, gross, commission, net, multiplier, exchange_rate
    data_tokens = Enum.slice(tokens, (total - 8)..(total - 1))
    text_tokens = if total > 8, do: Enum.slice(tokens, 0..(total - 9)), else: []

    [quantity_s, price_s, currency_s, gross_s, commission_s, net_s, multiplier_s, exchange_rate_s] =
      data_tokens

    {symbol, desc_tokens} = extract_symbol(text_tokens)
    all_context = before_ctx ++ after_ctx
    all_text = Enum.join(desc_tokens ++ all_context, " ")

    raw_type = detect_raw_type(desc_tokens, all_text)

    # Fix PDF text interleaving: adjacent dividend + tax records have their text
    # columns merged. If detected as "Foreign Tax Withholding" but amount is positive,
    # reclassify as dividend/PIL (tax records always have negative amounts).
    net_amount = IbkrCsvParser.parse_decimal(clean_dash(net_s))

    raw_type =
      if raw_type == "Foreign Tax Withholding" && net_amount != nil &&
           Decimal.positive?(net_amount) do
        if payment_in_lieu?(all_text), do: "Payment in Lieu", else: "Dividend"
      else
        raw_type
      end

    quantity = IbkrCsvParser.parse_decimal(clean_dash(quantity_s))
    transaction_type = resolve_type(raw_type, quantity)

    isin = extract_isin(all_context)
    description = build_description(before_ctx, desc_tokens, after_ctx)

    %{
      broker: "ibkr",
      transaction_type: transaction_type,
      raw_type: raw_type,
      trade_date: parse_date(date_str),
      entry_date: parse_date(date_str),
      security_name: clean_dash(symbol),
      isin: isin,
      quantity: quantity,
      price: IbkrCsvParser.parse_decimal(clean_dash(price_s)),
      currency: clean_dash(currency_s),
      amount: net_amount,
      commission: IbkrCsvParser.parse_decimal(clean_dash(commission_s)),
      exchange_rate: IbkrCsvParser.parse_decimal(clean_dash(exchange_rate_s)),
      description: description,
      raw_data: %{
        "account" => account,
        "symbol" => clean_dash(symbol),
        "gross_amount" => clean_dash(gross_s),
        "multiplier" => clean_dash(multiplier_s)
      }
    }
  end

  # Extract symbol from the end of text tokens.
  # Handles multi-word symbols like "PBR A" or "BRK B".
  defp extract_symbol([]), do: {"-", []}

  defp extract_symbol(tokens) do
    last = List.last(tokens)
    rest = Enum.drop(tokens, -1)

    # Multi-word symbol: single uppercase letter preceded by uppercase alphanumeric token
    if String.length(last) == 1 && String.match?(last, ~r/^[A-Z]$/) && rest != [] do
      second_last = List.last(rest)

      if String.match?(second_last, ~r/^[A-Z][A-Z0-9.]*$/) do
        symbol = second_last <> " " <> last
        {symbol, Enum.drop(rest, -1)}
      else
        {last, rest}
      end
    else
      {last, rest}
    end
  end

  # Two-pass type detection to avoid context bleed between neighboring records.
  # Pass 1: Check date-line text tokens (highest confidence - the type keyword is on the date line).
  # Pass 2: Check all context for types that wrap across lines (Foreign Tax, PIL, Forex).
  defp detect_raw_type(text_tokens, all_text) do
    detect_from_date_line(text_tokens) || detect_from_context(all_text, text_tokens)
  end

  # Pass 1: Keywords found directly on the date line
  # Split into two functions to reduce cyclomatic complexity.
  defp detect_from_date_line(text_tokens) do
    text = Enum.join(text_tokens, " ")
    detect_multiword_type(text) || detect_single_keyword(text_tokens)
  end

  defp detect_multiword_type(text) do
    cond do
      String.contains?(text, "Debit Interest") -> "Debit Interest"
      String.contains?(text, "Other Fee") -> "Other Fee"
      String.contains?(text, "Sales Tax") -> "Sales Tax"
      String.contains?(text, "Transaction Fee") -> "Transaction Fee"
      true -> nil
    end
  end

  defp detect_single_keyword(text_tokens) do
    cond do
      "Buy" in text_tokens -> "Buy"
      "Sell" in text_tokens -> "Sell"
      "Dividend" in text_tokens -> "Dividend"
      "Deposit" in text_tokens -> "Deposit"
      "Withdrawal" in text_tokens -> "Withdrawal"
      "Adjustment" in text_tokens -> "Adjustment"
      true -> nil
    end
  end

  # Pass 2: Fallback to context when type isn't on the date line.
  # Split into specific-type and general-type checks to reduce cyclomatic complexity.
  defp detect_from_context(all_text, text_tokens) do
    detect_specific_context_type(all_text) || detect_general_context_type(all_text, text_tokens)
  end

  defp detect_specific_context_type(all_text) do
    cond do
      String.contains?(all_text, "Withholding") ->
        "Foreign Tax Withholding"

      payment_in_lieu?(all_text) ->
        "Payment in Lieu"

      String.contains?(all_text, "Forex Trade") || String.contains?(all_text, "Forex") ->
        "Forex Trade Component"

      String.contains?(all_text, "Debit Interest") ->
        "Debit Interest"

      Regex.match?(~r/\bBuy\b/, all_text) ->
        "Buy"

      Regex.match?(~r/\bSell\b/, all_text) ->
        "Sell"

      true ->
        nil
    end
  end

  defp detect_general_context_type(all_text, text_tokens) do
    cond do
      String.contains?(all_text, "Dividend") ->
        "Dividend"

      String.contains?(all_text, "Deposit") ->
        "Deposit"

      String.contains?(all_text, "Withdrawal") ->
        "Withdrawal"

      String.contains?(all_text, "Adjustment") || String.contains?(all_text, "Corporate") ||
          String.contains?(all_text, "Subscribes") ->
        "Adjustment"

      String.contains?(all_text, "Trade Charge") ->
        "Transaction Fee"

      true ->
        Logger.warning("IbkrPdfParser: unknown type, text_tokens=#{inspect(text_tokens)}")
        "Unknown"
    end
  end

  defp payment_in_lieu?(text) do
    String.contains?(text, "Payment") && String.contains?(text, "Lieu")
  end

  defp resolve_type("Forex Trade Component", quantity) do
    case quantity do
      nil -> "fx_buy"
      qty -> if Decimal.negative?(qty), do: "fx_sell", else: "fx_buy"
    end
  end

  defp resolve_type(raw_type, _quantity), do: IbkrCsvParser.normalize_type(raw_type)

  # Extract ISIN from context lines, handling line-break splits.
  # ISINs appear in parentheses like "(US04010L1035)" but may be split:
  # "CIBUS(SE001\n0832204)" → needs space removal within parens.
  defp extract_isin([]), do: nil

  defp extract_isin(context) do
    text = Enum.join(context, " ")

    # Try direct match first
    case Regex.run(@isin_regex, text) do
      [_, isin] ->
        isin

      _ ->
        # Remove spaces within parenthesized text and retry
        compressed =
          Regex.replace(~r/\(([^)]{10,16})\)/, text, fn _, inner ->
            "(#{String.replace(inner, ~r/\s/, "")})"
          end)

        case Regex.run(@isin_regex, compressed) do
          [_, isin] -> isin
          _ -> nil
        end
    end
  end

  # Build description from context and date line text tokens, capped at 255 chars
  defp build_description(before_ctx, desc_tokens, after_ctx) do
    parts = before_ctx ++ desc_tokens ++ after_ctx

    case parts do
      [] -> nil
      _ -> parts |> Enum.join(" ") |> String.slice(0, 255)
    end
  end

  # Filter noise lines from context: page headers, column headers, section headers
  defp noise_line?(line) do
    Regex.match?(@page_header_regex, line) ||
      String.starts_with?(line, "Transactions") ||
      String.starts_with?(line, "Summary") ||
      String.starts_with?(line, "Starting Cash") ||
      String.starts_with?(line, "Ending Cash") ||
      Regex.match?(~r/^Date\s+Account\s+Description/, line) ||
      Regex.match?(~r/^Type$/, line) ||
      Regex.match?(~r/^EUR$/, line)
  end

  defp clean_dash("-"), do: nil
  defp clean_dash(val), do: val

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
