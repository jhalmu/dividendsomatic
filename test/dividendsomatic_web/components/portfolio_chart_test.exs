defmodule DividendsomaticWeb.Components.PortfolioChartTest do
  use ExUnit.Case, async: true

  alias DividendsomaticWeb.Components.PortfolioChart

  describe "render_sparkline/2" do
    test "should return HTML containing an SVG element for valid data" do
      values = [10.0, 20.0, 15.0, 25.0, 30.0]
      result = PortfolioChart.render_sparkline(values)

      assert {:safe, _} = result

      html = Phoenix.HTML.safe_to_string(result)
      assert html =~ "<svg"
      assert html =~ "sparkline-inline"
    end

    test "should return empty HTML for an empty list" do
      result = PortfolioChart.render_sparkline([])

      assert {:safe, _} = result

      html = Phoenix.HTML.safe_to_string(result)
      assert html == ""
    end

    test "should return empty HTML for a single value" do
      result = PortfolioChart.render_sparkline([42.0])

      assert {:safe, _} = result

      html = Phoenix.HTML.safe_to_string(result)
      assert html == ""
    end

    test "should return empty HTML for nil input" do
      result = PortfolioChart.render_sparkline(nil)

      assert {:safe, _} = result

      html = Phoenix.HTML.safe_to_string(result)
      assert html == ""
    end

    test "should apply custom width and height options" do
      values = [5.0, 10.0, 7.0, 12.0]
      result = PortfolioChart.render_sparkline(values, width: 200, height: 50)

      assert {:safe, _} = result

      html = Phoenix.HTML.safe_to_string(result)
      assert html =~ "<svg"
      assert html =~ "200"
      assert html =~ "50"
    end

    test "should apply custom fill and line color options" do
      values = [1.0, 2.0, 3.0]
      result = PortfolioChart.render_sparkline(values, fill: "rgba(255,0,0,0.2)", line: "#ff0000")

      assert {:safe, _} = result

      html = Phoenix.HTML.safe_to_string(result)
      assert html =~ "<svg"
    end
  end

  describe "render_fear_greed_gauge/1" do
    test "should contain FEAR and GREED text and the value for valid data" do
      fear_greed = %{value: 65, color: "green"}
      result = PortfolioChart.render_fear_greed_gauge(fear_greed)

      assert {:safe, _} = result

      html = Phoenix.HTML.safe_to_string(result)
      assert html =~ "<svg"
      assert html =~ "FEAR"
      assert html =~ "GREED"
      assert html =~ "65"
      assert html =~ "fear-greed-gauge"
    end

    test "should render with different color values" do
      for color <- ["red", "orange", "yellow", "emerald", "green"] do
        fear_greed = %{value: 50, color: color}
        result = PortfolioChart.render_fear_greed_gauge(fear_greed)

        assert {:safe, _} = result

        html = Phoenix.HTML.safe_to_string(result)
        assert html =~ "<svg"
        assert html =~ "50"
      end
    end

    test "should render extreme value 0" do
      fear_greed = %{value: 0, color: "red"}
      result = PortfolioChart.render_fear_greed_gauge(fear_greed)

      html = Phoenix.HTML.safe_to_string(result)
      assert html =~ "FEAR"
      assert html =~ "GREED"
      assert html =~ ">0<"
    end

    test "should render extreme value 100" do
      fear_greed = %{value: 100, color: "green"}
      result = PortfolioChart.render_fear_greed_gauge(fear_greed)

      html = Phoenix.HTML.safe_to_string(result)
      assert html =~ "FEAR"
      assert html =~ "GREED"
      assert html =~ "100"
    end

    test "should return empty HTML for nil input" do
      result = PortfolioChart.render_fear_greed_gauge(nil)

      assert {:safe, _} = result

      html = Phoenix.HTML.safe_to_string(result)
      assert html == ""
    end

    test "should return empty HTML for non-map input" do
      result = PortfolioChart.render_fear_greed_gauge("not a map")

      assert {:safe, _} = result

      html = Phoenix.HTML.safe_to_string(result)
      assert html == ""
    end
  end
end
