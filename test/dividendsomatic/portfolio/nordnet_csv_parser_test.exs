defmodule Dividendsomatic.Portfolio.NordnetCsvParserTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.Portfolio.NordnetCsvParser

  # Tab-separated UTF-8 test data (after BOM stripping)
  @header "Id\tKirjauspäivä\tKauppapäivä\tMaksupäivä\tSalkku\tTapahtumatyyppi\tArvopaperi\tISIN\tMäärä\tKurssi\tKorko\tKokonaiskulut\tValuutta\tSumma\tValuutta\tHankinta-arvo\tValuutta\tTulos\tValuutta\tKokonaismäärä\tSaldo\tVaihtokurssi\tTapahtumateksti\tMitätöintipäivä\tLaskelma\tVahvistusnumero\tVälityspalkkio\tValuutta\tViitevaluuttakurssi\tAlkuperäinen korko"

  defp build_csv(rows) do
    [@header | rows] |> Enum.join("\n")
  end

  describe "parse/1" do
    test "should parse a buy (OSTO) transaction" do
      csv =
        build_csv([
          "373251051\t2017-03-06\t2017-03-06\t2017-03-08\t16874679\tOSTO\tiShares Core\tIE00BKM4GZ66\t20\t22,58\t0\t15\tEUR\t-466,6\tEUR\t466,6\tEUR\t0\tEUR\t20\t533,4\t\t\t\t558941819\t558941819\t15\tEUR\t\t"
        ])

      {:ok, [txn]} = NordnetCsvParser.parse(csv)

      assert txn.external_id == "373251051"
      assert txn.broker == "nordnet"
      assert txn.transaction_type == "buy"
      assert txn.raw_type == "OSTO"
      assert txn.trade_date == ~D[2017-03-06]
      assert txn.settlement_date == ~D[2017-03-08]
      assert txn.security_name == "iShares Core"
      assert txn.isin == "IE00BKM4GZ66"
      assert Decimal.equal?(txn.quantity, Decimal.new("20"))
      assert Decimal.equal?(txn.price, Decimal.new("22.58"))
      assert Decimal.equal?(txn.commission, Decimal.new("15"))
      assert txn.currency == "EUR"
    end

    test "should parse a sell (MYYNTI) transaction" do
      csv =
        build_csv([
          "383899883\t2017-04-21\t2017-04-21\t2017-04-25\t16874679\tMYYNTI\tXtrackers MSCI\tLU0592217524\t30\t7,17\t0\t15\tEUR\t200,1\tEUR\t\tEUR\t-29,8499\tEUR\t0\t232,21\t\t\t\t562455212\t562455212\t15\tEUR\t\t"
        ])

      {:ok, [txn]} = NordnetCsvParser.parse(csv)

      assert txn.transaction_type == "sell"
      assert txn.raw_type == "MYYNTI"
      assert Decimal.equal?(txn.quantity, Decimal.new("30"))
      assert Decimal.equal?(txn.price, Decimal.new("7.17"))
      assert Decimal.equal?(txn.result, Decimal.new("-29.8499"))
    end

    test "should parse a dividend (OSINKO) transaction" do
      csv =
        build_csv([
          "379618893\t2017-04-03\t2017-03-17\t2017-04-04\t16874679\tOSINKO\tYIT Corporation\tFI0009800643\t20\t0,22\t\t\t\t4,4\tEUR\t\t\t\t\t0\t26,22\t\tVOPR OSINKO YTY1V 0,22 EUR/OSAKE\t\t\t217741667\t\t\t\t"
        ])

      {:ok, [txn]} = NordnetCsvParser.parse(csv)

      assert txn.transaction_type == "dividend"
      assert txn.raw_type == "OSINKO"
      assert txn.security_name == "YIT Corporation"
      assert txn.isin == "FI0009800643"
      assert Decimal.equal?(txn.price, Decimal.new("0.22"))
      assert Decimal.equal?(txn.amount, Decimal.new("4.4"))
      assert txn.confirmation_number == "217741667"
    end

    test "should parse withholding tax (ENNAKKOPIDÄTYS)" do
      csv =
        build_csv([
          "379618895\t2017-04-03\t2017-03-17\t2017-04-04\t16874679\tENNAKKOPIDÄTYS\tYIT Corporation\tFI0009800643\t20\t\t\t\t\t-1,12\tEUR\t\t\t\t\t0\t25,1\t\tVOPR OSINKO YTY1V 0,22 EUR/OSAKE\t\t\t217741667\t\t\t\t"
        ])

      {:ok, [txn]} = NordnetCsvParser.parse(csv)

      assert txn.transaction_type == "withholding_tax"
      assert txn.confirmation_number == "217741667"
      assert Decimal.equal?(txn.amount, Decimal.new("-1.12"))
    end

    test "should parse deposit (TALLETUS)" do
      csv =
        build_csv([
          "372946430\t2017-03-06\t2017-03-04\t2017-03-04\t16874679\tTALLETUS\t\t\t\t\t\t\t\t700\tEUR\t\t\t\t\t\t700\t\tTALLETUS REAL-TIME\t\t\t217330260\t\t\t\t"
        ])

      {:ok, [txn]} = NordnetCsvParser.parse(csv)

      assert txn.transaction_type == "deposit"
      assert Decimal.equal?(txn.amount, Decimal.new("700"))
      assert txn.security_name == nil
      assert txn.isin == nil
    end

    test "should parse loan interest (LAINAKORKO)" do
      csv =
        build_csv([
          "999\t2018-01-02\t2018-01-02\t2018-01-02\t16874679\tLAINAKORKO\t\t\t\t\t\t\t\t-5,50\tEUR\t\t\t\t\t\t100\t\tLAINAKORKO\t\t\t12345\t\t\t\t"
        ])

      {:ok, [txn]} = NordnetCsvParser.parse(csv)

      assert txn.transaction_type == "loan_interest"
    end

    test "should parse FX buy (VALUUTAN OSTO)" do
      csv =
        build_csv([
          "888\t2018-01-02\t2018-01-02\t2018-01-02\t16874679\tVALUUTAN OSTO\t\t\t\t\t\t\t\t100\tUSD\t\t\t\t\t\t100\t1,2\tVALUUTAN OSTO\t\t\t12346\t\t\t\t"
        ])

      {:ok, [txn]} = NordnetCsvParser.parse(csv)

      assert txn.transaction_type == "fx_buy"
    end

    test "should parse corporate actions as corporate_action" do
      for type <- ["VAIHTO AP-JÄTTÖ", "POISTO AP OTTO", "MERKINTÄ AP JÄTTÖ", "AP OTTO"] do
        csv =
          build_csv([
            "777\t2018-01-02\t2018-01-02\t2018-01-02\t16874679\t#{type}\tSome Stock\tFI123\t10\t\t\t\t\t\tEUR\t\t\t\t\t10\t100\t\t#{type}\t\t\t12347\t\t\t\t"
          ])

        {:ok, [txn]} = NordnetCsvParser.parse(csv)
        assert txn.transaction_type == "corporate_action", "Expected corporate_action for #{type}"
      end
    end

    test "should handle multiple rows" do
      csv =
        build_csv([
          "1\t2017-03-06\t2017-03-06\t2017-03-08\t16874679\tTALLETUS\t\t\t\t\t\t\t\t700\tEUR\t\t\t\t\t\t700\t\t\t\t\t217330260\t\t\t\t",
          "2\t2017-03-06\t2017-03-06\t2017-03-08\t16874679\tOSTO\tiShares\tIE00BKM4GZ66\t20\t22,58\t0\t15\tEUR\t-466,6\tEUR\t466,6\tEUR\t0\tEUR\t20\t533,4\t\t\t\t558941819\t558941819\t15\tEUR\t\t"
        ])

      {:ok, txns} = NordnetCsvParser.parse(csv)
      assert length(txns) == 2
    end

    test "should return empty list for header-only CSV" do
      {:ok, txns} = NordnetCsvParser.parse(@header)
      assert txns == []
    end

    test "should handle empty fields as nil" do
      csv =
        build_csv([
          "1\t2017-03-06\t2017-03-06\t\t16874679\tTALLETUS\t\t\t\t\t\t\t\t700\tEUR\t\t\t\t\t\t700\t\t\t\t\t217330260\t\t\t\t"
        ])

      {:ok, [txn]} = NordnetCsvParser.parse(csv)

      assert txn.settlement_date == nil
      assert txn.security_name == nil
      assert txn.isin == nil
      assert txn.quantity == nil
      assert txn.price == nil
    end
  end

  describe "decode_to_utf8/1" do
    test "should convert UTF-16LE with BOM to UTF-8" do
      # UTF-16LE BOM + "Hi"
      utf16 = <<0xFF, 0xFE, 0x48, 0x00, 0x69, 0x00>>
      assert NordnetCsvParser.decode_to_utf8(utf16) == "Hi"
    end

    test "should pass through UTF-8 unchanged" do
      assert NordnetCsvParser.decode_to_utf8("Hello") == "Hello"
    end
  end

  describe "parse_decimal/1" do
    test "should parse comma-separated decimal" do
      assert Decimal.equal?(NordnetCsvParser.parse_decimal("22,58"), Decimal.new("22.58"))
    end

    test "should parse negative decimal" do
      assert Decimal.equal?(NordnetCsvParser.parse_decimal("-466,6"), Decimal.new("-466.6"))
    end

    test "should parse integer" do
      assert Decimal.equal?(NordnetCsvParser.parse_decimal("700"), Decimal.new("700"))
    end

    test "should return nil for empty string" do
      assert NordnetCsvParser.parse_decimal("") == nil
    end

    test "should return nil for nil" do
      assert NordnetCsvParser.parse_decimal(nil) == nil
    end
  end

  describe "normalize_type/1" do
    test "should normalize all known types" do
      assert NordnetCsvParser.normalize_type("OSTO") == "buy"
      assert NordnetCsvParser.normalize_type("MYYNTI") == "sell"
      assert NordnetCsvParser.normalize_type("OSINKO") == "dividend"
      assert NordnetCsvParser.normalize_type("ENNAKKOPIDÄTYS") == "withholding_tax"
      assert NordnetCsvParser.normalize_type("ULKOM. KUPONKIVERO") == "foreign_tax"
      assert NordnetCsvParser.normalize_type("TALLETUS") == "deposit"
      assert NordnetCsvParser.normalize_type("NOSTO") == "withdrawal"
      assert NordnetCsvParser.normalize_type("VALUUTAN OSTO") == "fx_buy"
      assert NordnetCsvParser.normalize_type("VALUUTAN MYYNTI") == "fx_sell"
      assert NordnetCsvParser.normalize_type("LAINAKORKO") == "loan_interest"
      assert NordnetCsvParser.normalize_type("PÄÄOMIT YLIT.KORKO") == "capital_interest"
      assert NordnetCsvParser.normalize_type("DEBET KORON KORJ.") == "interest_correction"
    end

    test "should normalize corporate actions" do
      assert NordnetCsvParser.normalize_type("VAIHTO AP-JÄTTÖ") == "corporate_action"
      assert NordnetCsvParser.normalize_type("POISTO AP OTTO") == "corporate_action"
    end
  end

  describe "parse_file/1" do
    test "should return error for nonexistent file" do
      assert {:error, _} = NordnetCsvParser.parse_file("/nonexistent/file.csv")
    end
  end
end
