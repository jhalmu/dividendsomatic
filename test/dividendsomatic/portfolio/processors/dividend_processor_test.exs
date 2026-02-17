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
      assert dividend.amount_type == "per_share"
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

    test "should extract per-share from IBKR Cash Dividend description" do
      insert_transaction(%{
        broker: "ibkr",
        raw_type: "Cash Dividend",
        transaction_type: "dividend",
        trade_date: ~D[2023-06-15],
        security_name: "AAPL",
        isin: "US0378331005",
        amount: Decimal.new("24.00"),
        currency: "USD",
        description: "Cash Dividend USD 0.24 per Share"
      })

      {:ok, count} = DividendProcessor.process()
      assert count == 1

      [dividend] = Repo.all(Dividend)
      assert Decimal.equal?(dividend.amount, Decimal.new("0.24"))
      assert dividend.currency == "USD"
      assert dividend.amount_type == "per_share"
    end

    test "should extract per-share from IBKR PDF interleaved description" do
      insert_transaction(%{
        broker: "ibkr",
        raw_type: "Cash Dividend",
        transaction_type: "dividend",
        trade_date: ~D[2023-06-15],
        security_name: "MSFT",
        isin: "US5949181045",
        amount: Decimal.new("16.50"),
        currency: "USD",
        description: "Cash Dividend Foreign Tax USD 0.0825 Withholding per Share"
      })

      {:ok, count} = DividendProcessor.process()
      assert count == 1

      [dividend] = Repo.all(Dividend)
      assert Decimal.equal?(dividend.amount, Decimal.new("0.0825"))
      assert dividend.currency == "USD"
      assert dividend.amount_type == "per_share"
    end

    test "should fall back to total_net for PIL without per-share amount" do
      insert_transaction(%{
        broker: "ibkr",
        raw_type: "Payment In Lieu Of Dividend",
        transaction_type: "dividend",
        trade_date: ~D[2023-09-01],
        security_name: "AGNC",
        isin: "US00123Q1040",
        amount: Decimal.new("30.60"),
        currency: "USD",
        description: "Payment In Lieu Of Dividend (Ordinary Dividend)"
      })

      {:ok, count} = DividendProcessor.process()
      assert count == 1

      [dividend] = Repo.all(Dividend)
      assert Decimal.equal?(dividend.amount, Decimal.new("30.60"))
      assert dividend.currency == "USD"
      assert dividend.amount_type == "total_net"
    end

    test "should skip Foreign Tax records without Cash Dividend" do
      insert_transaction(%{
        broker: "ibkr",
        raw_type: "Foreign Tax",
        transaction_type: "dividend",
        trade_date: ~D[2023-06-15],
        security_name: "AAPL",
        isin: "US0378331005",
        amount: Decimal.new("-3.60"),
        currency: "USD",
        description: "Foreign Tax Withholding"
      })

      {:ok, count} = DividendProcessor.process()
      assert count == 0
    end

    test "should NOT skip Foreign Tax records that include Cash Dividend" do
      insert_transaction(%{
        broker: "ibkr",
        raw_type: "Cash Dividend",
        transaction_type: "dividend",
        trade_date: ~D[2023-06-15],
        security_name: "MSFT",
        isin: "US5949181045",
        amount: Decimal.new("16.50"),
        currency: "USD",
        description: "Cash Dividend Foreign Tax USD 0.68 per Share"
      })

      {:ok, count} = DividendProcessor.process()
      assert count == 1
    end
  end

  describe "currency_from_isin/1" do
    test "should return USD for US ISINs" do
      assert DividendProcessor.currency_from_isin("US0378331005") == "USD"
    end

    test "should return CAD for Canadian ISINs" do
      assert DividendProcessor.currency_from_isin("CAC010971017") == "CAD"
    end

    test "should return EUR for Finnish ISINs" do
      assert DividendProcessor.currency_from_isin("FI0009800643") == "EUR"
    end

    test "should return SEK for Swedish ISINs" do
      assert DividendProcessor.currency_from_isin("SE0000108656") == "SEK"
    end

    test "should return JPY for Japanese ISINs" do
      assert DividendProcessor.currency_from_isin("JP3633400001") == "JPY"
    end

    test "should return GBP for British ISINs" do
      assert DividendProcessor.currency_from_isin("GB0002374006") == "GBP"
    end

    test "should return HKD for Hong Kong ISINs" do
      assert DividendProcessor.currency_from_isin("HK0011000095") == "HKD"
    end

    test "should return nil for unknown country" do
      assert DividendProcessor.currency_from_isin("XX1234567890") == nil
    end

    test "should return nil for nil ISIN" do
      assert DividendProcessor.currency_from_isin(nil) == nil
    end
  end
end
