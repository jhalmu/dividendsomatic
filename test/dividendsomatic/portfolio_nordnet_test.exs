defmodule Dividendsomatic.PortfolioNordnetTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio

  describe "broker transactions" do
    test "should create a broker transaction" do
      {:ok, txn} =
        Portfolio.create_broker_transaction(%{
          broker: "nordnet",
          transaction_type: "buy",
          raw_type: "OSTO",
          external_id: "ctx_1",
          isin: "FI001"
        })

      assert txn.broker == "nordnet"
      assert txn.transaction_type == "buy"
    end

    test "should upsert broker transaction (idempotent)" do
      attrs = %{
        broker: "nordnet",
        transaction_type: "buy",
        raw_type: "OSTO",
        external_id: "ctx_upsert_1"
      }

      {:ok, _} = Portfolio.upsert_broker_transaction(attrs)
      {:ok, _} = Portfolio.upsert_broker_transaction(attrs)

      txns = Portfolio.list_broker_transactions(broker: "nordnet")
      assert length(txns) == 1
    end

    test "should list broker transactions with filters" do
      Portfolio.create_broker_transaction(%{
        broker: "nordnet",
        transaction_type: "buy",
        raw_type: "OSTO",
        external_id: "f1",
        isin: "FI001"
      })

      Portfolio.create_broker_transaction(%{
        broker: "nordnet",
        transaction_type: "sell",
        raw_type: "MYYNTI",
        external_id: "f2",
        isin: "FI002"
      })

      all = Portfolio.list_broker_transactions()
      assert length(all) == 2

      buys = Portfolio.list_broker_transactions(type: "buy")
      assert length(buys) == 1

      fi001 = Portfolio.list_broker_transactions(isin: "FI001")
      assert length(fi001) == 1
    end
  end

  describe "costs" do
    test "should create a cost" do
      {:ok, cost} =
        Portfolio.create_cost(%{
          cost_type: "commission",
          date: ~D[2017-03-06],
          amount: Decimal.new("15"),
          currency: "EUR",
          broker: "nordnet"
        })

      assert cost.cost_type == "commission"
      assert Decimal.equal?(cost.amount, Decimal.new("15"))
    end

    test "should list costs" do
      Portfolio.create_cost(%{
        cost_type: "commission",
        date: ~D[2017-03-06],
        amount: Decimal.new("15"),
        currency: "EUR",
        broker: "nordnet"
      })

      assert length(Portfolio.list_costs()) == 1
    end

    test "should list costs by type" do
      Portfolio.create_cost(%{
        cost_type: "commission",
        date: ~D[2017-03-06],
        amount: Decimal.new("15"),
        currency: "EUR",
        broker: "nordnet"
      })

      Portfolio.create_cost(%{
        cost_type: "withholding_tax",
        date: ~D[2017-04-03],
        amount: Decimal.new("1.12"),
        currency: "EUR",
        broker: "nordnet"
      })

      commissions = Portfolio.list_costs_by_type("commission")
      assert length(commissions) == 1
    end

    test "should return costs summary" do
      Portfolio.create_cost(%{
        cost_type: "commission",
        date: ~D[2017-03-06],
        amount: Decimal.new("15"),
        currency: "EUR",
        broker: "nordnet"
      })

      Portfolio.create_cost(%{
        cost_type: "commission",
        date: ~D[2017-04-21],
        amount: Decimal.new("9"),
        currency: "EUR",
        broker: "nordnet"
      })

      summary = Portfolio.costs_summary()
      assert summary.count == 2
      assert Decimal.equal?(summary.total, Decimal.new("24"))
      assert Decimal.equal?(summary.by_type["commission"], Decimal.new("24"))
    end

    test "should return total costs by type" do
      Portfolio.create_cost(%{
        cost_type: "commission",
        date: ~D[2017-03-06],
        amount: Decimal.new("15"),
        currency: "EUR",
        broker: "nordnet"
      })

      by_type = Portfolio.total_costs_by_type()
      assert Decimal.equal?(by_type["commission"], Decimal.new("15"))
    end
  end

  describe "broker_coverage/0" do
    test "should return coverage data" do
      coverage = Portfolio.broker_coverage()
      assert Map.has_key?(coverage, :nordnet)
      assert Map.has_key?(coverage, :ibkr)
    end
  end

  describe "stock_gaps/1" do
    test "should return empty list when no data" do
      gaps = Portfolio.stock_gaps()
      assert gaps == []
    end
  end
end
