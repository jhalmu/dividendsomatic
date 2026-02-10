defmodule DividendsomaticWeb.Components.PortfolioChart do
  @moduledoc """
  LiveComponent for rendering a combined portfolio chart as custom SVG.

  Renders a unified panel with portfolio value line, cost basis line,
  dividend bars, Fear & Greed indicator, and current date marker.
  """
  use Phoenix.LiveComponent

  alias Contex.Sparkline

  # Layout constants
  @w 900
  @ml 62
  @mr 20
  @pw @w - @ml - @mr

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:fear_greed, fn -> nil end)
      |> assign_new(:dividend_data, fn -> [] end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="combined-chart-container"
      id="chart-anim"
      phx-hook="ChartAnimation"
      role="img"
      aria-labelledby="chart-title"
      aria-describedby="chart-legend"
    >
      {render_combined(@chart_data, @current_date, @dividend_data, @fear_greed)}
      <p class="sr-only">
        Portfolio value and cost basis chart showing {length(@chart_data)} data points.
      </p>
    </div>
    """
  end

  # --- Main combined chart renderer ---

  defp render_combined(chart_data, current_date, dividend_data, _fear_greed)
       when is_list(chart_data) and length(chart_data) > 1 do
    has_div = is_list(dividend_data) and dividend_data != []

    mt = 20
    main_h = 250
    chart_bottom = mt + main_h
    total_h = chart_bottom + 25

    n = length(chart_data)

    # X scale: index -> pixel
    x_fn = fn idx -> @ml + idx / max(n - 1, 1) * @pw end

    # Y scale: value -> pixel
    vals = Enum.map(chart_data, & &1.value_float)
    costs = Enum.map(chart_data, & &1.cost_basis_float)
    all_y = vals ++ costs
    y_lo = Enum.min(all_y) * 0.97
    y_hi = Enum.max(all_y) * 1.03
    y_range = max(y_hi - y_lo, 1.0)
    y_fn = fn v -> mt + main_h - (v - y_lo) / y_range * main_h end

    # Dividend bars overlaid at bottom of main chart area
    div_overlay =
      if has_div do
        svg_dividend_overlay(dividend_data, chart_data, x_fn, mt, main_h, chart_bottom)
      else
        ""
      end

    parts =
      [
        svg_defs(false),
        svg_grid(mt, main_h, y_lo, y_range),
        svg_area_fill(chart_data, x_fn, y_fn, chart_bottom),
        div_overlay,
        svg_line(chart_data, :value_float, x_fn, y_fn, "#10b981", "2.5", nil),
        svg_line(chart_data, :cost_basis_float, x_fn, y_fn, "#3b82f6", "1.5", "6 3"),
        svg_current_marker(chart_data, current_date, x_fn, y_fn, mt, chart_bottom),
        svg_x_labels(chart_data, x_fn, chart_bottom + 15),
        svg_y_labels(mt, main_h, y_lo, y_range),
        svg_annotations(chart_data, x_fn, y_fn)
      ]
      |> Enum.join("\n")

    Phoenix.HTML.raw("""
    <svg width="#{@w}" height="#{round(total_h)}" viewBox="0 0 #{@w} #{round(total_h)}" xmlns="http://www.w3.org/2000/svg" style="font-family: 'JetBrains Mono', monospace;">
      #{parts}
    </svg>
    """)
  end

  defp render_combined(_, _, _, _) do
    Phoenix.HTML.raw("""
    <div style="text-align: center; padding: 2.5rem; font-size: 0.75rem; color: #475569; font-family: 'JetBrains Mono', monospace;">
      Not enough data for chart
    </div>
    """)
  end

  # --- SVG building blocks ---

  defp svg_defs(has_fg) do
    fg_grad =
      if has_fg do
        """
        <linearGradient id="fg-bar-grad" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stop-color="#ef4444"/>
          <stop offset="30%" stop-color="#f97316"/>
          <stop offset="50%" stop-color="#eab308"/>
          <stop offset="75%" stop-color="#10b981"/>
          <stop offset="100%" stop-color="#22c55e"/>
        </linearGradient>
        """
      else
        ""
      end

    """
    <defs>
      <linearGradient id="val-area" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="#10b981" stop-opacity="0.15"/>
        <stop offset="100%" stop-color="#10b981" stop-opacity="0.02"/>
      </linearGradient>
      <linearGradient id="div-area" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="#f59e0b" stop-opacity="0.20"/>
        <stop offset="100%" stop-color="#f59e0b" stop-opacity="0.03"/>
      </linearGradient>
      #{fg_grad}
    </defs>
    """
  end

  defp svg_grid(mt, main_h, _y_lo, _y_range) do
    for i <- 0..5 do
      gy = r(mt + main_h - i / 5 * main_h)

      """
      <line x1="#{@ml}" y1="#{gy}" x2="#{@ml + @pw}" y2="#{gy}" stroke="#1e293b" stroke-width="1"/>
      """
    end
    |> Enum.join("\n")
  end

  defp svg_area_fill(chart_data, x_fn, y_fn, bottom_y) do
    n = length(chart_data)

    points =
      chart_data
      |> Enum.with_index()
      |> Enum.map(fn {p, i} ->
        "#{r(x_fn.(i))},#{r(y_fn.(p.value_float))}"
      end)

    first_x = r(x_fn.(0))
    last_x = r(x_fn.(n - 1))

    d = "M#{first_x},#{bottom_y} L#{Enum.join(points, " L")} L#{last_x},#{bottom_y} Z"
    ~s[<path d="#{d}" fill="url(#val-area)"/>]
  end

  defp svg_line(chart_data, field, x_fn, y_fn, color, width, dash) do
    d =
      chart_data
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {p, i} ->
        x = r(x_fn.(i))
        y = r(y_fn.(Map.get(p, field)))
        if i == 0, do: "M#{x} #{y}", else: "L#{x} #{y}"
      end)

    dash_attr = if dash, do: ~s[ stroke-dasharray="#{dash}" opacity="0.6"], else: ""

    glow =
      if dash,
        do: "filter: drop-shadow(0 0 3px rgba(59,130,246,0.25));",
        else: "filter: drop-shadow(0 0 5px rgba(16,185,129,0.4));"

    ~s[<path d="#{d}" fill="none" stroke="#{color}" stroke-width="#{width}" stroke-linejoin="round"#{dash_attr} style="#{glow}"/>]
  end

  defp svg_current_marker(chart_data, current_date, x_fn, y_fn, mt, bottom) do
    case Enum.find_index(chart_data, fn p -> p.date == current_date end) do
      nil ->
        ""

      idx ->
        point = Enum.at(chart_data, idx)
        cx = r(x_fn.(idx))
        cy = r(y_fn.(point.value_float))

        """
        <line x1="#{cx}" y1="#{mt}" x2="#{cx}" y2="#{bottom}" stroke="#10b981" stroke-width="1" stroke-dasharray="3 3" opacity="0.25"/>
        <circle cx="#{cx}" cy="#{cy}" r="3.5" fill="#10b981" stroke="#0a0e17" stroke-width="2" class="chart-current-marker"/>
        """
    end
  end

  defp svg_x_labels(chart_data, x_fn, label_y) do
    n = length(chart_data)
    count = min(6, n)
    step = max(div(n - 1, count), 1)

    for i <- 0..count, idx = min(i * step, n - 1), reduce: [] do
      acc ->
        point = Enum.at(chart_data, idx)
        lx = r(x_fn.(idx))
        date_str = Calendar.strftime(point.date, "%b %d")

        [
          ~s[<text x="#{lx}" y="#{r(label_y)}" fill="#475569" font-size="8" text-anchor="middle">#{date_str}</text>]
          | acc
        ]
    end
    |> Enum.reverse()
    |> Enum.uniq()
    |> Enum.join("\n")
  end

  defp svg_y_labels(mt, main_h, y_lo, y_range) do
    for i <- 0..5 do
      gy = r(mt + main_h - i / 5 * main_h + 3)
      val = y_lo + i / 5 * y_range

      ~s[<text x="#{@ml - 8}" y="#{gy}" fill="#475569" font-size="8" text-anchor="end">#{format_compact(val)}</text>]
    end
    |> Enum.join("\n")
  end

  defp svg_annotations(chart_data, x_fn, y_fn) do
    n = length(chart_data)
    last = List.last(chart_data)
    lx = r(x_fn.(n - 1))

    val_y = r(y_fn.(last.value_float))
    cost_y = r(y_fn.(last.cost_basis_float))

    # Position labels to left if near edge
    {label_x, anchor} = if lx > @w - 80, do: {lx - 8, "end"}, else: {lx + 8, "start"}

    """
    <text x="#{label_x}" y="#{val_y - 6}" fill="#10b981" font-size="8" font-weight="600" text-anchor="#{anchor}">€#{format_compact(last.value_float)}</text>
    <text x="#{label_x}" y="#{cost_y + 12}" fill="#3b82f6" font-size="7" text-anchor="#{anchor}" opacity="0.6">€#{format_compact(last.cost_basis_float)}</text>
    """
  end

  # Dividend bars overlaid at the bottom of the main chart area + cumulative orange line
  defp svg_dividend_overlay(dividend_data, chart_data, x_fn, mt, main_h, chart_bottom) do
    # Map each dividend month to the chart x-position
    # Find the mid-point index in chart_data for each month "YYYY-MM"
    month_positions =
      Enum.map(dividend_data, fn d ->
        month_str = d.month
        # Find all chart_data indices whose date matches this month
        matching_indices =
          chart_data
          |> Enum.with_index()
          |> Enum.filter(fn {point, _idx} ->
            Calendar.strftime(point.date, "%Y-%m") == month_str
          end)
          |> Enum.map(fn {_point, idx} -> idx end)

        mid_idx =
          case matching_indices do
            [] -> nil
            indices -> Enum.at(indices, div(length(indices), 2))
          end

        total = Decimal.to_float(d.total)
        {mid_idx, total, d.month}
      end)
      |> Enum.reject(fn {idx, _, _} -> is_nil(idx) end)

    case month_positions do
      [] ->
        ""

      positions ->
        bars = svg_dividend_bars(positions, x_fn, main_h, chart_bottom, chart_data)
        cum_svg = svg_cumulative_line(positions, x_fn, mt, main_h)

        """
        #{bars}
        #{cum_svg}
        """
    end
  end

  defp svg_dividend_bars(positions, x_fn, main_h, chart_bottom, _chart_data) do
    totals = Enum.map(positions, fn {_, t, _} -> t end)
    max_total = Enum.max(totals)
    bar_zone_h = main_h * 0.18

    # Build area fill path from bar tops
    area_points =
      Enum.map(positions, fn {idx, total, _} ->
        cx = r(x_fn.(idx))
        bh = if max_total > 0, do: r(total / max_total * bar_zone_h), else: 0
        by = r(chart_bottom - bh)
        {cx, by}
      end)

    area_path =
      case area_points do
        [{first_x, first_y} | rest] ->
          moves = Enum.map_join(rest, " ", fn {x, y} -> "L#{x} #{y}" end)
          {last_x, _} = List.last(area_points)

          ~s[<path d="M#{first_x} #{chart_bottom} L#{first_x} #{first_y} #{moves} L#{last_x} #{chart_bottom} Z" fill="url(#div-area)"/>]

        _ ->
          ""
      end

    # Value labels at each point
    labels =
      Enum.map_join(positions, "\n", fn {idx, total, _month} ->
        cx = r(x_fn.(idx))
        bh = if max_total > 0, do: r(total / max_total * bar_zone_h), else: 0
        by = r(chart_bottom - bh)

        ~s[<text x="#{cx}" y="#{r(by - 4)}" fill="#f59e0b" font-size="7" text-anchor="middle" font-weight="500" opacity="0.7">€#{format_compact(total)}</text>]
      end)

    """
    #{area_path}
    #{labels}
    """
  end

  # Cumulative dividend orange line with dots and label
  defp svg_cumulative_line(month_positions, x_fn, mt, main_h) do
    cumulative =
      Enum.scan(month_positions, {0, 0, ""}, fn {idx, total, month}, {_, cum, _} ->
        {idx, cum + total, month}
      end)

    max_cum = elem(List.last(cumulative), 1)
    cum_zone_h = main_h * 0.30
    cum_base = mt + main_h * 0.15

    cum_y_fn = fn val ->
      if max_cum > 0,
        do: cum_base + cum_zone_h - val / max_cum * cum_zone_h,
        else: cum_base + cum_zone_h
    end

    cum_path = svg_cumulative_path(cumulative, x_fn, cum_y_fn)

    cum_dots =
      Enum.map_join(cumulative, "\n", fn {idx, cum, _} ->
        cx = r(x_fn.(idx))
        cy = r(cum_y_fn.(cum))

        ~s[<circle cx="#{cx}" cy="#{cy}" r="2.5" fill="#f59e0b" stroke="#0a0e17" stroke-width="1.5"/>]
      end)

    {last_idx, last_cum, _} = List.last(cumulative)
    last_x = r(x_fn.(last_idx))
    last_y = r(cum_y_fn.(last_cum))
    {label_x, anchor} = if last_x > @w - 80, do: {last_x - 8, "end"}, else: {last_x + 8, "start"}

    cum_label =
      ~s[<text x="#{label_x}" y="#{r(last_y - 4)}" fill="#f59e0b" font-size="7" font-weight="600" text-anchor="#{anchor}">€#{format_compact(last_cum)} div</text>]

    cum_area = svg_cumulative_area(cumulative, x_fn, cum_y_fn, cum_base + cum_zone_h)

    """
    #{cum_area}
    #{cum_path}
    #{cum_dots}
    #{cum_label}
    """
  end

  defp svg_cumulative_area(cumulative, _x_fn, _cum_y_fn, _baseline) when length(cumulative) <= 1,
    do: ""

  defp svg_cumulative_area(cumulative, x_fn, cum_y_fn, baseline) do
    points =
      Enum.map(cumulative, fn {idx, cum, _} ->
        {r(x_fn.(idx)), r(cum_y_fn.(cum))}
      end)

    case points do
      [{first_x, first_y} | rest] ->
        moves = Enum.map_join(rest, " ", fn {x, y} -> "L#{x} #{y}" end)
        {last_x, _} = List.last(points)

        ~s[<path d="M#{first_x} #{baseline} L#{first_x} #{first_y} #{moves} L#{last_x} #{baseline} Z" fill="url(#div-area)" opacity="0.6"/>]

      _ ->
        ""
    end
  end

  defp svg_cumulative_path(cumulative, _x_fn, _cum_y_fn) when length(cumulative) <= 1, do: ""

  defp svg_cumulative_path(cumulative, x_fn, cum_y_fn) do
    d =
      cumulative
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {{idx, cum, _}, i} ->
        x = r(x_fn.(idx))
        y = r(cum_y_fn.(cum))
        if i == 0, do: "M#{x} #{y}", else: "L#{x} #{y}"
      end)

    ~s[<path d="#{d}" fill="none" stroke="#f59e0b" stroke-width="2" stroke-linejoin="round" opacity="0.8" style="filter: drop-shadow(0 0 3px rgba(245,158,11,0.3));"/>]
  end

  # --- Helpers ---

  defp r(val), do: Float.round(val + 0.0, 1)

  defp format_compact(val) when is_number(val) do
    cond do
      val >= 1_000_000 -> "#{Float.round(val / 1_000_000, 1)}M"
      val >= 10_000 -> "#{round(val / 1_000)}K"
      val >= 1_000 -> "#{Float.round(val / 1_000, 1)}K"
      true -> "#{round(val)}"
    end
  end

  defp format_compact(_), do: "0"

  defp fg_color_hex("red"), do: "#ef4444"
  defp fg_color_hex("orange"), do: "#f97316"
  defp fg_color_hex("yellow"), do: "#eab308"
  defp fg_color_hex("emerald"), do: "#10b981"
  defp fg_color_hex("green"), do: "#22c55e"
  defp fg_color_hex(_), do: "#64748b"

  # --- Sparkline (public, used in stats cards) ---

  @doc """
  Renders an inline sparkline for use in stats cards.
  """
  def render_sparkline(values, opts \\ [])

  def render_sparkline(values, opts) when is_list(values) and length(values) > 1 do
    width = Keyword.get(opts, :width, 120)
    height = Keyword.get(opts, :height, 28)
    fill_color = Keyword.get(opts, :fill, "rgba(16, 185, 129, 0.15)")
    line_color = Keyword.get(opts, :line, "#10b981")

    sparkline =
      Sparkline.new(values)
      |> Sparkline.colours(fill_color, line_color)
      |> Map.put(:width, width)
      |> Map.put(:height, height)
      |> Map.put(:line_width, 1.5)
      |> Map.put(:spot_radius, 0)

    {:safe, svg_iolist} = Sparkline.draw(sparkline)
    svg_string = IO.iodata_to_binary(svg_iolist)

    Phoenix.HTML.raw("""
    <span class="sparkline-inline" aria-hidden="true">#{svg_string}</span>
    """)
  end

  def render_sparkline(_, _), do: Phoenix.HTML.raw("")

  # --- Fear & Greed Gauge (standalone, used in template header) ---

  @doc """
  Renders a Fear & Greed Index gauge as an inline SVG.
  """
  def render_fear_greed_gauge(fear_greed, opts \\ [])

  def render_fear_greed_gauge(fear_greed, opts) when is_map(fear_greed) do
    value = fear_greed.value
    color_hex = fg_color_hex(fear_greed.color)
    label_text = fear_greed_label(value)
    # Unique ID suffix to avoid duplicate SVG ids
    suffix = Keyword.get(opts, :id_suffix, System.unique_integer([:positive]))

    # Arc gauge: semicircle from 180deg to 0deg (left to right)
    cx = 60
    cy = 58
    radius = 46
    angle = :math.pi() * (1 - value / 100)
    needle_x = r(cx + radius * :math.cos(angle))
    needle_y = r(cy - radius * :math.sin(angle))

    aria_label = "Fear and Greed Index: #{value} out of 100, #{label_text}"
    grad_id = "fg-arc-grad-#{suffix}"

    Phoenix.HTML.raw("""
    <div class="fear-greed-gauge" role="img" aria-label="#{aria_label}">
      <svg width="120" height="72" viewBox="0 0 120 72" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <defs>
          <linearGradient id="#{grad_id}" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%" stop-color="#ef4444"/>
            <stop offset="30%" stop-color="#f97316"/>
            <stop offset="50%" stop-color="#eab308"/>
            <stop offset="75%" stop-color="#10b981"/>
            <stop offset="100%" stop-color="#22c55e"/>
          </linearGradient>
        </defs>
        <!-- Background arc track -->
        <path d="M #{cx - radius} #{cy} A #{radius} #{radius} 0 0 1 #{cx + radius} #{cy}"
              fill="none" stroke="#1e293b" stroke-width="8" stroke-linecap="round"/>
        <!-- Colored arc track (dim) -->
        <path d="M #{cx - radius} #{cy} A #{radius} #{radius} 0 0 1 #{cx + radius} #{cy}"
              fill="none" stroke="url(##{grad_id})" stroke-width="8" stroke-linecap="round" opacity="0.25"/>
        <!-- Active arc (filled to value position) -->
        <path d="M #{cx - radius} #{cy} A #{radius} #{radius} 0 #{if value > 50, do: 1, else: 0} 1 #{needle_x} #{needle_y}"
              fill="none" stroke="url(##{grad_id})" stroke-width="8" stroke-linecap="round"/>
        <!-- Needle dot -->
        <circle cx="#{needle_x}" cy="#{needle_y}" r="5" fill="#{color_hex}" stroke="#0a0e17" stroke-width="2"/>
        <!-- Center value -->
        <text x="#{cx}" y="#{cy - 6}" fill="#{color_hex}" font-size="18" font-family="JetBrains Mono, monospace" text-anchor="middle" font-weight="700">#{value}</text>
        <!-- Label -->
        <text x="#{cx}" y="#{cy + 6}" fill="#475569" font-size="7" font-family="JetBrains Mono, monospace" text-anchor="middle" letter-spacing="0.08em">#{String.upcase(label_text)}</text>
        <!-- FEAR / GREED labels -->
        <text x="#{cx - radius - 2}" y="#{cy + 10}" fill="#334155" font-size="6" font-family="JetBrains Mono, monospace" text-anchor="middle">FEAR</text>
        <text x="#{cx + radius + 2}" y="#{cy + 10}" fill="#334155" font-size="6" font-family="JetBrains Mono, monospace" text-anchor="middle">GREED</text>
      </svg>
    </div>
    """)
  end

  def render_fear_greed_gauge(_, _), do: Phoenix.HTML.raw("")

  defp fear_greed_label(value) when value <= 25, do: "Extreme Fear"
  defp fear_greed_label(value) when value <= 45, do: "Fear"
  defp fear_greed_label(value) when value <= 55, do: "Neutral"
  defp fear_greed_label(value) when value <= 75, do: "Greed"
  defp fear_greed_label(_), do: "Extreme Greed"
end
