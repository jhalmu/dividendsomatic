defmodule Dividendsomatic.Portfolio.SoldPositionTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.{Instrument, InstrumentAlias, SoldPosition}

  describe "identifier_key computation" do
    test "should use ISIN as identifier_key when present" do
      changeset =
        SoldPosition.changeset(%SoldPosition{}, %{
          symbol: "AAPL",
          isin: "US0378331005",
          quantity: Decimal.new("10"),
          purchase_price: Decimal.new("150.00"),
          purchase_date: ~D[2024-01-15],
          sale_price: Decimal.new("175.00"),
          sale_date: ~D[2024-06-15],
          currency: "USD"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :identifier_key) == "US0378331005"
    end

    test "should use symbol prefix as identifier_key when ISIN is nil" do
      changeset =
        SoldPosition.changeset(%SoldPosition{}, %{
          symbol: "AAPL",
          quantity: Decimal.new("10"),
          purchase_price: Decimal.new("150.00"),
          purchase_date: ~D[2024-01-15],
          sale_price: Decimal.new("175.00"),
          sale_date: ~D[2024-06-15],
          currency: "USD"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :identifier_key) == "symbol:AAPL"
    end

    test "should recalculate identifier_key when ISIN is set on update" do
      sp =
        %SoldPosition{}
        |> SoldPosition.changeset(%{
          symbol: "AAPL",
          quantity: Decimal.new("10"),
          purchase_price: Decimal.new("150.00"),
          purchase_date: ~D[2024-01-15],
          sale_price: Decimal.new("175.00"),
          sale_date: ~D[2024-06-15],
          currency: "USD"
        })
        |> Repo.insert!()

      assert sp.identifier_key == "symbol:AAPL"

      updated =
        sp
        |> SoldPosition.changeset(%{isin: "US0378331005"})
        |> Repo.update!()

      assert updated.identifier_key == "US0378331005"
    end
  end

  describe "ISIN backfill matching" do
    test "should match sold_position symbol to instrument ISIN via alias" do
      # Create instrument with ISIN
      instrument =
        %Instrument{}
        |> Instrument.changeset(%{
          isin: "US0378331005",
          name: "Apple Inc",
          symbol: "AAPL",
          currency: "USD"
        })
        |> Repo.insert!()

      # Create alias linking symbol to instrument
      %InstrumentAlias{}
      |> InstrumentAlias.changeset(%{
        instrument_id: instrument.id,
        symbol: "AAPL",
        source: "ibkr"
      })
      |> Repo.insert!()

      # Create sold_position without ISIN
      sp =
        %SoldPosition{}
        |> SoldPosition.changeset(%{
          symbol: "AAPL",
          quantity: Decimal.new("10"),
          purchase_price: Decimal.new("150.00"),
          purchase_date: ~D[2024-01-15],
          sale_price: Decimal.new("175.00"),
          sale_date: ~D[2024-06-15],
          currency: "USD"
        })
        |> Repo.insert!()

      assert is_nil(sp.isin)

      # Verify the instrument can be found via alias
      match =
        from(a in InstrumentAlias,
          join: i in Instrument,
          on: a.instrument_id == i.id,
          where: a.symbol == ^sp.symbol,
          select: i.isin
        )
        |> Repo.one()

      assert match == "US0378331005"
    end
  end
end
