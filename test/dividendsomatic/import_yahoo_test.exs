defmodule Dividendsomatic.ImportYahooTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Portfolio
  alias Mix.Tasks.Import.Yahoo, as: ImportYahoo

  @test_dir "tmp/test_yahoo_import"

  setup do
    File.mkdir_p!(Path.join(@test_dir, "dividends"))

    on_exit(fn ->
      File.rm_rf!(@test_dir)
    end)

    :ok
  end

  describe "import.yahoo dividends" do
    test "should import valid dividend JSON" do
      json_data = [
        %{
          "symbol" => "TESTCO",
          "yahoo_symbol" => "TESTCO.HE",
          "exchange" => "HEX",
          "isin" => "FI0009000001",
          "ex_date" => "2026-01-15",
          "amount" => 0.50,
          "currency" => "EUR"
        },
        %{
          "symbol" => "TESTCO",
          "yahoo_symbol" => "TESTCO.HE",
          "exchange" => "HEX",
          "isin" => "FI0009000001",
          "ex_date" => "2025-07-15",
          "amount" => 0.45,
          "currency" => "EUR"
        }
      ]

      path = Path.join([@test_dir, "dividends", "TESTCO.HE.json"])
      File.write!(path, Jason.encode!(json_data))

      # Import the file
      dividends_before = length(Portfolio.list_dividends())
      ImportYahoo.run(["dividends", path])
      dividends_after = length(Portfolio.list_dividends())

      assert dividends_after == dividends_before + 2
    end

    test "should skip duplicate dividends" do
      json_data = [
        %{
          "symbol" => "DUPL",
          "ex_date" => "2026-01-20",
          "amount" => 1.0,
          "currency" => "USD"
        }
      ]

      path = Path.join([@test_dir, "dividends", "DUPL.json"])
      File.write!(path, Jason.encode!(json_data))

      ImportYahoo.run(["dividends", path])
      count1 = length(Portfolio.list_dividends())

      # Import again - should skip
      ImportYahoo.run(["dividends", path])
      count2 = length(Portfolio.list_dividends())

      assert count2 == count1
    end
  end
end
