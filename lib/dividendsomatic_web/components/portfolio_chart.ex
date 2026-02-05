defmodule DividendsomaticWeb.Components.PortfolioChart do
  @moduledoc """
  LiveComponent for rendering portfolio value chart using Contex.
  """
  use Phoenix.LiveComponent

  alias Contex.{Dataset, LinePlot, Plot}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="portfolio-chart-container">
      {render_chart(@chart_data, @current_date)}
    </div>
    """
  end

  defp render_chart(chart_data, current_date) when length(chart_data) > 1 do
    data_points =
      chart_data
      |> Enum.with_index()
      |> Enum.map(fn {point, idx} -> {idx, point.value_float} end)

    min_value = chart_data |> Enum.map(& &1.value_float) |> Enum.min() |> floor()
    max_value = chart_data |> Enum.map(& &1.value_float) |> Enum.max() |> ceil()
    padding = (max_value - min_value) * 0.1

    dataset = Dataset.new(data_points, ["Day", "Value"])

    current_idx =
      Enum.find_index(chart_data, fn point -> point.date == current_date end) || 0

    options = [
      mapping: %{x_col: "Day", y_cols: ["Value"]},
      colour_palette: ["#10b981"],
      smoothed: false,
      custom_y_scale:
        Contex.ContinuousLinearScale.new()
        |> Contex.ContinuousLinearScale.domain(min_value - padding, max_value + padding),
      custom_y_formatter: &format_value/1,
      axis_label_rotation: 0
    ]

    plot =
      Plot.new(dataset, LinePlot, 800, 200, options)
      |> Plot.titles("", "")
      |> Plot.axis_labels("", "")

    {:safe, svg_iolist} = Plot.to_svg(plot)
    svg_string = IO.iodata_to_binary(svg_iolist)

    first_date = format_date(List.first(chart_data))
    current_date_str = format_date(Enum.at(chart_data, current_idx))
    last_date = format_date(List.last(chart_data))

    Phoenix.HTML.raw("""
    <div class="relative">
      <style>
        .portfolio-chart-container svg {
          width: 100%;
          height: auto;
        }
        .portfolio-chart-container .exc-tick text {
          font-family: 'JetBrains Mono', monospace;
          font-size: 10px;
          fill: #64748b;
        }
        .portfolio-chart-container .exc-tick line,
        .portfolio-chart-container .exc-axis line,
        .portfolio-chart-container .exc-axis path {
          stroke: #2d3748;
        }
        .portfolio-chart-container .exc-line {
          stroke-width: 2.5;
          filter: drop-shadow(0 0 6px rgba(16, 185, 129, 0.4));
        }
      </style>
      #{svg_string}
      <div class="absolute bottom-8 left-0 right-0 flex justify-between px-12 text-xs text-[#64748b] font-mono">
        <span>#{first_date}</span>
        <span class="text-[#10b981] font-semibold">#{current_date_str}</span>
        <span>#{last_date}</span>
      </div>
    </div>
    """)
  end

  defp render_chart(_chart_data, _current_date) do
    Phoenix.HTML.raw("""
    <div class="text-center text-[#64748b] py-8">
      Not enough data points to display chart
    </div>
    """)
  end

  defp format_value(value) when is_number(value) do
    value
    |> round()
    |> Integer.to_string()
    |> add_thousands_separator()
  end

  defp format_value(value), do: to_string(value)

  defp add_thousands_separator(str) do
    str
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_date(%{date: date}) do
    Calendar.strftime(date, "%b %d")
  end

  defp format_date(_), do: ""
end
