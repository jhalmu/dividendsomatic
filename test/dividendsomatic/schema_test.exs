defmodule Dividendsomatic.SchemaTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Portfolio.{PortfolioSnapshot, Position, SoldPosition}

  describe "PortfolioSnapshot changeset" do
    test "should require date and source" do
      changeset = PortfolioSnapshot.changeset(%PortfolioSnapshot{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).date
      assert "can't be blank" in errors_on(changeset).source
    end

    test "should accept valid snapshot" do
      attrs = %{date: ~D[2026-01-28], source: "ibkr_flex"}
      changeset = PortfolioSnapshot.changeset(%PortfolioSnapshot{}, attrs)

      assert changeset.valid?
    end

    test "should accept snapshot with metadata" do
      attrs = %{date: ~D[2026-01-28], source: "ibkr_flex", metadata: %{"raw_csv" => 1234}}
      changeset = PortfolioSnapshot.changeset(%PortfolioSnapshot{}, attrs)

      assert changeset.valid?
    end

    test "should persist snapshot" do
      {:ok, snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{date: ~D[2026-01-28], source: "ibkr_flex"})
        |> Repo.insert()

      assert snapshot.date == ~D[2026-01-28]
    end

    test "should enforce unique date" do
      {:ok, _} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{date: ~D[2026-01-28], source: "ibkr_flex"})
        |> Repo.insert()

      assert {:error, changeset} =
               %PortfolioSnapshot{}
               |> PortfolioSnapshot.changeset(%{date: ~D[2026-01-28], source: "ibkr_flex"})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).date
    end

    test "should validate data_quality inclusion" do
      attrs = %{date: ~D[2026-01-28], source: "ibkr_flex", data_quality: "invalid"}
      changeset = PortfolioSnapshot.changeset(%PortfolioSnapshot{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).data_quality
    end
  end

  describe "Position changeset" do
    test "should require portfolio_snapshot_id, date, symbol, and quantity" do
      changeset = Position.changeset(%Position{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).portfolio_snapshot_id
      assert "can't be blank" in errors_on(changeset).date
      assert "can't be blank" in errors_on(changeset).symbol
      assert "can't be blank" in errors_on(changeset).quantity
    end

    test "should accept valid position" do
      {:ok, snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{date: ~D[2026-01-28], source: "ibkr_flex"})
        |> Repo.insert()

      attrs = %{
        portfolio_snapshot_id: snapshot.id,
        date: ~D[2026-01-28],
        symbol: "KESKOB",
        currency: "EUR",
        quantity: Decimal.new("1000"),
        price: Decimal.new("21.00"),
        value: Decimal.new("21000.00")
      }

      changeset = Position.changeset(%Position{}, attrs)
      assert changeset.valid?
    end

    test "should accept all optional decimal fields" do
      {:ok, snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{date: ~D[2026-01-28], source: "ibkr_flex"})
        |> Repo.insert()

      attrs = %{
        portfolio_snapshot_id: snapshot.id,
        date: ~D[2026-01-28],
        symbol: "AAPL",
        name: "Apple Inc.",
        quantity: Decimal.new("100"),
        cost_price: Decimal.new("150.00"),
        cost_basis: Decimal.new("15000.00"),
        weight: Decimal.new("10.50"),
        unrealized_pnl: Decimal.new("500.00"),
        exchange: "NASDAQ",
        asset_class: "STK",
        fx_rate: Decimal.new("1.0"),
        isin: "US0378331005",
        figi: "BBG000B9XRY4"
      }

      changeset = Position.changeset(%Position{}, attrs)
      assert changeset.valid?
    end
  end

  describe "SoldPosition changeset" do
    test "should require mandatory fields" do
      changeset = SoldPosition.changeset(%SoldPosition{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).symbol
      assert "can't be blank" in errors_on(changeset).quantity
      assert "can't be blank" in errors_on(changeset).purchase_price
      assert "can't be blank" in errors_on(changeset).purchase_date
      assert "can't be blank" in errors_on(changeset).sale_price
      assert "can't be blank" in errors_on(changeset).sale_date
    end

    test "should validate quantity is greater than 0" do
      attrs = valid_sold_position_attrs(%{quantity: Decimal.new("0")})
      changeset = SoldPosition.changeset(%SoldPosition{}, attrs)

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).quantity
    end

    test "should validate purchase_price is greater than 0" do
      attrs = valid_sold_position_attrs(%{purchase_price: Decimal.new("0")})
      changeset = SoldPosition.changeset(%SoldPosition{}, attrs)

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).purchase_price
    end

    test "should validate sale_price is greater than 0" do
      attrs = valid_sold_position_attrs(%{sale_price: Decimal.new("0")})
      changeset = SoldPosition.changeset(%SoldPosition{}, attrs)

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).sale_price
    end

    test "should auto-calculate realized_pnl" do
      attrs = %{
        symbol: "AAPL",
        quantity: Decimal.new("100"),
        purchase_price: Decimal.new("100.00"),
        purchase_date: ~D[2025-01-01],
        sale_price: Decimal.new("150.00"),
        sale_date: ~D[2026-01-15]
      }

      changeset = SoldPosition.changeset(%SoldPosition{}, attrs)
      assert changeset.valid?

      pnl = Ecto.Changeset.get_change(changeset, :realized_pnl)
      # (150 - 100) * 100 = 5000
      assert Decimal.equal?(pnl, Decimal.new("5000.00"))
    end

    test "should calculate negative pnl for losing trade" do
      attrs = %{
        symbol: "AAPL",
        quantity: Decimal.new("50"),
        purchase_price: Decimal.new("200.00"),
        purchase_date: ~D[2025-01-01],
        sale_price: Decimal.new("150.00"),
        sale_date: ~D[2026-01-15]
      }

      changeset = SoldPosition.changeset(%SoldPosition{}, attrs)
      pnl = Ecto.Changeset.get_change(changeset, :realized_pnl)

      # (150 - 200) * 50 = -2500
      assert Decimal.equal?(pnl, Decimal.new("-2500.00"))
    end

    test "should accept optional fields" do
      attrs =
        valid_sold_position_attrs(%{
          description: "Apple Inc.",
          currency: "USD",
          notes: "Took profits"
        })

      changeset = SoldPosition.changeset(%SoldPosition{}, attrs)
      assert changeset.valid?
    end

    test "should default currency to EUR" do
      sold = %SoldPosition{}
      assert sold.currency == "EUR"
    end
  end

  defp valid_sold_position_attrs(overrides) do
    Map.merge(
      %{
        symbol: "AAPL",
        quantity: Decimal.new("100"),
        purchase_price: Decimal.new("150.00"),
        purchase_date: ~D[2025-01-01],
        sale_price: Decimal.new("175.00"),
        sale_date: ~D[2026-01-15]
      },
      overrides
    )
  end
end
