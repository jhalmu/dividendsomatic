defmodule Dividendsomatic.Portfolio.BrokerTransactionTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.BrokerTransaction

  describe "changeset/2" do
    test "should validate required fields" do
      changeset = BrokerTransaction.changeset(%BrokerTransaction{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).broker
      assert "can't be blank" in errors_on(changeset).transaction_type
      assert "can't be blank" in errors_on(changeset).raw_type
    end

    test "should accept valid attributes" do
      attrs = %{
        broker: "nordnet",
        transaction_type: "buy",
        raw_type: "OSTO",
        external_id: "123",
        isin: "FI0009000202",
        trade_date: ~D[2017-03-06],
        quantity: Decimal.new("100"),
        price: Decimal.new("10.50")
      }

      changeset = BrokerTransaction.changeset(%BrokerTransaction{}, attrs)
      assert changeset.valid?
    end

    test "should validate transaction_type inclusion" do
      attrs = %{broker: "nordnet", transaction_type: "invalid", raw_type: "OSTO"}
      changeset = BrokerTransaction.changeset(%BrokerTransaction{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).transaction_type
    end

    test "should enforce unique constraint on broker + external_id" do
      attrs = %{
        broker: "nordnet",
        transaction_type: "buy",
        raw_type: "OSTO",
        external_id: "unique_123"
      }

      {:ok, _} =
        %BrokerTransaction{}
        |> BrokerTransaction.changeset(attrs)
        |> Repo.insert()

      {:error, changeset} =
        %BrokerTransaction{}
        |> BrokerTransaction.changeset(attrs)
        |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).broker
    end
  end
end
