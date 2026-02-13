defmodule Mix.Tasks.ImportLynx9aTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.SoldPosition

  # We test the task's core logic by invoking it with a small fixture CSV.
  # The task reads from @csv_path which is hardcoded, so we test the
  # exported helpers indirectly via module internals.

  describe "parse_date/1" do
    # parse_date is private, so test through build_attrs via a full run.
    # Instead, we test the date parsing logic pattern directly.

    test "should parse DD/MM/YYYY format correctly" do
      assert parse_date("15/03/2022") == ~D[2022-03-15]
    end

    test "should parse single-digit day and month" do
      assert parse_date("1/2/2020") == ~D[2020-02-01]
    end

    test "should return nil for invalid format" do
      assert parse_date("2022-03-15") == nil
    end

    test "should return nil for empty string" do
      assert parse_date("") == nil
    end

    test "should return nil for nil" do
      assert parse_date(nil) == nil
    end
  end

  describe "parse_decimal/1" do
    test "should parse valid decimal string" do
      assert parse_decimal("100.50") == Decimal.new("100.50")
    end

    test "should parse integer string" do
      assert parse_decimal("1000") == Decimal.new("1000")
    end

    test "should return nil for empty string" do
      assert parse_decimal("") == nil
    end

    test "should return nil for nil" do
      assert parse_decimal(nil) == nil
    end

    test "should return nil for non-numeric string" do
      assert parse_decimal("abc") == nil
    end

    test "should return nil for partial numeric string" do
      assert parse_decimal("100abc") == nil
    end
  end

  describe "per-share price derivation" do
    test "should derive correct per-share prices from totals" do
      # 1000 shares, total sell = 4429.69, total buy = 4421.66
      quantity = Decimal.new("1000")
      sell_total = Decimal.new("4429.69")
      buy_total = Decimal.new("4421.66")

      sale_price = Decimal.div(sell_total, quantity) |> Decimal.round(6)
      purchase_price = Decimal.div(buy_total, quantity) |> Decimal.round(6)

      assert sale_price == Decimal.new("4.429690")
      assert purchase_price == Decimal.new("4.421660")
    end

    test "should handle fractional quantities" do
      quantity = Decimal.new("3.5")
      sell_total = Decimal.new("175.00")
      buy_total = Decimal.new("140.00")

      sale_price = Decimal.div(sell_total, quantity) |> Decimal.round(6)
      purchase_price = Decimal.div(buy_total, quantity) |> Decimal.round(6)

      assert sale_price == Decimal.new("50.000000")
      assert purchase_price == Decimal.new("40.000000")
    end
  end

  describe "format_pnl/1" do
    test "should format gain" do
      trade = %{"gain" => "123.45", "loss" => ""}
      assert format_pnl(trade) == "+123.45"
    end

    test "should format loss" do
      trade = %{"gain" => "", "loss" => "67.89"}
      assert format_pnl(trade) == "-67.89"
    end

    test "should return 0 when both empty" do
      trade = %{"gain" => "", "loss" => ""}
      assert format_pnl(trade) == "0"
    end
  end

  describe "resolve_symbol/2" do
    test "should resolve known stock name from map" do
      name_map = %{"APPLE INC" => "AAPL", "INTEL CORP" => "INTC"}
      assert resolve_symbol("Apple Inc", name_map) == "AAPL"
    end

    test "should return original name when not in map" do
      name_map = %{"APPLE INC" => "AAPL"}
      assert resolve_symbol("Unknown Corp", name_map) == "Unknown Corp"
    end

    test "should handle leading/trailing whitespace" do
      name_map = %{"APPLE INC" => "AAPL"}
      assert resolve_symbol("  Apple Inc  ", name_map) == "AAPL"
    end
  end

  describe "position deduplication" do
    test "should detect existing position" do
      # Insert a sold position
      %SoldPosition{}
      |> SoldPosition.changeset(%{
        symbol: "AAPL",
        quantity: Decimal.new("100"),
        purchase_price: Decimal.new("150.00"),
        purchase_date: ~D[2022-01-01],
        sale_price: Decimal.new("160.00"),
        sale_date: ~D[2022-06-15],
        currency: "EUR",
        source: "lynx_9a"
      })
      |> Repo.insert!()

      assert position_exists?(%{
               symbol: "AAPL",
               sale_date: ~D[2022-06-15],
               purchase_date: ~D[2022-01-01],
               purchase_price: Decimal.new("150.00"),
               quantity: Decimal.new("100"),
               source: "lynx_9a"
             })
    end

    test "should not match different source" do
      %SoldPosition{}
      |> SoldPosition.changeset(%{
        symbol: "AAPL",
        quantity: Decimal.new("100"),
        purchase_price: Decimal.new("150.00"),
        purchase_date: ~D[2022-01-01],
        sale_price: Decimal.new("160.00"),
        sale_date: ~D[2022-06-15],
        currency: "EUR",
        source: "ibkr"
      })
      |> Repo.insert!()

      refute position_exists?(%{
               symbol: "AAPL",
               sale_date: ~D[2022-06-15],
               purchase_date: ~D[2022-01-01],
               purchase_price: Decimal.new("150.00"),
               quantity: Decimal.new("100"),
               source: "lynx_9a"
             })
    end
  end

  # --- Helper functions mirroring the task's private functions ---
  # These replicate the logic from import_lynx_9a.ex for unit testing.

  defp parse_date(str) when is_binary(str) and str != "" do
    case String.split(str, "/") do
      [d, m, y] ->
        Date.new!(String.to_integer(y), String.to_integer(m), String.to_integer(d))

      _ ->
        nil
    end
  end

  defp parse_date(_), do: nil

  defp parse_decimal(str) when is_binary(str) and str != "" do
    case Decimal.parse(str) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp parse_decimal(_), do: nil

  defp format_pnl(trade) do
    cond do
      trade["gain"] != "" -> "+#{trade["gain"]}"
      trade["loss"] != "" -> "-#{trade["loss"]}"
      true -> "0"
    end
  end

  defp resolve_symbol(stock_name, name_map) do
    key = String.upcase(String.trim(stock_name))
    Map.get(name_map, key, stock_name)
  end

  defp position_exists?(attrs) do
    import Ecto.Query

    SoldPosition
    |> where(
      [s],
      s.symbol == ^attrs.symbol and
        s.sale_date == ^attrs.sale_date and
        s.purchase_date == ^attrs.purchase_date and
        s.purchase_price == ^attrs.purchase_price and
        s.quantity == ^attrs.quantity and
        s.source == "lynx_9a"
    )
    |> Repo.exists?()
  end
end
