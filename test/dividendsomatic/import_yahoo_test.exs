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

  describe "import.yahoo dividends (legacy)" do
    test "should handle legacy disabled import gracefully" do
      json_data = [
        %{
          "symbol" => "TESTCO",
          "yahoo_symbol" => "TESTCO.HE",
          "exchange" => "HEX",
          "isin" => "FI0009000001",
          "ex_date" => "2026-01-15",
          "amount" => 0.50,
          "currency" => "EUR"
        }
      ]

      path = Path.join([@test_dir, "dividends", "TESTCO.HE.json"])
      File.write!(path, Jason.encode!(json_data))

      # Yahoo import is legacy — create_dividend returns error, so no dividends are created
      dividends_before = length(Portfolio.list_dividends())
      ImportYahoo.run(["dividends", path])
      dividends_after = length(Portfolio.list_dividends())

      # No new dividends since create_dividend is disabled
      assert dividends_after == dividends_before
    end
  end
end
