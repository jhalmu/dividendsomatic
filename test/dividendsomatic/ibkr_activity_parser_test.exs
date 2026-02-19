defmodule Dividendsomatic.IbkrActivityParserTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Portfolio.{CashFlow, DividendPayment, Instrument, InstrumentAlias, Trade}
  alias Dividendsomatic.Portfolio.IbkrActivityParser

  describe "parse_csv_line/1" do
    test "should parse simple CSV line" do
      assert IbkrActivityParser.parse_csv_line("a,b,c") == ["a", "b", "c"]
    end

    test "should handle quoted fields with commas" do
      line = ~s(Trades,Data,Order,Stocks,EUR,AKTIA,"2026-01-08, 07:42:02",-,500)
      result = IbkrActivityParser.parse_csv_line(line)
      assert Enum.at(result, 6) == "2026-01-08, 07:42:02"
    end

    test "should handle empty fields" do
      assert IbkrActivityParser.parse_csv_line("a,,c") == ["a", "", "c"]
    end

    test "should handle trailing comma" do
      assert IbkrActivityParser.parse_csv_line("a,b,") == ["a", "b", ""]
    end
  end

  describe "split_sections/1" do
    test "should group rows by section name" do
      raw = """
      Statement,Header,Field Name,Field Value
      Statement,Data,Title,Activity Statement
      Trades,Header,DataDiscriminator,Asset Category
      Trades,Data,Trade,Stocks,EUR,AKTIA
      Trades,Data,Trade,Stocks,USD,AGNC
      Dividends,Header,Currency,Date,Description,Amount
      Dividends,Data,EUR,2026-01-20,Test Dividend,100
      """

      sections = IbkrActivityParser.split_sections(raw)

      assert length(Map.get(sections, "Statement", [])) == 1
      assert length(Map.get(sections, "Trades", [])) == 2
      assert length(Map.get(sections, "Dividends", [])) == 1
    end

    test "should skip Header and Total rows" do
      raw = """
      Trades,Header,Col1,Col2
      Trades,Data,val1,val2
      Trades,Total,sum1,sum2
      """

      sections = IbkrActivityParser.split_sections(raw)
      assert length(Map.get(sections, "Trades", [])) == 1
    end
  end

  describe "extract_isin_and_per_share/1" do
    test "should extract ISIN and per-share from standard dividend description" do
      desc = "KESKOB(FI0009000202) Cash Dividend EUR 0.22 per Share (Ordinary Dividend)"
      {isin, per_share} = IbkrActivityParser.extract_isin_and_per_share(desc)

      assert isin == "FI0009000202"
      assert Decimal.equal?(per_share, Decimal.new("0.22"))
    end

    test "should extract ISIN from US stock dividend" do
      desc = "AGNC(US00123Q1040) Cash Dividend USD 0.12 per Share (Ordinary Dividend)"
      {isin, per_share} = IbkrActivityParser.extract_isin_and_per_share(desc)

      assert isin == "US00123Q1040"
      assert Decimal.equal?(per_share, Decimal.new("0.12"))
    end

    test "should handle Payment in Lieu description" do
      desc = "ORC(US68571X3017) Payment in Lieu of Dividend"
      {isin, _per_share} = IbkrActivityParser.extract_isin_and_per_share(desc)

      assert isin == "US68571X3017"
    end

    test "should return nil ISIN for Conid-only descriptions" do
      desc = "PTMN(510900095) Cash Dividend USD 0.07 per Share (Bonus Dividend)"
      {isin, _per_share} = IbkrActivityParser.extract_isin_and_per_share(desc)

      assert isin == nil
    end

    test "should extract per-share with high precision" do
      desc = "FFN(CA65685J3010) Cash Dividend CAD 0.11335 per Share (Ordinary Dividend)"
      {_isin, per_share} = IbkrActivityParser.extract_isin_and_per_share(desc)

      assert Decimal.equal?(per_share, Decimal.new("0.11335"))
    end
  end

  describe "Instrument schema" do
    test "should require ISIN" do
      changeset = Instrument.changeset(%Instrument{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).isin
    end

    test "should accept valid instrument" do
      attrs = %{isin: "FI0009000202", name: "Kesko B", asset_category: "Stocks"}
      changeset = Instrument.changeset(%Instrument{}, attrs)
      assert changeset.valid?
    end

    test "should persist instrument with all fields" do
      {:ok, instrument} =
        %Instrument{}
        |> Instrument.changeset(%{
          isin: "US00123Q1040",
          name: "AGNC INVESTMENT CORP",
          asset_category: "Stocks",
          listing_exchange: "NASDAQ",
          currency: "USD",
          type: "REIT",
          conid: 249_963_585
        })
        |> Repo.insert()

      assert instrument.isin == "US00123Q1040"
      assert instrument.conid == 249_963_585
    end

    test "should enforce unique ISIN" do
      attrs = %{isin: "FI0009000202", name: "Kesko B"}

      {:ok, _} =
        %Instrument{}
        |> Instrument.changeset(attrs)
        |> Repo.insert()

      {:error, changeset} =
        %Instrument{}
        |> Instrument.changeset(attrs)
        |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).isin
    end
  end

  describe "InstrumentAlias schema" do
    test "should require instrument_id and symbol" do
      changeset = InstrumentAlias.changeset(%InstrumentAlias{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).symbol
    end

    test "should persist alias with instrument" do
      {:ok, instrument} =
        %Instrument{}
        |> Instrument.changeset(%{isin: "FI0009000202", name: "Kesko B"})
        |> Repo.insert()

      {:ok, alias_record} =
        %InstrumentAlias{}
        |> InstrumentAlias.changeset(%{
          instrument_id: instrument.id,
          symbol: "KESKOB",
          exchange: "OMXH",
          source: "ibkr"
        })
        |> Repo.insert()

      assert alias_record.symbol == "KESKOB"
      assert alias_record.instrument_id == instrument.id
    end
  end

  describe "Trade schema" do
    setup do
      {:ok, instrument} =
        %Instrument{}
        |> Instrument.changeset(%{isin: "FI0009000202", name: "Kesko B"})
        |> Repo.insert()

      %{instrument: instrument}
    end

    test "should require essential fields", %{instrument: instrument} do
      changeset = Trade.changeset(%Trade{}, %{instrument_id: instrument.id})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).external_id
      assert "can't be blank" in errors_on(changeset).trade_date
    end

    test "should persist valid trade", %{instrument: instrument} do
      {:ok, trade} =
        %Trade{}
        |> Trade.changeset(%{
          external_id: "test-trade-001",
          instrument_id: instrument.id,
          trade_date: ~D[2026-01-08],
          quantity: Decimal.new("500"),
          price: Decimal.new("12.26"),
          amount: Decimal.new("-6130"),
          commission: Decimal.new("-5.52"),
          currency: "EUR"
        })
        |> Repo.insert()

      assert Decimal.equal?(trade.quantity, Decimal.new("500"))
      assert trade.currency == "EUR"
    end

    test "should enforce unique external_id", %{instrument: instrument} do
      attrs = %{
        external_id: "dedup-test-001",
        instrument_id: instrument.id,
        trade_date: ~D[2026-01-08],
        quantity: Decimal.new("100"),
        price: Decimal.new("10"),
        amount: Decimal.new("-1000"),
        currency: "EUR"
      }

      {:ok, _} = %Trade{} |> Trade.changeset(attrs) |> Repo.insert()
      {:error, changeset} = %Trade{} |> Trade.changeset(attrs) |> Repo.insert()
      assert "has already been taken" in errors_on(changeset).external_id
    end
  end

  describe "DividendPayment schema" do
    setup do
      {:ok, instrument} =
        %Instrument{}
        |> Instrument.changeset(%{isin: "FI0009000202", name: "Kesko B"})
        |> Repo.insert()

      %{instrument: instrument}
    end

    test "should persist paired dividend with WHT", %{instrument: instrument} do
      {:ok, dp} =
        %DividendPayment{}
        |> DividendPayment.changeset(%{
          external_id: "div-test-001",
          instrument_id: instrument.id,
          pay_date: ~D[2026-01-20],
          gross_amount: Decimal.new("220"),
          withholding_tax: Decimal.new("-77"),
          net_amount: Decimal.new("143"),
          currency: "EUR",
          per_share: Decimal.new("0.22")
        })
        |> Repo.insert()

      assert Decimal.equal?(dp.gross_amount, Decimal.new("220"))
      assert Decimal.equal?(dp.withholding_tax, Decimal.new("-77"))
      assert Decimal.equal?(dp.net_amount, Decimal.new("143"))
    end
  end

  describe "CashFlow schema" do
    test "should require essential fields" do
      changeset = CashFlow.changeset(%CashFlow{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).external_id
      assert "can't be blank" in errors_on(changeset).flow_type
    end

    test "should validate flow_type values" do
      changeset =
        CashFlow.changeset(%CashFlow{}, %{
          external_id: "cf-001",
          flow_type: "invalid_type",
          date: ~D[2026-01-01],
          amount: Decimal.new("100"),
          currency: "EUR"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).flow_type
    end

    test "should persist deposit" do
      {:ok, cf} =
        %CashFlow{}
        |> CashFlow.changeset(%{
          external_id: "cf-deposit-001",
          flow_type: "deposit",
          date: ~D[2026-01-01],
          amount: Decimal.new("5000"),
          currency: "EUR"
        })
        |> Repo.insert()

      assert cf.flow_type == "deposit"
      assert Decimal.equal?(cf.amount, Decimal.new("5000"))
    end

    test "should persist interest" do
      {:ok, cf} =
        %CashFlow{}
        |> CashFlow.changeset(%{
          external_id: "cf-interest-001",
          flow_type: "interest",
          date: ~D[2026-01-06],
          amount: Decimal.new("-293.45"),
          currency: "EUR",
          description: "EUR Debit Interest for Dec-2025"
        })
        |> Repo.insert()

      assert cf.flow_type == "interest"
    end
  end

  describe "import_file/1 integration" do
    @tag :integration
    test "should import a small test CSV" do
      # Create a minimal test CSV
      csv_content = """
      Statement,Header,Field Name,Field Value
      Statement,Data,Title,Activity Statement
      Financial Instrument Information,Header,Asset Category,Symbol,Description,Conid,Security ID,Underlying,Listing Exch,Multiplier,Type,Code
      Financial Instrument Information,Data,Stocks,TEST,TEST CORP,12345,US1234567890,TEST,NYSE,1,COMMON,
      Dividends,Header,Currency,Date,Description,Amount
      Dividends,Data,USD,2026-01-15,TEST(US1234567890) Cash Dividend USD 0.50 per Share (Ordinary Dividend),500
      Withholding Tax,Header,Currency,Date,Description,Amount,Code
      Withholding Tax,Data,USD,2026-01-15,TEST(US1234567890) Cash Dividend USD 0.50 per Share - US Tax,-75,
      Interest,Header,Currency,Date,Description,Amount
      Interest,Data,EUR,2026-01-06,EUR Debit Interest for Dec-2025,-100.50
      Deposits & Withdrawals,Header,Currency,Settle Date,Description,Amount
      Deposits & Withdrawals,Data,EUR,2026-01-02,Electronic Fund Transfer,5000
      """

      path = Path.join(System.tmp_dir!(), "test_activity.csv")
      File.write!(path, csv_content)

      _result = IbkrActivityParser.import_file(path)

      # Verify instrument was created
      assert Repo.aggregate(Instrument, :count) == 1
      instrument = Repo.get_by!(Instrument, isin: "US1234567890")
      assert instrument.name == "TEST CORP"

      # Verify alias
      assert Repo.aggregate(InstrumentAlias, :count) == 1

      # Verify dividend with paired WHT
      assert Repo.aggregate(DividendPayment, :count) == 1
      dp = Repo.one!(DividendPayment)
      assert Decimal.equal?(dp.gross_amount, Decimal.new("500"))
      assert Decimal.equal?(dp.withholding_tax, Decimal.new("-75"))
      assert Decimal.equal?(dp.net_amount, Decimal.new("425"))

      # Verify interest
      interest_count =
        Repo.one(from c in CashFlow, where: c.flow_type == "interest", select: count(c.id))

      assert interest_count == 1

      # Verify deposit
      deposit_count =
        Repo.one(from c in CashFlow, where: c.flow_type == "deposit", select: count(c.id))

      assert deposit_count == 1

      File.rm!(path)
    end

    @tag :integration
    test "should deduplicate on re-import" do
      csv_content = """
      Financial Instrument Information,Header,Asset Category,Symbol,Description,Conid,Security ID,Underlying,Listing Exch,Multiplier,Type,Code
      Financial Instrument Information,Data,Stocks,DEDUP,DEDUP CORP,99999,US9999999999,DEDUP,NYSE,1,COMMON,
      Dividends,Header,Currency,Date,Description,Amount
      Dividends,Data,USD,2026-02-01,DEDUP(US9999999999) Cash Dividend USD 1.00 per Share (Ordinary Dividend),1000
      """

      path = Path.join(System.tmp_dir!(), "test_dedup.csv")
      File.write!(path, csv_content)

      # First import
      IbkrActivityParser.import_file(path)
      assert Repo.aggregate(DividendPayment, :count) == 1

      # Second import — should skip duplicate
      IbkrActivityParser.import_file(path)
      assert Repo.aggregate(DividendPayment, :count) == 1

      File.rm!(path)
    end
  end
end
