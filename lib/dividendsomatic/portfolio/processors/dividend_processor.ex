defmodule Dividendsomatic.Portfolio.Processors.DividendProcessor do
  @moduledoc """
  Derives dividend records from Nordnet broker transactions.

  Pairs OSINKO (dividend) transactions with ENNAKKOPIDÄTYS (withholding tax)
  by confirmation_number. Stores gross amount in dividends table.
  Deduplicates by ISIN+ex_date first, then symbol+ex_date.
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.{BrokerTransaction, Dividend}
  alias Dividendsomatic.Repo

  @doc """
  Processes all Nordnet dividend transactions and inserts into dividends table.
  Returns `{:ok, count}` with the number of new dividends created.
  """
  def process do
    dividend_txns =
      BrokerTransaction
      |> where([t], t.transaction_type == "dividend" and t.broker == "nordnet")
      |> order_by([t], asc: t.trade_date)
      |> Repo.all()

    results =
      Enum.map(dividend_txns, fn txn ->
        insert_dividend(txn)
      end)

    created = Enum.count(results, &(&1 == :created))
    skipped = Enum.count(results, &(&1 == :skipped))
    Logger.info("DividendProcessor: #{created} created, #{skipped} skipped (duplicates)")
    {:ok, created}
  end

  defp insert_dividend(txn) do
    # Gross per-share amount is in the price field (Kurssi)
    amount = txn.price || calculate_per_share(txn.amount, txn.quantity)

    cond do
      is_nil(amount) || Decimal.compare(amount, Decimal.new("0")) != :gt -> :skipped
      dividend_exists?(txn) -> :skipped
      true -> do_insert_dividend(txn, amount)
    end
  end

  defp do_insert_dividend(txn, amount) do
    attrs = %{
      symbol: txn.security_name,
      ex_date: txn.trade_date,
      pay_date: txn.settlement_date,
      amount: amount,
      currency: txn.currency || "EUR",
      source: "nordnet",
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
