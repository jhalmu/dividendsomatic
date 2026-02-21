defmodule Mix.Tasks.Backfill.AliasesTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.{Instrument, InstrumentAlias}
  alias Mix.Tasks.Backfill.Aliases, as: BackfillAliases

  describe "split_comma_aliases/0" do
    test "should split comma-separated alias into individual records" do
      instrument = insert_instrument!("FI0009013296", "Telia Company")

      %InstrumentAlias{}
      |> InstrumentAlias.changeset(%{
        instrument_id: instrument.id,
        symbol: "TELIA1, TLS",
        source: "ibkr"
      })
      |> Repo.insert!()

      count = BackfillAliases.split_comma_aliases()
      assert count == 1

      aliases =
        Repo.all(
          from(a in InstrumentAlias,
            where: a.instrument_id == ^instrument.id,
            order_by: a.symbol
          )
        )

      assert length(aliases) == 2
      symbols = Enum.map(aliases, & &1.symbol) |> Enum.sort()
      assert symbols == ["TELIA1", "TLS"]
    end

    test "should not create duplicate when split symbol already exists" do
      instrument = insert_instrument!("FI0009013297", "Test Corp")

      %InstrumentAlias{}
      |> InstrumentAlias.changeset(%{
        instrument_id: instrument.id,
        symbol: "ABC, DEF",
        source: "ibkr"
      })
      |> Repo.insert!()

      # Pre-existing alias for DEF
      %InstrumentAlias{}
      |> InstrumentAlias.changeset(%{
        instrument_id: instrument.id,
        symbol: "DEF",
        source: "symbol_mapping"
      })
      |> Repo.insert!()

      count = BackfillAliases.split_comma_aliases()
      assert count == 0

      aliases =
        Repo.all(from(a in InstrumentAlias, where: a.instrument_id == ^instrument.id))

      assert length(aliases) == 2
    end
  end

  describe "set_primary_flags/0" do
    test "should prefer finnhub alias as primary" do
      instrument = insert_instrument!("FI0009000681", "Nokia Oyj")

      ibkr =
        %InstrumentAlias{}
        |> InstrumentAlias.changeset(%{
          instrument_id: instrument.id,
          symbol: "NOKIA HEX",
          source: "ibkr"
        })
        |> Repo.insert!()

      finnhub =
        %InstrumentAlias{}
        |> InstrumentAlias.changeset(%{
          instrument_id: instrument.id,
          symbol: "NOKIA",
          source: "finnhub"
        })
        |> Repo.insert!()

      BackfillAliases.set_primary_flags()

      assert Repo.get!(InstrumentAlias, finnhub.id).is_primary == true
      assert Repo.get!(InstrumentAlias, ibkr.id).is_primary == false
    end

    test "should prefer symbol_mapping over ibkr when no finnhub" do
      instrument = insert_instrument!("FI0009005961", "Stora Enso Oyj")

      ibkr =
        %InstrumentAlias{}
        |> InstrumentAlias.changeset(%{
          instrument_id: instrument.id,
          symbol: "STERV",
          source: "ibkr"
        })
        |> Repo.insert!()

      mapping =
        %InstrumentAlias{}
        |> InstrumentAlias.changeset(%{
          instrument_id: instrument.id,
          symbol: "STORA ENSO",
          source: "symbol_mapping"
        })
        |> Repo.insert!()

      BackfillAliases.set_primary_flags()

      assert Repo.get!(InstrumentAlias, mapping.id).is_primary == true
      assert Repo.get!(InstrumentAlias, ibkr.id).is_primary == false
    end

    test "should fall back to ibkr when no finnhub or symbol_mapping" do
      instrument = insert_instrument!("US0378331005", "Apple Inc")

      alias_record =
        %InstrumentAlias{}
        |> InstrumentAlias.changeset(%{
          instrument_id: instrument.id,
          symbol: "AAPL",
          source: "ibkr"
        })
        |> Repo.insert!()

      BackfillAliases.set_primary_flags()

      assert Repo.get!(InstrumentAlias, alias_record.id).is_primary == true
    end
  end

  describe "fix_base_names/0" do
    test "should apply override map to instrument symbol" do
      instrument =
        %Instrument{}
        |> Instrument.changeset(%{
          isin: "FI0009013296",
          name: "Telia Company",
          symbol: "TELIA1"
        })
        |> Repo.insert!()

      count = BackfillAliases.fix_base_names()
      assert count == 1

      updated = Repo.get!(Instrument, instrument.id)
      assert updated.symbol == "TELIA"
    end

    test "should not change symbol without override" do
      instrument =
        %Instrument{}
        |> Instrument.changeset(%{
          isin: "US0378331005",
          name: "Apple Inc",
          symbol: "AAPL"
        })
        |> Repo.insert!()

      count = BackfillAliases.fix_base_names()
      assert count == 0

      unchanged = Repo.get!(Instrument, instrument.id)
      assert unchanged.symbol == "AAPL"
    end
  end

  defp insert_instrument!(isin, name) do
    %Instrument{}
    |> Instrument.changeset(%{isin: isin, name: name})
    |> Repo.insert!()
  end
end
