defmodule Dividendsomatic.Portfolio.DividendAnalyticsTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.Portfolio.DividendAnalytics

  describe "compute_annual_dividend_per_share/1" do
    test "should return zero for empty list" do
      assert DividendAnalytics.compute_annual_dividend_per_share([]) == Decimal.new("0")
    end

    test "should sum per-share amounts from last 12 months" do
      today = Date.utc_today()

      divs = [
        %{
          dividend: %{
            ex_date: Date.add(today, -90),
            amount: Decimal.new("0.50"),
            amount_type: "per_share",
            gross_rate: nil,
            quantity_at_record: nil
          },
          income: Decimal.new("500")
        },
        %{
          dividend: %{
            ex_date: Date.add(today, -180),
            amount: Decimal.new("0.50"),
            amount_type: "per_share",
            gross_rate: nil,
            quantity_at_record: nil
          },
          income: Decimal.new("500")
        }
      ]

      result = DividendAnalytics.compute_annual_dividend_per_share(divs)
      assert Decimal.equal?(result, Decimal.new("1.00"))
    end

    test "should exclude dividends older than 365 days" do
      today = Date.utc_today()

      divs = [
        %{
          dividend: %{
            ex_date: Date.add(today, -90),
            amount: Decimal.new("0.50"),
            amount_type: "per_share",
            gross_rate: nil,
            quantity_at_record: nil
          },
          income: Decimal.new("500")
        },
        %{
          dividend: %{
            ex_date: Date.add(today, -400),
            amount: Decimal.new("0.50"),
            amount_type: "per_share",
            gross_rate: nil,
            quantity_at_record: nil
          },
          income: Decimal.new("500")
        }
      ]

      result = DividendAnalytics.compute_annual_dividend_per_share(divs)
      assert Decimal.equal?(result, Decimal.new("0.50"))
    end
  end

  describe "compute_dividend_yield/2" do
    test "should return nil when quote_data is nil" do
      assert DividendAnalytics.compute_dividend_yield(Decimal.new("1.00"), nil) == nil
    end

    test "should compute yield as annual_per_share / price * 100" do
      quote_data = %{current_price: Decimal.new("20.00")}
      result = DividendAnalytics.compute_dividend_yield(Decimal.new("1.00"), quote_data)
      assert Decimal.equal?(result, Decimal.new("5.00"))
    end

    test "should return nil when price is zero" do
      quote_data = %{current_price: Decimal.new("0")}
      assert DividendAnalytics.compute_dividend_yield(Decimal.new("1.00"), quote_data) == nil
    end
  end

  describe "compute_yield_on_cost/2" do
    test "should return nil when holding_stats is nil" do
      assert DividendAnalytics.compute_yield_on_cost(Decimal.new("1.00"), nil) == nil
    end

    test "should compute yield on cost as annual_per_share / avg_cost * 100" do
      stats = %{avg_cost: Decimal.new("10.00")}
      result = DividendAnalytics.compute_yield_on_cost(Decimal.new("0.50"), stats)
      assert Decimal.equal?(result, Decimal.new("5.00"))
    end

    test "should return nil when avg_cost is zero" do
      stats = %{avg_cost: Decimal.new("0")}
      assert DividendAnalytics.compute_yield_on_cost(Decimal.new("1.00"), stats) == nil
    end
  end

  describe "detect_dividend_frequency/1" do
    test "should return unknown for fewer than 2 dividends" do
      assert DividendAnalytics.detect_dividend_frequency([]) == "unknown"

      assert DividendAnalytics.detect_dividend_frequency([
               %{dividend: %{ex_date: ~D[2025-06-01]}}
             ]) == "unknown"
    end

    test "should detect monthly frequency" do
      divs =
        for m <- 1..4 do
          %{dividend: %{ex_date: Date.new!(2025, m, 15)}}
        end

      assert DividendAnalytics.detect_dividend_frequency(divs) == "monthly"
    end

    test "should detect quarterly frequency" do
      divs = [
        %{dividend: %{ex_date: ~D[2025-03-15]}},
        %{dividend: %{ex_date: ~D[2025-06-15]}},
        %{dividend: %{ex_date: ~D[2025-09-15]}},
        %{dividend: %{ex_date: ~D[2025-12-15]}}
      ]

      assert DividendAnalytics.detect_dividend_frequency(divs) == "quarterly"
    end

    test "should detect annual frequency" do
      divs = [
        %{dividend: %{ex_date: ~D[2024-06-01]}},
        %{dividend: %{ex_date: ~D[2025-06-01]}}
      ]

      assert DividendAnalytics.detect_dividend_frequency(divs) == "annual"
    end
  end

  describe "per_share_amount/1" do
    test "should return amount directly for per_share type" do
      div = %{
        amount: Decimal.new("0.50"),
        amount_type: "per_share",
        gross_rate: nil,
        quantity_at_record: nil
      }

      assert Decimal.equal?(DividendAnalytics.per_share_amount(div), Decimal.new("0.50"))
    end

    test "should use gross_rate for total_net type when available" do
      div = %{
        amount: Decimal.new("500"),
        amount_type: "total_net",
        gross_rate: Decimal.new("0.60"),
        quantity_at_record: Decimal.new("1000")
      }

      assert Decimal.equal?(DividendAnalytics.per_share_amount(div), Decimal.new("0.60"))
    end

    test "should compute per-share from total_net / quantity_at_record" do
      div = %{
        amount: Decimal.new("500"),
        amount_type: "total_net",
        gross_rate: nil,
        quantity_at_record: Decimal.new("1000")
      }

      assert Decimal.equal?(DividendAnalytics.per_share_amount(div), Decimal.new("0.5"))
    end

    test "should return zero when total_net has no quantity_at_record" do
      div = %{
        amount: Decimal.new("500"),
        amount_type: "total_net",
        gross_rate: nil,
        quantity_at_record: nil
      }

      assert Decimal.equal?(DividendAnalytics.per_share_amount(div), Decimal.new("0"))
    end

    test "should return zero when amount is nil" do
      div = %{amount: nil, amount_type: "per_share", gross_rate: nil, quantity_at_record: nil}
      assert Decimal.equal?(DividendAnalytics.per_share_amount(div), Decimal.new("0"))
    end
  end

  describe "compute_rule72/1" do
    test "should compute correct values at 8% (baseline)" do
      result = DividendAnalytics.compute_rule72(8.0)

      assert result.rate == 8.0
      assert result.exact_years == 9.0
      assert result.approx_years == 9.0
      assert result.rule_variant == "R72"
      assert length(result.milestones) == 5
    end

    test "should use adjusted numerator for low rates" do
      result = DividendAnalytics.compute_rule72(2.0)

      # (2-8)/3 = -2, numerator = 72 + (-2) = 70
      assert result.rule_variant == "R70"
      assert result.approx_years == 35.0
    end

    test "should use adjusted numerator for high rates" do
      result = DividendAnalytics.compute_rule72(14.0)

      # (14-8)/3 = 2, numerator = 72 + 2 = 74
      assert result.rule_variant == "R74"
    end

    test "should clamp numerator to 69 minimum" do
      result = DividendAnalytics.compute_rule72(1.0)

      # (1-8)/3 = -2.33 → round -2, 72 + (-2) = 70 → still above 69
      # Actually: (1-8)/3 = -2.33 → round(-2.33) = -2, 72-2 = 70
      assert result.rule_variant == "R70"
    end

    test "should clamp numerator to 74 maximum" do
      result = DividendAnalytics.compute_rule72(22.0)

      # (22-8)/3 = 4.67 → round 5, 72 + 5 = 77 → clamp to 74
      assert result.rule_variant == "R74"
    end

    test "should return nil for non-positive rate" do
      assert DividendAnalytics.compute_rule72(0) == nil
      assert DividendAnalytics.compute_rule72(-5) == nil
      assert DividendAnalytics.compute_rule72("invalid") == nil
    end

    test "should include milestones for 2x, 4x, 8x, 16x" do
      result = DividendAnalytics.compute_rule72(10.0)
      multipliers = Enum.map(result.milestones, & &1.multiplier)
      assert multipliers == [1, 2, 4, 8, 16]
    end
  end
end
