defmodule Dividendsomatic.Portfolio.Processors.CostProcessorTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.{BrokerTransaction, Cost}
  alias Dividendsomatic.Portfolio.Processors.CostProcessor

  defp insert_transaction(attrs) do
    %BrokerTransaction{}
    |> BrokerTransaction.changeset(
      Map.merge(
        %{
          broker: "nordnet",
          external_id: "ext_#{System.unique_integer([:positive])}"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "process/0" do
    test "should extract commission from buy transaction" do
      insert_transaction(%{
        transaction_type: "buy",
        raw_type: "OSTO",
        trade_date: ~D[2017-03-06],
        security_name: "iShares Core",
        isin: "IE00BKM4GZ66",
        commission: Decimal.new("15"),
        currency: "EUR"
      })

      {:ok, count} = CostProcessor.process()
      assert count == 1

      [cost] = Repo.all(Cost)
      assert cost.cost_type == "commission"
      assert Decimal.equal?(cost.amount, Decimal.new("15"))
      assert cost.symbol == "iShares Core"
      assert cost.broker == "nordnet"
    end

    test "should extract withholding tax" do
      insert_transaction(%{
        transaction_type: "withholding_tax",
        raw_type: "ENNAKKOPIDÄTYS",
        trade_date: ~D[2017-04-03],
        security_name: "YIT Corporation",
        isin: "FI0009800643",
        amount: Decimal.new("-1.12"),
        currency: "EUR"
      })

      {:ok, count} = CostProcessor.process()
      assert count == 1

      [cost] = Repo.all(Cost)
      assert cost.cost_type == "withholding_tax"
      assert Decimal.equal?(cost.amount, Decimal.new("1.12"))
    end

    test "should extract loan interest" do
      insert_transaction(%{
        transaction_type: "loan_interest",
        raw_type: "LAINAKORKO",
        trade_date: ~D[2018-01-02],
        amount: Decimal.new("-5.50"),
        currency: "EUR"
      })

      {:ok, count} = CostProcessor.process()
      assert count == 1

      [cost] = Repo.all(Cost)
      assert cost.cost_type == "loan_interest"
      assert Decimal.equal?(cost.amount, Decimal.new("5.50"))
    end

    test "should skip zero commission" do
      insert_transaction(%{
        transaction_type: "buy",
        raw_type: "OSTO",
        trade_date: ~D[2017-03-06],
        commission: Decimal.new("0"),
        currency: "EUR"
      })

      {:ok, count} = CostProcessor.process()
      assert count == 0
    end

    test "should be idempotent" do
      insert_transaction(%{
        transaction_type: "buy",
        raw_type: "OSTO",
        trade_date: ~D[2017-03-06],
        commission: Decimal.new("15"),
        currency: "EUR"
      })

      {:ok, first} = CostProcessor.process()
      assert first == 1

      {:ok, second} = CostProcessor.process()
      assert second == 0
    end

    test "should store amounts as positive values" do
      insert_transaction(%{
        transaction_type: "foreign_tax",
        raw_type: "ULKOM. KUPONKIVERO",
        trade_date: ~D[2018-06-15],
        security_name: "US Stock",
        amount: Decimal.new("-3.75"),
        currency: "USD"
      })

      {:ok, _} = CostProcessor.process()

      [cost] = Repo.all(Cost)
      assert cost.cost_type == "foreign_tax"
      assert Decimal.compare(cost.amount, Decimal.new("0")) == :gt
    end
  end
end
