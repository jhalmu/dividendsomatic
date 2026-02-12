defmodule Dividendsomatic.Portfolio.Processors.DividendProcessorTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.{BrokerTransaction, Dividend}
  alias Dividendsomatic.Portfolio.Processors.DividendProcessor

  defp insert_transaction(attrs) do
    %BrokerTransaction{}
    |> BrokerTransaction.changeset(
      Map.merge(
        %{
          broker: "nordnet",
          raw_type: "OSINKO",
          external_id: "ext_#{System.unique_integer([:positive])}"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "process/0" do
    test "should create dividend from OSINKO transaction" do
      insert_transaction(%{
        transaction_type: "dividend",
        trade_date: ~D[2017-04-03],
        security_name: "YIT Corporation",
        isin: "FI0009800643",
        quantity: Decimal.new("20"),
        price: Decimal.new("0.22"),
        amount: Decimal.new("4.40"),
        currency: "EUR",
        confirmation_number: "217741667"
      })

      {:ok, count} = DividendProcessor.process()
      assert count == 1

      [dividend] = Repo.all(Dividend)
      assert dividend.symbol == "YIT Corporation"
      assert dividend.ex_date == ~D[2017-04-03]
      assert Decimal.equal?(dividend.amount, Decimal.new("0.22"))
      assert dividend.isin == "FI0009800643"
      assert dividend.source == "nordnet"
      assert dividend.currency == "EUR"
    end

    test "should be idempotent (skip duplicates)" do
      insert_transaction(%{
        transaction_type: "dividend",
        trade_date: ~D[2017-04-03],
        security_name: "YIT Corporation",
        isin: "FI0009800643",
        quantity: Decimal.new("20"),
        price: Decimal.new("0.22"),
        amount: Decimal.new("4.40"),
        currency: "EUR"
      })

      {:ok, first_count} = DividendProcessor.process()
      assert first_count == 1

      {:ok, second_count} = DividendProcessor.process()
      assert second_count == 0
    end

    test "should skip transactions with zero amount" do
      insert_transaction(%{
        transaction_type: "dividend",
        trade_date: ~D[2017-04-03],
        security_name: "Test Corp",
        isin: "FI123",
        quantity: Decimal.new("0"),
        price: Decimal.new("0"),
        amount: Decimal.new("0"),
        currency: "EUR"
      })

      {:ok, count} = DividendProcessor.process()
      assert count == 0
    end

    test "should deduplicate by ISIN across brokers" do
      # Pre-existing dividend (e.g., from IBKR/yfinance)
      %Dividend{}
      |> Dividend.changeset(%{
        symbol: "YIT",
        ex_date: ~D[2017-04-03],
        amount: Decimal.new("0.22"),
        currency: "EUR",
        isin: "FI0009800643"
      })
      |> Repo.insert!()

      # Nordnet transaction with same ISIN + date
      insert_transaction(%{
        transaction_type: "dividend",
        trade_date: ~D[2017-04-03],
        security_name: "YIT Corporation",
        isin: "FI0009800643",
        price: Decimal.new("0.22"),
        amount: Decimal.new("4.40"),
        currency: "EUR"
      })

      {:ok, count} = DividendProcessor.process()
      assert count == 0
    end
  end
end
