defmodule Dividendsomatic.Portfolio.InstrumentAliasTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.{Instrument, InstrumentAlias}

  describe "changeset/2" do
    test "should accept is_primary field" do
      instrument = insert_instrument!("US0378331005", "Apple Inc")

      changeset =
        InstrumentAlias.changeset(%InstrumentAlias{}, %{
          instrument_id: instrument.id,
          symbol: "AAPL",
          source: "finnhub",
          is_primary: true
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :is_primary) == true
    end

    test "should default is_primary to false" do
      instrument = insert_instrument!("US5949181045", "Microsoft Corp")

      alias_record =
        %InstrumentAlias{}
        |> InstrumentAlias.changeset(%{
          instrument_id: instrument.id,
          symbol: "MSFT",
          source: "ibkr"
        })
        |> Repo.insert!()

      assert alias_record.is_primary == false
    end

    test "should enforce unique primary per instrument" do
      instrument = insert_instrument!("FI0009000681", "Nokia Oyj")

      %InstrumentAlias{}
      |> InstrumentAlias.changeset(%{
        instrument_id: instrument.id,
        symbol: "NOKIA",
        source: "finnhub",
        is_primary: true
      })
      |> Repo.insert!()

      assert {:error, changeset} =
               %InstrumentAlias{}
               |> InstrumentAlias.changeset(%{
                 instrument_id: instrument.id,
                 symbol: "NOKIA HEX",
                 source: "ibkr",
                 is_primary: true
               })
               |> Repo.insert()

      assert errors_on(changeset).instrument_id
    end

    test "should allow multiple non-primary aliases per instrument" do
      instrument = insert_instrument!("FI0009005961", "Stora Enso Oyj")

      %InstrumentAlias{}
      |> InstrumentAlias.changeset(%{
        instrument_id: instrument.id,
        symbol: "STERV",
        source: "ibkr"
      })
      |> Repo.insert!()

      alias2 =
        %InstrumentAlias{}
        |> InstrumentAlias.changeset(%{
          instrument_id: instrument.id,
          symbol: "STORA ENSO",
          exchange: "HEX",
          source: "symbol_mapping"
        })
        |> Repo.insert!()

      assert alias2.is_primary == false
    end
  end

  defp insert_instrument!(isin, name) do
    %Instrument{}
    |> Instrument.changeset(%{isin: isin, name: name})
    |> Repo.insert!()
  end
end
