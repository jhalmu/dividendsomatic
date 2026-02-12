defmodule Dividendsomatic.Portfolio.Processors.SoldPositionProcessor do
  @moduledoc """
  Derives sold position records from Nordnet MYYNTI (sell) transactions.

  Back-calculates purchase price from Nordnet's P&L data.
  Finds earliest matching buy (OSTO) by ISIN for purchase date (FIFO).
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.{BrokerTransaction, SoldPosition}
  alias Dividendsomatic.Repo

  @doc """
  Processes all Nordnet sell transactions and inserts into sold_positions table.
  Returns `{:ok, count}` with the number of new sold positions created.
  """
  def process do
    sell_txns =
      BrokerTransaction
      |> where([t], t.transaction_type == "sell" and t.broker == "nordnet")
      |> order_by([t], asc: t.trade_date)
      |> Repo.all()

    results = Enum.map(sell_txns, &insert_sold_position/1)

    created = Enum.count(results, &(&1 == :created))
    skipped = Enum.count(results, &(&1 == :skipped))
    Logger.info("SoldPositionProcessor: #{created} created, #{skipped} skipped")
    {:ok, created}
  end

  defp insert_sold_position(txn) do
    if sold_position_exists?(txn), do: :skipped, else: do_insert_sold_position(txn)
  end

  defp do_insert_sold_position(txn) do
    quantity = Decimal.abs(txn.quantity || Decimal.new("0"))
    sale_price = txn.price || Decimal.new("0")

    if zero?(quantity) || zero?(sale_price) do
      :skipped
    else
      build_and_insert_sold_position(txn, quantity, sale_price)
    end
  end

  defp build_and_insert_sold_position(txn, quantity, sale_price) do
    purchase_price = back_calculate_purchase_price(sale_price, txn.result, quantity)
    purchase_date = find_purchase_date(txn.isin)

    attrs = %{
      symbol: txn.security_name,
      quantity: quantity,
      purchase_price: purchase_price,
      purchase_date: purchase_date || txn.trade_date,
      sale_price: sale_price,
      sale_date: txn.trade_date,
      currency: txn.currency || "EUR",
      realized_pnl: txn.result,
      isin: txn.isin,
      source: "nordnet",
      notes: "Imported from Nordnet"
    }

    case %SoldPosition{} |> SoldPosition.changeset(attrs) |> Repo.insert() do
      {:ok, _} -> :created
      {:error, _} -> :skipped
    end
  end

  defp zero?(decimal), do: Decimal.compare(decimal, Decimal.new("0")) == :eq

  # purchase_price = sale_price - (result / quantity)
  defp back_calculate_purchase_price(sale_price, nil, _quantity), do: sale_price

  defp back_calculate_purchase_price(sale_price, result, quantity) do
    if Decimal.compare(quantity, Decimal.new("0")) != :eq do
      per_share_pnl = Decimal.div(result, quantity)
      price = Decimal.sub(sale_price, per_share_pnl)
      # Ensure positive purchase price
      if Decimal.compare(price, Decimal.new("0")) == :gt, do: price, else: sale_price
    else
      sale_price
    end
  end

  # Find earliest buy transaction for this ISIN (FIFO)
  defp find_purchase_date(nil), do: nil

  defp find_purchase_date(isin) do
    BrokerTransaction
    |> where([t], t.transaction_type == "buy" and t.isin == ^isin and t.broker == "nordnet")
    |> order_by([t], asc: t.trade_date)
    |> limit(1)
    |> select([t], t.trade_date)
    |> Repo.one()
  end

  defp sold_position_exists?(txn) do
    # Check by ISIN + sale_date + quantity
    if txn.isin do
      quantity = Decimal.abs(txn.quantity || Decimal.new("0"))

      SoldPosition
      |> where(
        [s],
        s.isin == ^txn.isin and s.sale_date == ^txn.trade_date and s.quantity == ^quantity
      )
      |> Repo.exists?()
    else
      SoldPosition
      |> where([s], s.symbol == ^txn.security_name and s.sale_date == ^txn.trade_date)
      |> Repo.exists?()
    end
  end
end
