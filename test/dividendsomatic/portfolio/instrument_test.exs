defmodule Dividendsomatic.Portfolio.InstrumentTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.Instrument
  alias Dividendsomatic.Repo

  describe "changeset/2" do
    test "should accept symbol field" do
      changeset =
        Instrument.changeset(%Instrument{}, %{
          isin: "US0378331005",
          name: "Apple Inc",
          symbol: "AAPL",
          currency: "USD"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :symbol) == "AAPL"
    end

    test "should allow nil symbol" do
      changeset =
        Instrument.changeset(%Instrument{}, %{
          isin: "US5949181045",
          name: "Microsoft Corp"
        })

      assert changeset.valid?
    end

    test "should persist symbol to database" do
      instrument =
        %Instrument{}
        |> Instrument.changeset(%{
          isin: "US0231351067",
          name: "Amazon.com Inc",
          symbol: "AMZN",
          currency: "USD"
        })
        |> Repo.insert!()

      loaded = Repo.get!(Instrument, instrument.id)
      assert loaded.symbol == "AMZN"
    end
  end
end
