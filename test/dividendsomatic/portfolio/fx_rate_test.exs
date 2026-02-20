defmodule Dividendsomatic.Portfolio.FxRateTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio
  alias Dividendsomatic.Portfolio.FxRate

  describe "FxRate schema" do
    test "should create valid fx_rate with required fields" do
      changeset =
        FxRate.changeset(%FxRate{}, %{
          date: ~D[2025-01-15],
          currency: "USD",
          rate: Decimal.new("0.85")
        })

      assert changeset.valid?
    end

    test "should create fx_rate with source" do
      changeset =
        FxRate.changeset(%FxRate{}, %{
          date: ~D[2025-01-15],
          currency: "USD",
          rate: Decimal.new("0.85"),
          source: "activity_statement"
        })

      assert changeset.valid?
    end

    test "should require date" do
      changeset =
        FxRate.changeset(%FxRate{}, %{
          currency: "USD",
          rate: Decimal.new("0.85")
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).date
    end

    test "should require currency" do
      changeset =
        FxRate.changeset(%FxRate{}, %{
          date: ~D[2025-01-15],
          rate: Decimal.new("0.85")
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).currency
    end

    test "should require rate" do
      changeset =
        FxRate.changeset(%FxRate{}, %{
          date: ~D[2025-01-15],
          currency: "USD"
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).rate
    end

    test "should enforce unique constraint on date + currency" do
      attrs = %{date: ~D[2025-01-15], currency: "USD", rate: Decimal.new("0.85")}

      {:ok, _} = Portfolio.upsert_fx_rate(attrs)

      # Upserting same date+currency should update, not error
      {:ok, updated} = Portfolio.upsert_fx_rate(%{attrs | rate: Decimal.new("0.86")})
      assert Decimal.equal?(updated.rate, Decimal.new("0.86"))
    end
  end

  describe "get_fx_rate/2" do
    test "should return 1 for EUR" do
      assert Decimal.equal?(Portfolio.get_fx_rate("EUR", ~D[2025-01-15]), Decimal.new("1"))
    end

    test "should return exact date match" do
      Portfolio.upsert_fx_rate(%{
        date: ~D[2025-01-15],
        currency: "USD",
        rate: Decimal.new("0.85")
      })

      rate = Portfolio.get_fx_rate("USD", ~D[2025-01-15])
      assert Decimal.equal?(rate, Decimal.new("0.85"))
    end

    test "should return nearest preceding date when exact match missing" do
      Portfolio.upsert_fx_rate(%{
        date: ~D[2025-01-10],
        currency: "USD",
        rate: Decimal.new("0.84")
      })

      Portfolio.upsert_fx_rate(%{
        date: ~D[2025-01-20],
        currency: "USD",
        rate: Decimal.new("0.86")
      })

      # Query date 2025-01-15 should find 2025-01-10 rate (nearest preceding)
      rate = Portfolio.get_fx_rate("USD", ~D[2025-01-15])
      assert Decimal.equal?(rate, Decimal.new("0.84"))
    end

    test "should return nil when no rate exists for currency" do
      assert Portfolio.get_fx_rate("ZZZ", ~D[2025-01-15]) == nil
    end

    test "should return nil when no rate exists before requested date" do
      Portfolio.upsert_fx_rate(%{
        date: ~D[2025-06-01],
        currency: "SEK",
        rate: Decimal.new("0.09")
      })

      # Query for a date before any rate exists
      assert Portfolio.get_fx_rate("SEK", ~D[2025-01-01]) == nil
    end

    test "should return nil for nil currency" do
      assert Portfolio.get_fx_rate(nil, ~D[2025-01-15]) == nil
    end
  end

  describe "upsert_fx_rate/1" do
    test "should insert a new rate" do
      {:ok, rate} =
        Portfolio.upsert_fx_rate(%{
          date: ~D[2025-03-01],
          currency: "CAD",
          rate: Decimal.new("0.62"),
          source: "flex_csv"
        })

      assert rate.currency == "CAD"
      assert rate.source == "flex_csv"
    end

    test "should update existing rate on conflict" do
      attrs = %{
        date: ~D[2025-03-01],
        currency: "CAD",
        rate: Decimal.new("0.62"),
        source: "flex_csv"
      }

      {:ok, _} = Portfolio.upsert_fx_rate(attrs)

      {:ok, updated} =
        Portfolio.upsert_fx_rate(%{
          attrs
          | rate: Decimal.new("0.63"),
            source: "activity_statement"
        })

      assert Decimal.equal?(updated.rate, Decimal.new("0.63"))
      assert updated.source == "activity_statement"
    end
  end
end
