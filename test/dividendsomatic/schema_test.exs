defmodule Dividendsomatic.SchemaTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Portfolio.{Dividend, Holding, PortfolioSnapshot, SoldPosition}

  describe "PortfolioSnapshot changeset" do
    test "should require report_date" do
      changeset = PortfolioSnapshot.changeset(%PortfolioSnapshot{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).report_date
    end

    test "should accept valid snapshot" do
      attrs = %{report_date: ~D[2026-01-28], raw_csv_data: "some,csv,data"}
      changeset = PortfolioSnapshot.changeset(%PortfolioSnapshot{}, attrs)

      assert changeset.valid?
    end

    test "should accept snapshot without raw_csv_data" do
      attrs = %{report_date: ~D[2026-01-28]}
      changeset = PortfolioSnapshot.changeset(%PortfolioSnapshot{}, attrs)

      assert changeset.valid?
    end

    test "should persist snapshot" do
      {:ok, snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{report_date: ~D[2026-01-28]})
        |> Repo.insert()

      assert snapshot.report_date == ~D[2026-01-28]
    end

    test "should enforce unique report_date" do
      {:ok, _} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{report_date: ~D[2026-01-28]})
        |> Repo.insert()

      assert {:error, changeset} =
               %PortfolioSnapshot{}
               |> PortfolioSnapshot.changeset(%{report_date: ~D[2026-01-28]})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).report_date
    end
  end

  describe "Holding changeset" do
    test "should require portfolio_snapshot_id, report_date, and symbol" do
      changeset = Holding.changeset(%Holding{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).portfolio_snapshot_id
      assert "can't be blank" in errors_on(changeset).report_date
      assert "can't be blank" in errors_on(changeset).symbol
    end

    test "should accept valid holding" do
      {:ok, snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{report_date: ~D[2026-01-28]})
        |> Repo.insert()

      attrs = %{
        portfolio_snapshot_id: snapshot.id,
        report_date: ~D[2026-01-28],
        symbol: "KESKOB",
        currency_primary: "EUR",
        quantity: Decimal.new("1000"),
        mark_price: Decimal.new("21.00"),
        position_value: Decimal.new("21000.00")
      }

      changeset = Holding.changeset(%Holding{}, attrs)
      assert changeset.valid?
    end

    test "should accept all optional decimal fields" do
      {:ok, snapshot} =
        %PortfolioSnapshot{}
        |> PortfolioSnapshot.changeset(%{report_date: ~D[2026-01-28]})
        |> Repo.insert()

      attrs = %{
        portfolio_snapshot_id: snapshot.id,
        report_date: ~D[2026-01-28],
        symbol: "AAPL",
        description: "Apple Inc.",
        sub_category: "COMMON",
        cost_basis_price: Decimal.new("150.00"),
        cost_basis_money: Decimal.new("15000.00"),
        open_price: Decimal.new("149.00"),
        percent_of_nav: Decimal.new("10.50"),
        fifo_pnl_unrealized: Decimal.new("500.00"),
        listing_exchange: "NASDAQ",
        asset_class: "STK",
        fx_rate_to_base: Decimal.new("1.0"),
        isin: "US0378331005",
        figi: "BBG000B9XRY4"
      }

      changeset = Holding.changeset(%Holding{}, attrs)
      assert changeset.valid?
    end
  end

  describe "Dividend changeset" do
    test "should require symbol, ex_date, amount" do
      changeset = Dividend.changeset(%Dividend{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).symbol
      assert "can't be blank" in errors_on(changeset).ex_date
      assert "can't be blank" in errors_on(changeset).amount
    end

    test "should validate amount is greater than 0" do
      attrs = %{
        symbol: "KESKOB",
        ex_date: ~D[2026-01-15],
        amount: Decimal.new("0"),
        currency: "EUR"
      }

      changeset = Dividend.changeset(%Dividend{}, attrs)

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).amount
    end

    test "should reject negative amount" do
      attrs = %{
        symbol: "KESKOB",
        ex_date: ~D[2026-01-15],
        amount: Decimal.new("-1.00"),
        currency: "EUR"
      }

      changeset = Dividend.changeset(%Dividend{}, attrs)

      refute changeset.valid?
    end

    test "should accept valid dividend" do
      attrs = %{
        symbol: "KESKOB",
        ex_date: ~D[2026-01-15],
        pay_date: ~D[2026-02-01],
        amount: Decimal.new("0.50"),
        currency: "EUR",
        source: "Interactive Brokers"
      }

      changeset = Dividend.changeset(%Dividend{}, attrs)
      assert changeset.valid?
    end

    test "should default currency to EUR" do
      dividend = %Dividend{}
      assert dividend.currency == "EUR"
    end

    test "should persist dividend" do
      attrs = %{
        symbol: "KESKOB",
        ex_date: ~D[2026-01-15],
        amount: Decimal.new("0.50"),
        currency: "EUR"
      }

      {:ok, dividend} =
        %Dividend{}
        |> Dividend.changeset(attrs)
        |> Repo.insert()

      assert dividend.symbol == "KESKOB"
      assert Decimal.equal?(dividend.amount, Decimal.new("0.50"))
    end

    test "should enforce unique constraint on symbol+ex_date+amount" do
      attrs = %{
        symbol: "KESKOB",
        ex_date: ~D[2026-01-15],
        amount: Decimal.new("0.50"),
        currency: "EUR"
      }

      {:ok, _} =
        %Dividend{}
        |> Dividend.changeset(attrs)
        |> Repo.insert()

      # Second insert with same key fields should raise
      assert_raise Ecto.ConstraintError, fn ->
        %Dividend{}
        |> Dividend.changeset(attrs)
        |> Repo.insert!()
      end
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
