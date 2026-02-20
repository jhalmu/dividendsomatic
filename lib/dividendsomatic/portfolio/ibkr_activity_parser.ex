defmodule Dividendsomatic.Portfolio.IbkrActivityParser do
  @moduledoc """
  Parses IBKR Activity Statement CSV files into structured data for clean tables.

  Each CSV file contains multiple sections (Trades, Dividends, etc.) identified
  by the first column. Rows are either Header, Data, or Total rows (second column).

  Import order: Financial Instrument Information first (builds instruments table),
  then everything else resolves instrument_id via the instruments table.
  """

  alias Dividendsomatic.Repo

  alias Dividendsomatic.Portfolio

  alias Dividendsomatic.Portfolio.{
    CashFlow,
    CorporateAction,
    DividendPayment,
    Instrument,
    InstrumentAlias,
    MarginEquitySnapshot,
    Trade
  }

  import Ecto.Query
  require Logger

  # --- Public API ---

  @doc """
  Imports all files in two passes:
  1. Extract instruments from ALL files first
  2. Import trades, dividends, cash flows from all files

  This ensures instruments exist before any trades/dividends reference them.
  """
  def import_all(file_paths) do
    Logger.info("Pass 1: Importing instruments from #{length(file_paths)} files...")

    parsed_files =
      Enum.map(file_paths, fn path ->
        {sections, is_consolidated} = parse_file(path)
        {path, sections, is_consolidated}
      end)

    # Pass 1: Import instruments from all files
    Enum.each(parsed_files, fn {path, sections, is_consolidated} ->
      Logger.info("  Instruments from #{Path.basename(path)}")
      import_instruments(sections, is_consolidated)
    end)

    Logger.info("Pass 2: Importing transactions from #{length(file_paths)} files...")

    # Pass 2: Import everything else
    Enum.map(parsed_files, fn {path, sections, is_consolidated} ->
      Logger.info("--- #{Path.basename(path)} ---")
      import_transactions(path, sections, is_consolidated)
    end)
  end

  @doc """
  Parses an IBKR Activity Statement CSV file and imports all sections.
  Returns a summary map of what was imported.
  """
  def import_file(file_path) do
    {sections, is_consolidated} = parse_file(file_path)
    import_instruments(sections, is_consolidated)
    import_transactions(file_path, sections, is_consolidated)
  end

  defp parse_file(file_path) do
    raw = File.read!(file_path)
    raw = String.replace_prefix(raw, "\uFEFF", "")
    sections = split_sections(raw)
    is_consolidated = consolidated?(sections)

    if is_consolidated do
      Logger.info("  Detected consolidated format: #{Path.basename(file_path)}")
    end

    {sections, is_consolidated}
  end

  defp import_transactions(file_path, sections, is_consolidated) do
    trade_result = import_trades(sections, is_consolidated)
    dividend_result = import_dividends(sections, is_consolidated)
    cash_flow_result = import_cash_flows(sections, is_consolidated)
    interest_result = import_interest(sections, is_consolidated)
    fee_result = import_fees(sections)
    corporate_action_result = import_corporate_actions(sections, is_consolidated)
    nav_result = import_nav_snapshot(sections)
    borrow_fee_result = import_borrow_fees(sections, is_consolidated)
    fx_result = import_fx_rates(sections)

    %{
      file: Path.basename(file_path),
      trades: trade_result,
      dividends: dividend_result,
      cash_flows: cash_flow_result,
      interest: interest_result,
      fees: fee_result,
      corporate_actions: corporate_action_result,
      nav: nav_result,
      borrow_fees: borrow_fee_result,
      fx_rates: fx_result
    }
  end

  # --- Section Splitting ---

  @doc """
  Splits raw CSV text into a map of section_name => list of parsed CSV rows.
  Only includes "Data" rows (skips Header and Total rows).
  """
  def split_sections(raw_text) do
    raw_text
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      line = String.trim(line)

      case parse_csv_line(line) do
        [section, "Data" | rest] when section != "" ->
          Map.update(acc, section, [rest], &(&1 ++ [rest]))

        _ ->
          acc
      end
    end)
  end

  @doc """
  Parses a single CSV line, respecting quoted fields with commas.
  """
  def parse_csv_line(line) do
    line
    |> String.trim()
    |> do_parse_csv([], "", false)
    |> Enum.reverse()
    |> Enum.map(&String.trim/1)
  end

  defp do_parse_csv("", acc, current, _in_quote) do
    [current | acc]
  end

  defp do_parse_csv(<<"\"\"", rest::binary>>, acc, current, true) do
    do_parse_csv(rest, acc, current <> "\"", true)
  end

  defp do_parse_csv(<<"\"", rest::binary>>, acc, current, false) do
    do_parse_csv(rest, acc, current, true)
  end

  defp do_parse_csv(<<"\"", rest::binary>>, acc, current, true) do
    do_parse_csv(rest, acc, current, false)
  end

  defp do_parse_csv(<<",", rest::binary>>, acc, current, false) do
    do_parse_csv(rest, [current | acc], "", false)
  end

  defp do_parse_csv(<<char::utf8, rest::binary>>, acc, current, in_quote) do
    do_parse_csv(rest, acc, current <> <<char::utf8>>, in_quote)
  end

  # --- Consolidated Detection ---

  defp consolidated?(sections) do
    case Map.get(sections, "Dividends") do
      [first_row | _] ->
        # Consolidated has Account column: [Currency, Account, Date, Description, Amount]
        # Standard has: [Currency, Date, Description, Amount]
        # Check if 3rd field looks like a date (standard) or not (consolidated with Account)
        length(first_row) >= 5 and not date_like?(Enum.at(first_row, 1))

      _ ->
        # Fall back to checking Trades header
        case Map.get(sections, "Trades") do
          [first_row | _] -> length(first_row) >= 16
          _ -> false
        end
    end
  end

  defp date_like?(str) when is_binary(str) do
    String.match?(str, ~r/^\d{4}-\d{2}-\d{2}/)
  end

  defp date_like?(_), do: false

  # --- Financial Instrument Information ---

  defp import_instruments(sections, _is_consolidated) do
    rows = Map.get(sections, "Financial Instrument Information", [])

    results =
      Enum.map(rows, fn row ->
        # Columns: Asset Category, Symbol, Description, Conid, Security ID,
        # Underlying, Listing Exch, Multiplier, Type, Code
        # Note: consolidated file does NOT add Account column here
        parse_instrument_row(row)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.isin)

    {inserted, updated, errors} =
      Enum.reduce(results, {0, 0, []}, fn attrs, {ins, upd, errs} ->
        case upsert_instrument(attrs) do
          {:ok, :inserted} -> {ins + 1, upd, errs}
          {:ok, :updated} -> {ins, upd + 1, errs}
          {:error, reason} -> {ins, upd, [reason | errs]}
        end
      end)

    Logger.info("  Instruments: #{inserted} new, #{updated} updated, #{length(errors)} errors")
    %{inserted: inserted, updated: updated, errors: errors}
  end

  defp parse_instrument_row(row) when length(row) >= 5 do
    [asset_category, symbol, description, conid_str, security_id | rest] = row
    underlying = Enum.at(rest, 0, "")
    listing_exchange = Enum.at(rest, 1, "")
    multiplier_str = Enum.at(rest, 2, "1")
    type = Enum.at(rest, 3, "")

    # Skip Total/SubTotal rows
    if asset_category == "Total" or asset_category == "" do
      nil
    else
      isin = normalize_security_id(security_id)

      if isin && isin != "" do
        %{
          isin: isin,
          conid: parse_integer(conid_str),
          name: description,
          asset_category: asset_category,
          listing_exchange: listing_exchange,
          multiplier: parse_decimal(multiplier_str),
          type: type,
          metadata: %{
            "underlying" => underlying,
            "symbol" => symbol
          }
        }
      else
        Logger.warning("  Skipping instrument without Security ID: #{symbol} (#{description})")
        nil
      end
    end
  end

  defp parse_instrument_row(_row), do: nil

  defp normalize_security_id(id) when is_binary(id) do
    trimmed = String.trim(id)
    if trimmed == "" or trimmed == "--", do: nil, else: trimmed
  end

  defp normalize_security_id(_), do: nil

  defp upsert_instrument(attrs) do
    case Repo.get_by(Instrument, isin: attrs.isin) do
      nil ->
        %Instrument{}
        |> Instrument.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, instrument} ->
            # Create alias for the symbol
            create_alias(instrument, attrs)
            {:ok, :inserted}

          {:error, changeset} ->
            {:error, {:insert_failed, attrs.isin, changeset}}
        end

      existing ->
        existing
        |> Instrument.changeset(Map.drop(attrs, [:isin]))
        |> Repo.update()
        |> case do
          {:ok, instrument} ->
            create_alias(instrument, attrs)
            {:ok, :updated}

          {:error, changeset} ->
            {:error, {:update_failed, attrs.isin, changeset}}
        end
    end
  end

  defp create_alias(instrument, attrs) do
    symbol = get_in(attrs, [:metadata, "symbol"]) || ""
    exchange = attrs[:listing_exchange] || ""

    if symbol != "" do
      alias_attrs = %{
        instrument_id: instrument.id,
        symbol: symbol,
        exchange: exchange,
        source: "ibkr_activity_statement"
      }

      # Upsert: only create if not exists
      case Repo.get_by(InstrumentAlias,
             instrument_id: instrument.id,
             symbol: symbol,
             exchange: exchange
           ) do
        nil ->
          %InstrumentAlias{}
          |> InstrumentAlias.changeset(alias_attrs)
          |> Repo.insert()

        _existing ->
          :ok
      end
    end
  end

  # --- Trades ---

  defp import_trades(sections, is_consolidated) do
    rows = Map.get(sections, "Trades", [])

    # Determine which row types to import:
    # If file has "Trade" rows, use those (individual fills).
    # If file only has "Order" rows (consolidated), use Orders instead.
    has_trade_rows = Enum.any?(rows, fn row -> Enum.at(row, 0) == "Trade" end)
    accepted_types = if has_trade_rows, do: ["Trade", "ClosedLot"], else: ["Order"]

    results =
      rows
      |> Enum.map(&parse_trade_row(&1, is_consolidated, accepted_types))
      |> Enum.reject(&is_nil/1)

    {inserted, skipped, errors} =
      Enum.reduce(results, {0, 0, []}, fn attrs, {ins, skip, errs} ->
        case insert_if_new(Trade, attrs) do
          {:ok, :inserted} -> {ins + 1, skip, errs}
          {:ok, :skipped} -> {ins, skip + 1, errs}
          {:error, reason} -> {ins, skip, [reason | errs]}
        end
      end)

    Logger.info("  Trades: #{inserted} new, #{skipped} skipped, #{length(errors)} errors")
    %{inserted: inserted, skipped: skipped, errors: errors}
  end

  defp parse_trade_row(row, is_consolidated, accepted_types) do
    {data_disc, asset_category, currency, symbol, datetime_str, exchange, quantity_str, price_str,
     _close_price, proceeds_str, commission_str, _basis, _realized, _mtm, _code} =
      if is_consolidated do
        extract_trade_consolidated(row)
      else
        extract_trade_standard(row)
      end

    skip? =
      data_disc not in accepted_types or
        asset_category in ["", "Total", "Forex"]

    if skip? do
      nil
    else
      build_trade_attrs(%{
        row: row,
        symbol: symbol,
        currency: currency,
        datetime_str: datetime_str,
        exchange: exchange,
        quantity_str: quantity_str,
        price_str: price_str,
        proceeds_str: proceeds_str,
        commission_str: commission_str,
        asset_category: asset_category
      })
    end
  end

  defp build_trade_attrs(parsed) do
    case resolve_instrument_by_symbol(parsed.symbol, parsed.currency) do
      nil ->
        Logger.warning(
          "  Trade: no instrument for symbol=#{parsed.symbol}, currency=#{parsed.currency}"
        )

        nil

      instrument_id ->
        {trade_date, trade_time} = parse_datetime(parsed.datetime_str)
        quantity = parse_decimal(parsed.quantity_str)
        price = parse_decimal(parsed.price_str)
        amount = parse_decimal(parsed.proceeds_str)
        commission = parse_decimal(parsed.commission_str)
        external_id = trade_external_id(instrument_id, trade_date, quantity, price, amount)

        %{
          external_id: external_id,
          instrument_id: instrument_id,
          trade_date: trade_date,
          trade_time: trade_time,
          quantity: quantity,
          price: price,
          amount: amount,
          commission: commission,
          currency: parsed.currency,
          asset_category: parsed.asset_category,
          exchange: parsed.exchange,
          description: "#{parsed.symbol} #{parsed.asset_category}",
          raw_data: %{"row" => parsed.row}
        }
    end
  end

  defp extract_trade_standard(row) do
    data_disc = Enum.at(row, 0, "")
    asset_category = Enum.at(row, 1, "")
    currency = Enum.at(row, 2, "")
    symbol = Enum.at(row, 3, "")
    datetime_str = Enum.at(row, 4, "")
    exchange = Enum.at(row, 5, "")
    quantity_str = Enum.at(row, 6, "")
    price_str = Enum.at(row, 7, "")
    close_price = Enum.at(row, 8, "")
    proceeds_str = Enum.at(row, 9, "")
    commission_str = Enum.at(row, 10, "")
    basis = Enum.at(row, 11, "")
    realized = Enum.at(row, 12, "")
    mtm = Enum.at(row, 13, "")
    code = Enum.at(row, 14, "")

    {data_disc, asset_category, currency, symbol, datetime_str, exchange, quantity_str, price_str,
     close_price, proceeds_str, commission_str, basis, realized, mtm, code}
  end

  defp extract_trade_consolidated(row) do
    data_disc = Enum.at(row, 0, "")
    asset_category = Enum.at(row, 1, "")
    currency = Enum.at(row, 2, "")
    # Skip Account column at position 3
    symbol = Enum.at(row, 4, "")
    datetime_str = Enum.at(row, 5, "")
    # No Exchange column in consolidated
    quantity_str = Enum.at(row, 6, "")
    price_str = Enum.at(row, 7, "")
    close_price = Enum.at(row, 8, "")
    proceeds_str = Enum.at(row, 9, "")
    commission_str = Enum.at(row, 10, "")
    basis = Enum.at(row, 11, "")
    realized = Enum.at(row, 12, "")
    mtm = Enum.at(row, 13, "")
    code = Enum.at(row, 14, "")

    {data_disc, asset_category, currency, symbol, datetime_str, "", quantity_str, price_str,
     close_price, proceeds_str, commission_str, basis, realized, mtm, code}
  end

  # --- Dividends + Withholding Tax Pairing ---

  defp import_dividends(sections, is_consolidated) do
    div_rows = Map.get(sections, "Dividends", [])
    pil_rows = Map.get(sections, "Payment In Lieu Of Dividends", [])
    wht_rows = Map.get(sections, "Withholding Tax", [])

    # Parse dividend rows
    dividends =
      (div_rows ++ pil_rows)
      |> Enum.map(&parse_dividend_row(&1, is_consolidated))
      |> Enum.reject(&is_nil/1)

    # Parse WHT rows and index by matching key (isin + date)
    wht_map =
      wht_rows
      |> Enum.map(&parse_wht_row(&1, is_consolidated))
      |> Enum.reject(&is_nil/1)
      |> Enum.group_by(& &1.match_key)

    # Pair dividends with WHT
    paired =
      Enum.map(dividends, fn div ->
        wht_entries = Map.get(wht_map, div.match_key, [])

        wht_amount =
          Enum.reduce(wht_entries, Decimal.new("0"), fn w, acc ->
            Decimal.add(acc, w.amount)
          end)

        gross = div.amount
        net = Decimal.add(gross, wht_amount)

        %{
          instrument_id: div.instrument_id,
          pay_date: div.date,
          gross_amount: gross,
          withholding_tax: wht_amount,
          net_amount: net,
          currency: div.currency,
          per_share: div.per_share,
          description: div.description,
          external_id: dividend_external_id(div.instrument_id, div.date, gross, div.currency),
          raw_data: %{
            "dividend_row" => div.raw_row,
            "wht_rows" => Enum.map(wht_entries, & &1.raw_row)
          }
        }
      end)

    {inserted, skipped, errors} =
      Enum.reduce(paired, {0, 0, []}, fn attrs, {ins, skip, errs} ->
        case insert_if_new(DividendPayment, attrs) do
          {:ok, :inserted} -> {ins + 1, skip, errs}
          {:ok, :skipped} -> {ins, skip + 1, errs}
          {:error, reason} -> {ins, skip, [reason | errs]}
        end
      end)

    Logger.info("  Dividends: #{inserted} new, #{skipped} skipped, #{length(errors)} errors")
    %{inserted: inserted, skipped: skipped, errors: errors}
  end

  defp parse_dividend_row(row, is_consolidated) do
    # Standard: Currency, Date, Description, Amount
    # Consolidated: Currency, Account, Date, Description, Amount
    {currency, date_str, description, amount_str} =
      if is_consolidated do
        {Enum.at(row, 0, ""), Enum.at(row, 2, ""), Enum.at(row, 3, ""), Enum.at(row, 4, "")}
      else
        {Enum.at(row, 0, ""), Enum.at(row, 1, ""), Enum.at(row, 2, ""), Enum.at(row, 3, "")}
      end

    # Skip Total rows
    if currency == "Total" or currency == "" or date_str == "" do
      nil
    else
      {isin, per_share} = extract_isin_and_per_share(description)

      case resolve_instrument_by_isin(isin) do
        nil ->
          Logger.warning("  Dividend: no instrument for ISIN=#{isin}, desc=#{description}")
          nil

        instrument_id ->
          date = parse_date(date_str)
          amount = parse_decimal(amount_str)

          %{
            instrument_id: instrument_id,
            date: date,
            currency: currency,
            amount: amount,
            per_share: per_share,
            description: description,
            match_key: {instrument_id, date, currency},
            raw_row: row
          }
      end
    end
  end

  defp parse_wht_row(row, is_consolidated) do
    # Same structure as dividends (with extra Code column at end)
    {currency, date_str, description, amount_str} =
      if is_consolidated do
        {Enum.at(row, 0, ""), Enum.at(row, 2, ""), Enum.at(row, 3, ""), Enum.at(row, 4, "")}
      else
        {Enum.at(row, 0, ""), Enum.at(row, 1, ""), Enum.at(row, 2, ""), Enum.at(row, 3, "")}
      end

    if currency == "Total" or currency == "" or date_str == "" do
      nil
    else
      {isin, _per_share} = extract_isin_and_per_share(description)

      case resolve_instrument_by_isin(isin) do
        nil ->
          Logger.warning("  WHT: no instrument for ISIN=#{isin}, desc=#{description}")
          nil

        instrument_id ->
          date = parse_date(date_str)
          amount = parse_decimal(amount_str)

          %{
            instrument_id: instrument_id,
            date: date,
            currency: currency,
            amount: amount,
            match_key: {instrument_id, date, currency},
            raw_row: row
          }
      end
    end
  end

  @doc """
  Extracts ISIN and per-share amount from IBKR dividend description.
  Example: "KESKOB(FI0009000202) Cash Dividend EUR 0.22 per Share (Ordinary Dividend)"
  Returns: {"FI0009000202", Decimal.new("0.22")}
  """
  def extract_isin_and_per_share(description) do
    # Extract ISIN from parentheses: SYMBOL(ISIN)
    isin =
      case Regex.run(~r/\(([A-Z0-9]{12})\)/, description) do
        [_, isin] -> isin
        _ -> nil
      end

    # Extract per-share amount: "EUR 0.22 per Share" or "CAD 0.835"
    per_share =
      case Regex.run(
             ~r/(?:Cash Dividend|Payment in Lieu of Dividend)[^0-9]*([0-9]+\.?[0-9]*)/,
             description
           ) do
        [_, amount_str] -> parse_decimal(amount_str)
        _ -> nil
      end

    {isin, per_share}
  end

  # --- Cash Flows (Deposits & Withdrawals) ---

  defp import_cash_flows(sections, is_consolidated) do
    rows = Map.get(sections, "Deposits & Withdrawals", [])

    results =
      rows
      |> Enum.map(&parse_cash_flow_row(&1, is_consolidated))
      |> Enum.reject(&is_nil/1)

    {inserted, skipped, errors} =
      Enum.reduce(results, {0, 0, []}, fn attrs, {ins, skip, errs} ->
        case insert_if_new(CashFlow, attrs) do
          {:ok, :inserted} -> {ins + 1, skip, errs}
          {:ok, :skipped} -> {ins, skip + 1, errs}
          {:error, reason} -> {ins, skip, [reason | errs]}
        end
      end)

    Logger.info("  Cash flows: #{inserted} new, #{skipped} skipped, #{length(errors)} errors")
    %{inserted: inserted, skipped: skipped, errors: errors}
  end

  defp parse_cash_flow_row(row, is_consolidated) do
    {currency, date_str, description, amount_str} =
      if is_consolidated do
        {Enum.at(row, 0, ""), Enum.at(row, 2, ""), Enum.at(row, 3, ""), Enum.at(row, 4, "")}
      else
        {Enum.at(row, 0, ""), Enum.at(row, 1, ""), Enum.at(row, 2, ""), Enum.at(row, 3, "")}
      end

    date = parse_date(date_str)
    amount = parse_decimal(amount_str)

    skip? =
      currency in ["Total", "Total in EUR", ""] or
        date_str == "" or date == nil or amount == nil

    if skip? do
      nil
    else
      flow_type =
        if Decimal.compare(amount, Decimal.new("0")) == :gt, do: "deposit", else: "withdrawal"

      external_id = cash_flow_external_id(flow_type, date, amount, currency, description)

      %{
        external_id: external_id,
        flow_type: flow_type,
        date: date,
        amount: amount,
        currency: currency,
        description: description,
        raw_data: %{"row" => row}
      }
    end
  end

  # --- Interest ---

  defp import_interest(sections, is_consolidated) do
    rows =
      Map.get(sections, "Interest", []) ++
        Map.get(sections, "Broker Interest Paid", []) ++
        Map.get(sections, "Broker Interest Received", [])

    results =
      rows
      |> Enum.map(&parse_interest_row(&1, is_consolidated))
      |> Enum.reject(&is_nil/1)

    {inserted, skipped, errors} =
      Enum.reduce(results, {0, 0, []}, fn attrs, {ins, skip, errs} ->
        case insert_if_new(CashFlow, attrs) do
          {:ok, :inserted} -> {ins + 1, skip, errs}
          {:ok, :skipped} -> {ins, skip + 1, errs}
          {:error, reason} -> {ins, skip, [reason | errs]}
        end
      end)

    Logger.info("  Interest: #{inserted} new, #{skipped} skipped, #{length(errors)} errors")
    %{inserted: inserted, skipped: skipped, errors: errors}
  end

  defp parse_interest_row(row, is_consolidated) do
    # Standard: Currency, Date, Description, Amount
    # Consolidated: Currency, Account, Date, Description, Amount
    {currency, date_str, description, amount_str} =
      if is_consolidated do
        {Enum.at(row, 0, ""), Enum.at(row, 2, ""), Enum.at(row, 3, ""), Enum.at(row, 4, "")}
      else
        {Enum.at(row, 0, ""), Enum.at(row, 1, ""), Enum.at(row, 2, ""), Enum.at(row, 3, "")}
      end

    if currency in ["Total", "Total in EUR", ""] or date_str == "" or not date_like?(date_str) do
      nil
    else
      date = parse_date(date_str)
      amount = parse_decimal(amount_str)

      if amount == nil or date == nil do
        nil
      else
        external_id = cash_flow_external_id("interest", date, amount, currency, description)

        %{
          external_id: external_id,
          flow_type: "interest",
          date: date,
          amount: amount,
          currency: currency,
          description: description,
          raw_data: %{"row" => row}
        }
      end
    end
  end

  # --- Fees ---

  defp import_fees(sections) do
    rows =
      Map.get(sections, "Fees", []) ++
        Map.get(sections, "Other Fees", []) ++
        Map.get(sections, "Transaction Fees", []) ++
        Map.get(sections, "Sales Tax Details", [])

    results =
      rows
      |> Enum.map(&parse_fee_row/1)
      |> Enum.reject(&is_nil/1)

    {inserted, skipped, errors} =
      Enum.reduce(results, {0, 0, []}, fn attrs, {ins, skip, errs} ->
        case insert_if_new(CashFlow, attrs) do
          {:ok, :inserted} -> {ins + 1, skip, errs}
          {:ok, :skipped} -> {ins, skip + 1, errs}
          {:error, reason} -> {ins, skip, [reason | errs]}
        end
      end)

    Logger.info("  Fees: #{inserted} new, #{skipped} skipped, #{length(errors)} errors")
    %{inserted: inserted, skipped: skipped, errors: errors}
  end

  defp parse_fee_row(row) do
    # Fee sections have varying column layouts. Find currency, date, description, amount.
    # Common patterns:
    # Other Fees: Subtitle, Currency, Date, Description, Amount (but section name already stripped)
    # So after section+Data stripped: [Subtitle, Currency, Date, Description, Amount]
    # OR: [Currency, Date, Description, Amount]
    # Transaction Fees: Asset Category, Currency, Date/Time, Symbol, Description, Quantity, Trade Price, Amount, Code
    {currency, date_str, description, amount_str} = extract_fee_fields(row)

    if currency in ["Total", "Total in EUR", ""] or date_str == "" do
      nil
    else
      date = parse_date(date_str)
      amount = parse_decimal(amount_str)

      if amount == nil or date == nil do
        nil
      else
        external_id = cash_flow_external_id("fee", date, amount, currency, description)

        %{
          external_id: external_id,
          flow_type: "fee",
          date: date,
          amount: amount,
          currency: currency,
          description: description,
          raw_data: %{"row" => row}
        }
      end
    end
  end

  # Detect fee format by finding the date column position
  defp extract_fee_fields(row) when length(row) >= 8 and length(row) > 4 do
    case {date_like?(Enum.at(row, 1)), date_like?(Enum.at(row, 2))} do
      # Transaction Fees: Asset Category, Currency, Date/Time, Symbol, Description, ..., Amount
      {false, true} ->
        {Enum.at(row, 1, ""), Enum.at(row, 2, ""), Enum.at(row, 4, ""), Enum.at(row, 7, "")}

      # Sales Tax: Currency, Date, Description, ..., Sales Tax
      {true, _} ->
        {Enum.at(row, 0, ""), Enum.at(row, 1, ""), Enum.at(row, 2, ""), Enum.at(row, 7, "")}

      _ ->
        {"", "", "", ""}
    end
  end

  defp extract_fee_fields(row) when length(row) >= 4 do
    case {date_like?(Enum.at(row, 1)), date_like?(Enum.at(row, 2))} do
      # Other Fees: Subtitle, Currency, Date, Description, Amount
      {false, true} ->
        {Enum.at(row, 1, ""), Enum.at(row, 2, ""), Enum.at(row, 3, ""), Enum.at(row, 4, "")}

      # Simple: Currency, Date, Description, Amount
      {true, _} ->
        {Enum.at(row, 0, ""), Enum.at(row, 1, ""), Enum.at(row, 2, ""), Enum.at(row, 3, "")}

      _ ->
        {"", "", "", ""}
    end
  end

  defp extract_fee_fields(_row), do: {"", "", "", ""}

  # --- Corporate Actions ---

  defp import_corporate_actions(sections, is_consolidated) do
    rows = Map.get(sections, "Corporate Actions", [])

    results =
      rows
      |> Enum.map(&parse_corporate_action_row(&1, is_consolidated))
      |> Enum.reject(&is_nil/1)

    {inserted, skipped, errors} =
      Enum.reduce(results, {0, 0, []}, fn attrs, {ins, skip, errs} ->
        case insert_corporate_action(attrs) do
          {:ok, :inserted} -> {ins + 1, skip, errs}
          {:ok, :skipped} -> {ins, skip + 1, errs}
          {:error, reason} -> {ins, skip, [reason | errs]}
        end
      end)

    Logger.info(
      "  Corporate actions: #{inserted} new, #{skipped} skipped, #{length(errors)} errors"
    )

    %{inserted: inserted, skipped: skipped, errors: errors}
  end

  defp parse_corporate_action_row(row, is_consolidated) do
    # After section+Data stripped:
    # Standard: [AssetCategory, Currency, ReportDate, DateTime, Description, Quantity, Proceeds, Value, RealizedP/L, Code]
    # Consolidated adds Account column after Currency
    {asset_category, currency, report_date_str, _datetime_str, description, quantity_str,
     proceeds_str, value_str} =
      if is_consolidated do
        {Enum.at(row, 0, ""), Enum.at(row, 1, ""), Enum.at(row, 3, ""), Enum.at(row, 4, ""),
         Enum.at(row, 5, ""), Enum.at(row, 6, ""), Enum.at(row, 7, ""), Enum.at(row, 8, "")}
      else
        {Enum.at(row, 0, ""), Enum.at(row, 1, ""), Enum.at(row, 2, ""), Enum.at(row, 3, ""),
         Enum.at(row, 4, ""), Enum.at(row, 5, ""), Enum.at(row, 6, ""), Enum.at(row, 7, "")}
      end

    # Skip Total rows and Closed Lot rows
    skip? =
      asset_category in ["Total", "Total in EUR", ""] or
        report_date_str == "" or
        String.starts_with?(report_date_str, "Closed")

    if skip? do
      nil
    else
      date = parse_date(report_date_str)

      if date == nil do
        nil
      else
        # Extract ISIN from description: SYMBOL(ISIN) or (ISIN)
        {isin, _per_share} = extract_isin_and_per_share(description)
        instrument_id = resolve_instrument_by_isin(isin)

        action_type = classify_corporate_action(description)
        quantity = parse_decimal(quantity_str)
        proceeds = parse_decimal(proceeds_str)
        amount = parse_decimal(value_str)

        external_id =
          corporate_action_external_id(
            instrument_id || isin || description,
            date,
            action_type,
            quantity
          )

        %{
          external_id: external_id,
          instrument_id: instrument_id,
          action_type: action_type,
          date: date,
          description: description,
          quantity: quantity,
          amount: amount,
          currency: currency,
          proceeds: proceeds,
          raw_data: %{"row" => row}
        }
      end
    end
  end

  @doc """
  Classifies a corporate action type from its description.
  """
  def classify_corporate_action(description) do
    desc = String.downcase(description)

    cond do
      String.contains?(desc, "spinoff") -> "spinoff"
      String.contains?(desc, "rights issue") -> "rights_issue"
      String.contains?(desc, "subscribes to") -> "rights_exercise"
      String.contains?(desc, "stock dividend") -> "stock_dividend"
      String.contains?(desc, "merged") -> "merger"
      String.contains?(desc, "delisted") -> "delist"
      String.contains?(desc, "tendered") -> "tender"
      String.contains?(desc, "tender") -> "tender"
      String.contains?(desc, "consent") -> "consent"
      String.contains?(desc, "split") -> "split"
      String.contains?(desc, "name change") -> "name_change"
      true -> "other"
    end
  end

  defp insert_corporate_action(%{external_id: external_id} = attrs) do
    case Repo.get_by(CorporateAction, external_id: external_id) do
      nil ->
        %CorporateAction{}
        |> CorporateAction.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, _} -> {:ok, :inserted}
          {:error, changeset} -> {:error, {:insert_failed, external_id, changeset}}
        end

      _existing ->
        {:ok, :skipped}
    end
  end

  defp corporate_action_external_id(ref, date, action_type, quantity) do
    data = "corporate_action:#{ref}:#{date}:#{action_type}:#{quantity}"
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower) |> binary_part(0, 32)
  end

  # --- Net Asset Value → Margin Equity Snapshots ---

  defp import_nav_snapshot(sections) do
    rows = Map.get(sections, "Net Asset Value", [])
    statement_rows = Map.get(sections, "Statement", [])

    if rows == [] do
      Logger.info("  NAV snapshot: no data")
      %{inserted: 0, skipped: 0}
    else
      # Extract date from Statement period
      date = extract_statement_end_date(statement_rows)

      if date == nil do
        Logger.warning("  NAV snapshot: could not determine statement date")
        %{inserted: 0, skipped: 0}
      else
        parse_and_upsert_nav(rows, date)
      end
    end
  end

  defp extract_statement_end_date(statement_rows) do
    # Statement rows: [Field Name, Field Value]
    # Look for "Period" field: "January 1, 2026 - February 18, 2026" or "February 19, 2026"
    Enum.find_value(statement_rows, fn row ->
      field_name = Enum.at(row, 0, "")

      if field_name == "Period" do
        period_str = Enum.at(row, 1, "")
        parse_period_end_date(period_str)
      end
    end)
  end

  @doc """
  Parses IBKR statement period string to extract end date.
  Handles: "January 1, 2026 - February 18, 2026" and "February 19, 2026"
  """
  def parse_period_end_date(period_str) do
    # Try range format first: "Month DD, YYYY - Month DD, YYYY"
    case String.split(period_str, " - ") do
      [_, end_part] -> parse_ibkr_date_string(String.trim(end_part))
      [single] -> parse_ibkr_date_string(String.trim(single))
      _ -> nil
    end
  end

  defp parse_ibkr_date_string(str) do
    # "February 18, 2026" or "January 1, 2026"
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

  defp parse_and_upsert_nav(rows, date) do
    zero = Decimal.new("0")

    # Parse Cash and Stock/Total rows
    # NAV rows after section+Data stripped: [AssetClass, PriorTotal, CurrentLong, CurrentShort, CurrentTotal, Change]
    nav_data =
      Enum.reduce(rows, %{}, fn row, acc ->
        asset_class = Enum.at(row, 0, "") |> String.trim()
        current_total_str = Enum.at(row, 4, "")
        current_total = parse_decimal(current_total_str)

        case String.downcase(asset_class) do
          "cash" -> Map.put(acc, :cash, current_total || zero)
          "stock" -> Map.put(acc, :stock, current_total || zero)
          "total" -> Map.put(acc, :total, current_total || zero)
          _ -> acc
        end
      end)

    cash = Map.get(nav_data, :cash, zero)
    nlv = Map.get(nav_data, :total, zero)

    # Negative cash = margin loan
    margin_loan =
      if Decimal.compare(cash, zero) == :lt,
        do: Decimal.abs(cash),
        else: zero

    # NLV = cash + stock (cash is negative when on margin)
    # own_equity = NLV itself (already net of margin loan)

    attrs = %{
      date: date,
      cash_balance: cash,
      margin_loan: margin_loan,
      net_liquidation_value: nlv,
      own_equity: nlv,
      source: "ibkr_activity_statement",
      metadata: %{
        "nav_rows" =>
          nav_data |> Map.new(fn {k, v} -> {Atom.to_string(k), Decimal.to_string(v)} end)
      }
    }

    case upsert_margin_equity(attrs) do
      {:ok, :inserted} ->
        Logger.info("  NAV snapshot: inserted for #{date} (NLV: #{nlv}, Cash: #{cash})")
        %{inserted: 1, skipped: 0}

      {:ok, :skipped} ->
        Logger.info("  NAV snapshot: already exists for #{date}")
        %{inserted: 0, skipped: 1}
    end
  end

  defp upsert_margin_equity(attrs) do
    case Repo.get_by(MarginEquitySnapshot, date: attrs.date) do
      nil ->
        %MarginEquitySnapshot{}
        |> MarginEquitySnapshot.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, _} ->
            {:ok, :inserted}

          {:error, changeset} ->
            Logger.warning("  NAV insert error: #{inspect(changeset.errors)}")
            {:ok, :skipped}
        end

      _existing ->
        {:ok, :skipped}
    end
  end

  # --- Borrow Fee Details ---

  defp import_borrow_fees(sections, is_consolidated) do
    rows = Map.get(sections, "Borrow Fee Details", [])

    results =
      rows
      |> Enum.map(&parse_borrow_fee_row(&1, is_consolidated))
      |> Enum.reject(&is_nil/1)

    {inserted, skipped, errors} =
      Enum.reduce(results, {0, 0, []}, fn attrs, {ins, skip, errs} ->
        case insert_if_new(CashFlow, attrs) do
          {:ok, :inserted} -> {ins + 1, skip, errs}
          {:ok, :skipped} -> {ins, skip + 1, errs}
          {:error, reason} -> {ins, skip, [reason | errs]}
        end
      end)

    Logger.info("  Borrow fees: #{inserted} new, #{skipped} skipped, #{length(errors)} errors")

    %{inserted: inserted, skipped: skipped, errors: errors}
  end

  defp parse_borrow_fee_row(row, is_consolidated) do
    # After section+Data stripped:
    # Standard: [Currency, ValueDate, Symbol, Quantity, Price, Value, FeeRate, BorrowFee, Code]
    # Consolidated: [Currency, Account, ValueDate, Symbol, Quantity, Price, Value, FeeRate, BorrowFee, Code]
    {currency, date_str, symbol, borrow_fee_str} =
      if is_consolidated do
        {Enum.at(row, 0, ""), Enum.at(row, 2, ""), Enum.at(row, 3, ""), Enum.at(row, 8, "")}
      else
        {Enum.at(row, 0, ""), Enum.at(row, 1, ""), Enum.at(row, 2, ""), Enum.at(row, 7, "")}
      end

    if currency in ["Total", "Total in EUR", ""] or date_str == "" do
      nil
    else
      date = parse_date(date_str)
      amount = parse_decimal(borrow_fee_str)

      if date == nil or amount == nil do
        nil
      else
        description = "Borrow fee: #{symbol}"
        external_id = cash_flow_external_id("fee", date, amount, currency, description)

        %{
          external_id: external_id,
          flow_type: "fee",
          date: date,
          amount: amount,
          currency: currency,
          description: description,
          raw_data: %{"row" => row}
        }
      end
    end
  end

  # --- Instrument Resolution ---

  defp resolve_instrument_by_isin(nil), do: nil
  defp resolve_instrument_by_isin(""), do: nil

  defp resolve_instrument_by_isin(isin) do
    case Repo.one(from i in Instrument, where: i.isin == ^isin, select: i.id) do
      nil -> nil
      id -> id
    end
  end

  defp resolve_instrument_by_symbol(symbol, _currency) do
    # Look up symbol in instrument_aliases first, fall back to metadata search
    case Repo.one(
           from a in InstrumentAlias,
             where: a.symbol == ^symbol,
             join: i in Instrument,
             on: a.instrument_id == i.id,
             select: i.id,
             limit: 1
         ) do
      nil ->
        # Fall back: search instruments by metadata symbol
        Repo.one(
          from i in Instrument,
            where: fragment("?->>'symbol' = ?", i.metadata, ^symbol),
            select: i.id,
            limit: 1
        )

      id ->
        id
    end
  end

  # --- Deduplication ---

  defp insert_if_new(schema, attrs) do
    case Repo.get_by(schema, external_id: attrs.external_id) do
      nil ->
        struct(schema)
        |> schema.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, _} -> {:ok, :inserted}
          {:error, changeset} -> {:error, {:insert_failed, attrs.external_id, changeset}}
        end

      _existing ->
        {:ok, :skipped}
    end
  end

  # --- External ID Generation (Deterministic Hashes) ---

  defp trade_external_id(instrument_id, trade_date, quantity, price, amount) do
    data = "trade:#{instrument_id}:#{trade_date}:#{quantity}:#{price}:#{amount}"
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower) |> binary_part(0, 32)
  end

  defp dividend_external_id(instrument_id, date, amount, currency) do
    data = "dividend:#{instrument_id}:#{date}:#{amount}:#{currency}"
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower) |> binary_part(0, 32)
  end

  defp cash_flow_external_id(flow_type, date, amount, currency, description) do
    data = "cashflow:#{flow_type}:#{date}:#{amount}:#{currency}:#{description}"
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower) |> binary_part(0, 32)
  end

  # --- Parsing Helpers ---

  # --- FX Rates from Mark-to-Market Forex + Base Currency Exchange Rate ---

  defp import_fx_rates(sections) do
    m2m_result = import_m2m_forex_rates(sections)
    bcr_result = import_base_currency_rates(sections)

    total = m2m_result.inserted + bcr_result.inserted

    Logger.info(
      "  FX rates: #{total} upserted (#{m2m_result.inserted} M2M, #{bcr_result.inserted} BCR)"
    )

    %{inserted: total}
  end

  # Parse FX rates from Mark-to-Market Performance Summary Forex rows.
  # Format: [AssetCategory, Symbol(currency), PriorQty, CurrentQty, PriorPrice, CurrentPrice, ...]
  # PriorPrice = rate at period start, CurrentPrice = rate at period end
  defp import_m2m_forex_rates(sections) do
    rows = Map.get(sections, "Mark-to-Market Performance Summary", [])
    statement_rows = Map.get(sections, "Statement", [])

    forex_rows =
      Enum.filter(rows, fn row -> Enum.at(row, 0, "") |> String.trim() == "Forex" end)

    {start_date, end_date} = extract_statement_period(statement_rows)

    if forex_rows == [] or start_date == nil or end_date == nil do
      %{inserted: 0}
    else
      inserted =
        Enum.reduce(forex_rows, 0, &upsert_m2m_forex_row(&1, start_date, end_date, &2))

      %{inserted: inserted}
    end
  end

  defp upsert_m2m_forex_row(row, start_date, end_date, acc) do
    currency = Enum.at(row, 1, "") |> String.trim()

    if currency in ["", "EUR"] do
      acc
    else
      prior_price = Enum.at(row, 4, "") |> parse_decimal()
      current_price = Enum.at(row, 5, "") |> parse_decimal()
      c1 = upsert_fx_rate_if_valid(currency, start_date, prior_price, "activity_statement")
      c2 = upsert_fx_rate_if_valid(currency, end_date, current_price, "activity_statement")
      acc + c1 + c2
    end
  end

  # Parse FX rates from Base Currency Exchange Rate section (AllActions CSVs).
  # Format: [Currency, Rate]
  defp import_base_currency_rates(sections) do
    rows = Map.get(sections, "Base Currency Exchange Rate", [])
    statement_rows = Map.get(sections, "Statement", [])
    date = extract_statement_end_date(statement_rows)

    if rows == [] or date == nil do
      %{inserted: 0}
    else
      inserted = Enum.reduce(rows, 0, &upsert_bcr_row(&1, date, &2))
      Logger.info("  FX rates (BCR): #{inserted} currencies for #{date}")
      %{inserted: inserted}
    end
  end

  defp upsert_bcr_row(row, date, acc) do
    currency = Enum.at(row, 0, "") |> String.trim()
    rate = Enum.at(row, 1, "") |> parse_decimal()

    if currency in ["", "EUR"] or rate == nil do
      acc
    else
      acc + upsert_fx_rate_if_valid(currency, date, rate, "allactions")
    end
  end

  defp upsert_fx_rate_if_valid(_currency, _date, nil, _source), do: 0

  defp upsert_fx_rate_if_valid(currency, date, rate, source) do
    if Decimal.compare(rate, Decimal.new("0")) == :eq do
      0
    else
      case Portfolio.upsert_fx_rate(%{
             date: date,
             currency: currency,
             rate: rate,
             source: source
           }) do
        {:ok, _} -> 1
        {:error, _} -> 0
      end
    end
  end

  # Extract both start and end dates from Statement period.
  # "January 1, 2025 - December 31, 2025" → {~D[2025-01-01], ~D[2025-12-31]}
  defp extract_statement_period(statement_rows) do
    Enum.find_value(statement_rows, {nil, nil}, fn row ->
      if Enum.at(row, 0, "") == "Period" do
        parse_period_range(Enum.at(row, 1, ""))
      end
    end)
  end

  defp parse_period_range(period_str) do
    case String.split(period_str, " - ") do
      [start_part, end_part] ->
        {parse_ibkr_date_string(String.trim(start_part)),
         parse_ibkr_date_string(String.trim(end_part))}

      [single] ->
        date = parse_ibkr_date_string(String.trim(single))
        {date, date}

      _ ->
        {nil, nil}
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil
  defp parse_decimal("--"), do: nil

  defp parse_decimal(str) when is_binary(str) do
    # Remove thousands separators (commas in quantities like "1,000")
    cleaned = String.replace(str, ",", "")

    case Decimal.parse(cleaned) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil

  defp parse_integer(str) when is_binary(str) do
    case Integer.parse(String.trim(str)) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) when is_binary(str) do
    # Handle both "YYYY-MM-DD" and "YYYY-MM-DD, HH:MM:SS"
    date_part = str |> String.trim() |> String.split(",") |> List.first() |> String.trim()

    case Date.from_iso8601(date_part) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp parse_datetime(nil), do: {nil, nil}
  defp parse_datetime(""), do: {nil, nil}

  defp parse_datetime(str) when is_binary(str) do
    parts = str |> String.trim() |> String.split(",")
    date = parse_date(List.first(parts))

    time =
      case parts do
        [_, time_str] ->
          case Time.from_iso8601(String.trim(time_str)) do
            {:ok, time} -> time
            {:error, _} -> nil
          end

        _ ->
          nil
      end

    {date, time}
  end
end
