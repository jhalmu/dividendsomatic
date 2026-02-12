defmodule Dividendsomatic.Portfolio.Processors.DividendProcessor do
  @moduledoc """
  Derives dividend records from broker transactions.

  Handles Nordnet (per-share amount in price field) and IBKR (per-share amount
  extracted from description). Stores per-share gross amount in dividends table.
  Deduplicates by ISIN+ex_date first, then symbol+ex_date.
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.{BrokerTransaction, Dividend}
  alias Dividendsomatic.Repo

  # Extracts currency and per-share amount from IBKR descriptions.
  # Standard CSV format: "Cash Dividend USD 0.035 per Share"
  @cash_dividend_regex ~r/Cash Dividend\s+([A-Z]{3})\s+([\d.]+)/

  # Fallback for PDF-parsed descriptions where type keywords get interleaved:
  # "Cash Dividend Foreign Tax USD 0.0825 Withholding per Share"
  # "Cash Foreign Tax Dividend USD Withholding 0.24 per Share"
  @cash_dividend_pdf_regex ~r/Cash.*?\b([A-Z]{3})\b.*?([\d]+\.[\d]+)/

  @doc """
  Processes all dividend transactions and inserts into dividends table.
  Returns `{:ok, count}` with the number of new dividends created.
  """
  def process do
    dividend_txns =
      BrokerTransaction
      |> where([t], t.transaction_type == "dividend")
      |> order_by([t], asc: t.trade_date)
      |> Repo.all()

    results = Enum.map(dividend_txns, &insert_dividend/1)

    created = Enum.count(results, &(&1 == :created))
    skipped = Enum.count(results, &(&1 == :skipped))
    Logger.info("DividendProcessor: #{created} created, #{skipped} skipped (duplicates)")
    {:ok, created}
  end

  defp insert_dividend(txn) do
    {amount, currency} = extract_dividend_amount(txn)

    cond do
      is_nil(amount) || Decimal.compare(amount, Decimal.new("0")) != :gt -> :skipped
      dividend_exists?(txn) -> :skipped
      true -> do_insert_dividend(txn, amount, currency)
    end
  end

  # Nordnet: per-share amount in price field (Kurssi), or calculate from total/quantity
  defp extract_dividend_amount(%{broker: "nordnet"} = txn) do
    amount = txn.price || calculate_per_share(txn.amount, txn.quantity)
    {amount, txn.currency || "EUR"}
  end

  # IBKR: extract per-share amount and currency from description
  defp extract_dividend_amount(%{broker: "ibkr"} = txn) do
    case extract_cash_dividend_info(txn.description) do
      {per_share, currency} -> {per_share, currency}
      nil -> {nil, nil}
    end
  end

  defp extract_dividend_amount(txn) do
    amount = txn.price || calculate_per_share(txn.amount, txn.quantity)
    {amount, txn.currency || "EUR"}
  end

  defp extract_cash_dividend_info(nil), do: nil

  defp extract_cash_dividend_info(description) do
    # Try standard CSV format first, then PDF fallback for interleaved text
    try_regex(@cash_dividend_regex, description) ||
      try_regex(@cash_dividend_pdf_regex, description)
  end

  defp try_regex(regex, description) do
    case Regex.run(regex, description) do
      [_, currency, amount_str] ->
        case Decimal.parse(amount_str) do
          {decimal, _} -> {decimal, currency}
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp do_insert_dividend(txn, amount, currency) do
    attrs = %{
      symbol: txn.security_name,
      ex_date: txn.trade_date,
      pay_date: txn.settlement_date,
      amount: amount,
      currency: currency || "EUR",
      source: txn.broker,
      isin: txn.isin
    }

    case %Dividend{} |> Dividend.changeset(attrs) |> Repo.insert() do
      {:ok, _} -> :created
      {:error, _} -> :skipped
    end
  end

  defp calculate_per_share(nil, _), do: nil
  defp calculate_per_share(_, nil), do: nil

  defp calculate_per_share(amount, quantity) do
    if Decimal.compare(quantity, Decimal.new("0")) != :eq do
      amount |> Decimal.abs() |> Decimal.div(Decimal.abs(quantity))
    else
      nil
    end
  end

  defp dividend_exists?(txn) do
    # Check by ISIN + ex_date first (cross-broker dedup)
    by_isin =
      if txn.isin do
        Dividend
        |> where([d], d.isin == ^txn.isin and d.ex_date == ^txn.trade_date)
        |> Repo.exists?()
      else
        false
      end

    if by_isin do
      true
    else
      # Fall back to symbol + ex_date
      Dividend
      |> where([d], d.symbol == ^txn.security_name and d.ex_date == ^txn.trade_date)
      |> Repo.exists?()
    end
  end
end
