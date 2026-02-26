defmodule DividendsomaticWeb.Helpers.FormatHelpers do
  @moduledoc """
  Shared formatting helpers for currency, numbers, and P&L display.
  """

  def format_decimal(nil), do: "0.00"

  def format_decimal(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  def format_integer(nil), do: "0"

  def format_integer(decimal) do
    decimal
    |> Decimal.round(0)
    |> Decimal.to_integer()
    |> Integer.to_string()
    |> add_thousands_separator()
  end

  def format_euro(nil), do: "0 €"

  def format_euro(decimal) do
    integer_part =
      decimal
      |> Decimal.round(0)
      |> Decimal.to_integer()
      |> Integer.to_string()
      |> add_thousands_separator("\u00A0")

    "#{integer_part} €"
  end

  def format_euro_decimal(nil), do: "0,00 €"

  def format_euro_decimal(decimal) do
    format_euro_number(decimal, "")
  end

  def format_euro_signed(nil), do: "0,00 €"

  def format_euro_signed(decimal) do
    sign =
      cond do
        Decimal.compare(decimal, Decimal.new("0")) == :gt -> "+"
        Decimal.compare(decimal, Decimal.new("0")) == :lt -> "-"
        true -> ""
      end

    format_euro_number(decimal, sign)
  end

  def frequency_label(:monthly), do: "M"
  def frequency_label(:quarterly), do: "Q"
  def frequency_label(:semi_annual), do: "S"
  def frequency_label(:annual), do: "A"
  def frequency_label(:irregular), do: "IR"
  def frequency_label(_), do: "?"

  def frequency_title(:monthly), do: "Monthly (12×/yr)"
  def frequency_title(:quarterly), do: "Quarterly (4×/yr)"
  def frequency_title(:semi_annual), do: "Semi-annual (2×/yr)"
  def frequency_title(:annual), do: "Annual (1×/yr)"
  def frequency_title(:irregular), do: "Irregular schedule"
  def frequency_title(_), do: "Unknown frequency"

  def pnl_badge_class(pnl) do
    pnl = pnl || Decimal.new("0")

    cond do
      Decimal.compare(pnl, Decimal.new("0")) == :gt -> "terminal-gain"
      Decimal.compare(pnl, Decimal.new("0")) == :lt -> "terminal-loss"
      true -> ""
    end
  end

  def pnl_positive?(pnl) do
    Decimal.compare(pnl || Decimal.new("0"), Decimal.new("0")) != :lt
  end

  def add_thousands_separator(str, sep \\ ",") do
    str
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(sep)
    |> String.reverse()
  end

  defp format_euro_number(decimal, sign) do
    abs_val = Decimal.abs(Decimal.round(decimal, 2))

    int_part =
      abs_val
      |> Decimal.round(0, :floor)
      |> Decimal.to_integer()

    frac =
      abs_val
      |> Decimal.sub(Decimal.new(int_part))
      |> Decimal.mult(Decimal.new(100))
      |> Decimal.round(0)
      |> Decimal.to_integer()

    formatted_int =
      int_part
      |> Integer.to_string()
      |> add_thousands_separator("\u00A0")

    "#{sign}#{formatted_int},#{String.pad_leading(Integer.to_string(frac), 2, "0")} €"
  end
end
