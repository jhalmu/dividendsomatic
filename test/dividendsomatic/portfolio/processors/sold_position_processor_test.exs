defmodule Dividendsomatic.Portfolio.Processors.SoldPositionProcessorTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.{BrokerTransaction, SoldPosition}
  alias Dividendsomatic.Portfolio.Processors.SoldPositionProcessor

  defp insert_transaction(attrs) do
    %BrokerTransaction{}
    |> BrokerTransaction.changeset(
      Map.merge(
        %{
          broker: "nordnet",
          raw_type: attrs[:raw_type] || "MYYNTI",
          external_id: "ext_#{System.unique_integer([:positive])}"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "process/0" do
    test "should create sold position from MYYNTI transaction" do
      # First insert a buy for FIFO date lookup
      insert_transaction(%{
        transaction_type: "buy",
        raw_type: "OSTO",
        trade_date: ~D[2017-03-06],
        security_name: "Xtrackers MSCI",
        isin: "LU0592217524",
        quantity: Decimal.new("30"),
        price: Decimal.new("8.00"),
        currency: "EUR"
      })

      # Then the sell
      insert_transaction(%{
        transaction_type: "sell",
        trade_date: ~D[2017-04-21],
        security_name: "Xtrackers MSCI",
        isin: "LU0592217524",
        quantity: Decimal.new("30"),
        price: Decimal.new("7.17"),
        amount: Decimal.new("200.10"),
        result: Decimal.new("-29.85"),
        currency: "EUR"
      })

      {:ok, count} = SoldPositionProcessor.process()
      assert count == 1

      [sp] = Repo.all(SoldPosition)
      assert sp.symbol == "Xtrackers MSCI"
      assert sp.sale_date == ~D[2017-04-21]
      assert Decimal.equal?(sp.sale_price, Decimal.new("7.17"))
      assert Decimal.equal?(sp.quantity, Decimal.new("30"))
      assert sp.purchase_date == ~D[2017-03-06]
      assert sp.isin == "LU0592217524"
      assert sp.source == "nordnet"
    end

    test "should back-calculate purchase price from result" do
      insert_transaction(%{
        transaction_type: "sell",
        trade_date: ~D[2017-04-21],
        security_name: "Test Stock",
        isin: "TEST123",
        quantity: Decimal.new("30"),
        price: Decimal.new("7.17"),
        result: Decimal.new("-29.85"),
        currency: "EUR"
      })

      {:ok, _} = SoldPositionProcessor.process()

      [sp] = Repo.all(SoldPosition)

      # purchase_price = sale_price - (result / quantity) = 7.17 - (-29.85/30) = 7.17 + 0.995 = 8.165
      expected =
        Decimal.sub(Decimal.new("7.17"), Decimal.div(Decimal.new("-29.85"), Decimal.new("30")))

      assert Decimal.equal?(sp.purchase_price, expected)
    end

    test "should be idempotent" do
      insert_transaction(%{
        transaction_type: "sell",
        trade_date: ~D[2017-04-21],
        security_name: "Test Stock",
        isin: "TEST123",
        quantity: Decimal.new("30"),
        price: Decimal.new("7.17"),
        result: Decimal.new("-29.85"),
        currency: "EUR"
      })

      {:ok, first} = SoldPositionProcessor.process()
      assert first == 1

      {:ok, second} = SoldPositionProcessor.process()
      assert second == 0
    end

    test "should set realized_pnl_eur for EUR transactions" do
      insert_transaction(%{
        transaction_type: "sell",
        trade_date: ~D[2017-04-21],
        security_name: "Test Stock",
        isin: "TEST123",
        quantity: Decimal.new("30"),
        price: Decimal.new("7.17"),
        result: Decimal.new("-29.85"),
        currency: "EUR"
      })

      {:ok, _} = SoldPositionProcessor.process()

      [sp] = Repo.all(SoldPosition)
      assert Decimal.equal?(sp.exchange_rate_to_eur, Decimal.new("1"))
      # realized_pnl_eur set by changeset calculate_realized_pnl (EUR auto-set)
      assert not is_nil(sp.realized_pnl_eur)
    end

    test "should skip sell with zero quantity" do
      insert_transaction(%{
        transaction_type: "sell",
        trade_date: ~D[2017-04-21],
        security_name: "Test Stock",
        isin: "TEST123",
        quantity: Decimal.new("0"),
        price: Decimal.new("7.17"),
        currency: "EUR"
      })

      {:ok, count} = SoldPositionProcessor.process()
      assert count == 0
    end
  end
end
