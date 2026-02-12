defmodule Dividendsomatic.Portfolio.CostTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.Cost

  describe "changeset/2" do
    test "should validate required fields" do
      changeset = Cost.changeset(%Cost{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).cost_type
      assert "can't be blank" in errors_on(changeset).date
      assert "can't be blank" in errors_on(changeset).amount
      assert "can't be blank" in errors_on(changeset).broker
    end

    test "should accept valid attributes" do
      attrs = %{
        cost_type: "commission",
        date: ~D[2017-03-06],
        amount: Decimal.new("15.00"),
        currency: "EUR",
        broker: "nordnet",
        symbol: "iShares Core"
      }

      changeset = Cost.changeset(%Cost{}, attrs)
      assert changeset.valid?
    end

    test "should validate cost_type inclusion" do
      attrs = %{
        cost_type: "invalid_type",
        date: ~D[2017-03-06],
        amount: Decimal.new("15"),
        currency: "EUR",
        broker: "nordnet"
      }

      changeset = Cost.changeset(%Cost{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).cost_type
    end

    test "should validate amount greater than 0" do
      attrs = %{
        cost_type: "commission",
        date: ~D[2017-03-06],
        amount: Decimal.new("0"),
        currency: "EUR",
        broker: "nordnet"
      }

      changeset = Cost.changeset(%Cost{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).amount
    end

    test "should validate negative amount" do
      attrs = %{
        cost_type: "commission",
        date: ~D[2017-03-06],
        amount: Decimal.new("-5"),
        currency: "EUR",
        broker: "nordnet"
      }

      changeset = Cost.changeset(%Cost{}, attrs)
      refute changeset.valid?
    end

    test "should default currency to EUR" do
      attrs = %{
        cost_type: "commission",
        date: ~D[2017-03-06],
        amount: Decimal.new("15"),
        broker: "nordnet"
      }

      changeset = Cost.changeset(%Cost{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :currency) == "EUR"
    end
  end
end
