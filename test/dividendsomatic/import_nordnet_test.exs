defmodule Dividendsomatic.ImportNordnetTest do
  use Dividendsomatic.DataCase, async: false

  alias Dividendsomatic.Portfolio.{BrokerTransaction, Cost, Dividend, SoldPosition}
  alias Mix.Tasks.Import.Nordnet, as: ImportNordnet

  @header "Id\tKirjauspäivä\tKauppapäivä\tMaksupäivä\tSalkku\tTapahtumatyyppi\tArvopaperi\tISIN\tMäärä\tKurssi\tKorko\tKokonaiskulut\tValuutta\tSumma\tValuutta\tHankinta-arvo\tValuutta\tTulos\tValuutta\tKokonaismäärä\tSaldo\tVaihtokurssi\tTapahtumateksti\tMitätöintipäivä\tLaskelma\tVahvistusnumero\tVälityspalkkio\tValuutta\tViitevaluuttakurssi\tAlkuperäinen korko"

  @fixture_csv """
  #{@header}
  1\t2017-03-06\t2017-03-06\t2017-03-06\t1234\tTALLETUS\t\t\t\t\t\t\t\t1000\tEUR\t\t\t\t\t\t1000\t\tTALLETUS\t\t\t111\t\t\t\t
  2\t2017-03-06\t2017-03-06\t2017-03-08\t1234\tOSTO\tTest Corp\tFI001\t50\t10,00\t0\t9\tEUR\t-509\tEUR\t509\tEUR\t0\tEUR\t50\t491\t\t\t\t222\t222\t9\tEUR\t\t
  3\t2017-06-15\t2017-06-15\t2017-06-15\t1234\tOSINKO\tTest Corp\tFI001\t50\t0,50\t\t\t\t25\tEUR\t\t\t\t\t50\t516\t\tDIV\t\t\t333\t\t\t\t
  4\t2017-06-15\t2017-06-15\t2017-06-15\t1234\tENNAKKOPIDÄTYS\tTest Corp\tFI001\t50\t\t\t\t\t-7,50\tEUR\t\t\t\t\t50\t508,50\t\tDIV\t\t\t333\t\t\t\t
  5\t2017-09-01\t2017-09-01\t2017-09-03\t1234\tMYYNTI\tTest Corp\tFI001\t25\t12,00\t0\t9\tEUR\t291\tEUR\t\tEUR\t41\tEUR\t25\t799,50\t\t\t\t444\t444\t9\tEUR\t\t
  6\t2018-01-02\t2018-01-02\t2018-01-02\t1234\tLAINAKORKO\t\t\t\t\t\t\t\t-3,25\tEUR\t\t\t\t\t\t796,25\t\tLAINAKORKO\t\t\t555\t\t\t\t
  """

  setup do
    # Write fixture CSV to temp file
    dir = System.tmp_dir!()
    path = Path.join(dir, "test_nordnet_#{System.unique_integer([:positive])}.csv")
    File.write!(path, @fixture_csv)

    on_exit(fn -> File.rm(path) end)
    %{csv_path: path}
  end

  describe "full import pipeline" do
    test "should import transactions, derive dividends, sold positions, and costs", %{
      csv_path: path
    } do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          ImportNordnet.run([path])
        end)

      assert output =~ "Parsed"
      assert output =~ "transactions"

      # Verify broker_transactions
      txns = Repo.all(BrokerTransaction)
      assert length(txns) == 6

      types = Enum.map(txns, & &1.transaction_type) |> Enum.sort()
      assert "buy" in types
      assert "sell" in types
      assert "dividend" in types
      assert "withholding_tax" in types
      assert "deposit" in types
      assert "loan_interest" in types

      # Verify derived dividends
      dividends = Repo.all(Dividend)
      assert length(dividends) == 1
      div = hd(dividends)
      assert div.symbol == "Test Corp"
      assert div.isin == "FI001"

      # Verify sold positions
      sold = Repo.all(SoldPosition)
      assert length(sold) == 1
      sp = hd(sold)
      assert sp.symbol == "Test Corp"
      assert sp.source == "nordnet"

      # Verify costs (commission from buy + commission from sell + withholding_tax + loan_interest)
      costs = Repo.all(Cost)
      cost_types = Enum.map(costs, & &1.cost_type) |> Enum.sort()
      assert "commission" in cost_types
      assert "withholding_tax" in cost_types
      assert "loan_interest" in cost_types
    end

    test "should be idempotent on re-import", %{csv_path: path} do
      ExUnit.CaptureIO.capture_io(fn ->
        ImportNordnet.run([path])
      end)

      txn_count_1 = Repo.aggregate(BrokerTransaction, :count)
      div_count_1 = Repo.aggregate(Dividend, :count)

      ExUnit.CaptureIO.capture_io(fn ->
        ImportNordnet.run([path])
      end)

      assert Repo.aggregate(BrokerTransaction, :count) == txn_count_1
      assert Repo.aggregate(Dividend, :count) == div_count_1
    end
  end
end
