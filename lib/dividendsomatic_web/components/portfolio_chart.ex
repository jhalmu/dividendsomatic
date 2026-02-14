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
      {render_combined(@chart_data, @current_date, @fear_greed)}
      <p class="sr-only">
        Portfolio value and cost basis chart showing {length(@chart_data)} data points.
      </p>
    </div>
    """
  end

  # --- Main combined chart renderer ---

  defp render_combined(chart_data, current_date, _fear_greed)
       when is_list(chart_data) and length(chart_data) > 1 do
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

    parts =
      [
        svg_defs(false),
        svg_grid(mt, main_h, y_lo, y_range),
        svg_era_gap_indicator(chart_data, x_fn, mt, main_h),
        svg_area_fill(chart_data, x_fn, y_fn, chart_bottom),
        svg_line(chart_data, :cost_basis_float, x_fn, y_fn, "#3b82f6", "1", "6 3"),
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

  defp render_combined(_, _, _) do
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
        <stop offset="0%" stop-color="#10b981" stop-opacity="0.40"/>
        <stop offset="100%" stop-color="#10b981" stop-opacity="0.10"/>
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
    chart_data
    |> split_at_gaps()
    |> Enum.map_join("\n", &svg_area_segment(&1, x_fn, y_fn, bottom_y))
  end

  defp svg_area_segment(segment, x_fn, y_fn, bottom_y) do
    indexed = Enum.map(segment, fn {point, idx} -> {idx, point} end)

    points =
      Enum.map(indexed, fn {i, p} ->
        "#{r(x_fn.(i))},#{r(y_fn.(p.value_float))}"
      end)

    {first_idx, _} = hd(indexed)
    {last_idx, _} = List.last(indexed)
    first_x = r(x_fn.(first_idx))
    last_x = r(x_fn.(last_idx))

    d = "M#{first_x},#{bottom_y} L#{Enum.join(points, " L")} L#{last_x},#{bottom_y} Z"
    ~s[<path d="#{d}" fill="url(#val-area)"/>]
  end

  # Split chart data into segments, breaking at gaps > 180 days
  defp split_at_gaps(chart_data) do
    chart_data
    |> Enum.with_index()
    |> Enum.chunk_while([], &chunk_by_gap/2, &flush_chunk/1)
    |> Enum.reject(&(&1 == []))
  end

  defp chunk_by_gap(item, []), do: {:cont, [item]}

  defp chunk_by_gap({point, _idx} = item, [{prev_point, _} | _] = acc) do
    if Date.diff(point.date, prev_point.date) > 180 do
      {:cont, Enum.reverse(acc), [item]}
    else
      {:cont, [item | acc]}
    end
  end

  defp flush_chunk([]), do: {:cont, []}
  defp flush_chunk(acc), do: {:cont, Enum.reverse(acc), []}

  defp svg_line(chart_data, field, x_fn, y_fn, color, width, dash) do
    dash_attr = if dash, do: ~s[ stroke-dasharray="#{dash}" opacity="0.6"], else: ""

    chart_data
    |> split_at_gaps()
    |> Enum.map_join("\n", &svg_line_segment(&1, field, x_fn, y_fn, color, width, dash_attr))
  end

  defp svg_line_segment(segment, field, x_fn, y_fn, color, width, dash_attr) do
    d =
      segment
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {{p, orig_idx}, seg_idx} ->
        x = r(x_fn.(orig_idx))
        y = r(y_fn.(Map.get(p, field)))
        if seg_idx == 0, do: "M#{x} #{y}", else: "L#{x} #{y}"
      end)

    ~s[<path d="#{d}" fill="none" stroke="#{color}" stroke-width="#{width}" stroke-linejoin="round"#{dash_attr}/>]
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
    count = min(12, n)
    step = max(div(n - 1, count), 1)

    # Use year-month format for wide ranges (>365 days), day format for narrow
    first_date = hd(chart_data).date
    last_date = List.last(chart_data).date
    wide_range = Date.diff(last_date, first_date) > 365

    for i <- 0..count, idx = min(i * step, n - 1), reduce: [] do
      acc ->
        point = Enum.at(chart_data, idx)
        lx = r(x_fn.(idx))

        date_str =
          if wide_range,
            do: Calendar.strftime(point.date, "%b %Y"),
            else: Calendar.strftime(point.date, "%b %d")

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

  # Era gap indicator: shows "NO DATA" zone and era labels between data segments
  defp svg_era_gap_indicator(chart_data, x_fn, mt, main_h) do
    segments = split_at_gaps(chart_data)

    if length(segments) > 1 do
      gap_svg =
        segments
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map_join("\n", fn [seg_a, seg_b] ->
          {_, last_idx} = List.last(seg_a)
          {_, first_idx} = hd(seg_b)
          mid_x = r((x_fn.(last_idx) + x_fn.(first_idx)) / 2)
          mid_y = r(mt + main_h / 2)
          left_x = r(x_fn.(last_idx))
          right_x = r(x_fn.(first_idx))
          gap_w = r(right_x - left_x)

          """
          <rect x="#{left_x}" y="#{mt}" width="#{gap_w}" height="#{main_h}" fill="#1e293b" opacity="0.15"/>
          <line x1="#{left_x}" y1="#{mt}" x2="#{left_x}" y2="#{r(mt + main_h)}" stroke="#334155" stroke-width="1" stroke-dasharray="4 4" opacity="0.4"/>
          <line x1="#{right_x}" y1="#{mt}" x2="#{right_x}" y2="#{r(mt + main_h)}" stroke="#334155" stroke-width="1" stroke-dasharray="4 4" opacity="0.4"/>
          <text x="#{mid_x}" y="#{mid_y}" fill="#475569" font-size="8" text-anchor="middle" opacity="0.6">NO DATA</text>
          """
        end)

      era_labels =
        segments
        |> Enum.with_index()
        |> Enum.map_join("\n", &svg_era_label(&1, x_fn, mt, main_h))

      gap_svg <> "\n" <> era_labels
    else
      ""
    end
  end

  defp svg_era_label({segment, seg_idx}, x_fn, mt, main_h) do
    {_, first_idx} = hd(segment)
    {_, last_idx} = List.last(segment)
    seg_mid_x = r((x_fn.(first_idx) + x_fn.(last_idx)) / 2)
    label_y = r(mt + main_h - 8)

    {first_point, _} = hd(segment)
    era_label = if Map.get(first_point, :source) == "nordnet", do: "NORDNET", else: "IBKR"
    seg_px = x_fn.(last_idx) - x_fn.(first_idx)

    if seg_px > 60 or seg_idx == 0 do
      ~s[<text x="#{seg_mid_x}" y="#{label_y}" fill="#334155" font-size="7" text-anchor="middle" letter-spacing="0.1em" opacity="0.5">#{era_label}</text>]
    else
      ""
    end
  end

  # --- Helpers ---

  @month_abbrs %{
    1 => "Jan",
    2 => "Feb",
    3 => "Mar",
    4 => "Apr",
    5 => "May",
    6 => "Jun",
    7 => "Jul",
    8 => "Aug",
    9 => "Sep",
    10 => "Oct",
    11 => "Nov",
    12 => "Dec"
  }

  defp format_month_label(month_string, total_months) do
    month_num = month_string |> String.slice(5, 2) |> String.to_integer()
    year_2d = String.slice(month_string, 2, 2)

    if total_months <= 24 do
      "#{@month_abbrs[month_num]} #{year_2d}"
    else
      if month_num == 1, do: "'#{year_2d}", else: "#{String.first(@month_abbrs[month_num])}#{year_2d}"
    end
  end

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

  # --- Standalone Dividend Chart (public, used as separate section) ---

  @doc """
  Renders a standalone dividend chart SVG with monthly bars and cumulative line.
  Expects a list of `%{month: "YYYY-MM", total: Decimal}` maps.
  """
  def render_dividend_chart(dividend_data) when is_list(dividend_data) and length(dividend_data) > 0 do
    mt = 20
    bar_h = 120
    chart_bottom = mt + bar_h
    total_h = chart_bottom + 25

    n = length(dividend_data)
    bar_gap = 2
    bar_w = max((@pw - bar_gap * (n - 1)) / n, 4)

    totals = Enum.map(dividend_data, fn d -> Decimal.to_float(d.total) end)
    max_total = Enum.max(totals) |> max(0.01)

    # Cumulative values for the line
    cumulative =
      Enum.scan(totals, 0, &(&1 + &2))

    max_cum = List.last(cumulative) |> max(0.01)

    # Bar SVG
    bars =
      dividend_data
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {d, i} ->
        total = Decimal.to_float(d.total)
        bx = r(@ml + i * (bar_w + bar_gap))
        bh = r(total / max_total * bar_h * 0.85)
        by = r(chart_bottom - bh)

        label =
          if total > 0,
            do:
              ~s[<text x="#{r(bx + bar_w / 2)}" y="#{r(by - 3)}" fill="#eab308" font-size="6" text-anchor="middle" font-weight="600">#{format_compact(total)}</text>],
            else: ""

        """
        <rect x="#{bx}" y="#{by}" width="#{r(bar_w)}" height="#{bh}" fill="#eab308" opacity="0.7" rx="1"/>
        #{label}
        """
      end)

    # Cumulative line overlay
    cum_line =
      cumulative
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {cum, i} ->
        cx = r(@ml + i * (bar_w + bar_gap) + bar_w / 2)
        cy = r(mt + bar_h * 0.85 - cum / max_cum * bar_h * 0.75)
        if i == 0, do: "M#{cx} #{cy}", else: "L#{cx} #{cy}"
      end)

    cum_svg = ~s[<path d="#{cum_line}" fill="none" stroke="#f97316" stroke-width="1.5" stroke-linejoin="round"/>]

    # Cumulative end label
    last_cum = List.last(cumulative)
    last_cx = r(@ml + (n - 1) * (bar_w + bar_gap) + bar_w / 2)
    last_cy = r(mt + bar_h * 0.85 - last_cum / max_cum * bar_h * 0.75)
    {label_x, anchor} = if last_cx > @w - 80, do: {last_cx - 8, "end"}, else: {last_cx + 8, "start"}

    cum_label =
      ~s[<text x="#{label_x}" y="#{r(last_cy - 4)}" fill="#f97316" font-size="7" font-weight="600" text-anchor="#{anchor}">#{format_compact(last_cum)}</text>]

    # X labels (month abbreviations with year context)
    x_labels =
      dividend_data
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {d, i} ->
        lx = r(@ml + i * (bar_w + bar_gap) + bar_w / 2)
        # Show short month label; skip some if too many
        show = n <= 36 or rem(i, max(div(n, 24), 1)) == 0
        month_label = format_month_label(d.month, n)

        if show do
          ~s[<text x="#{lx}" y="#{r(chart_bottom + 12)}" fill="#475569" font-size="7" text-anchor="middle">#{month_label}</text>]
        else
          ""
        end
      end)

    # Y labels (left side)
    y_labels =
      for i <- 0..4 do
        gy = r(mt + bar_h - i / 4 * bar_h * 0.85 + 3)
        val = i / 4 * max_total

        ~s[<text x="#{@ml - 8}" y="#{gy}" fill="#475569" font-size="7" text-anchor="end">#{format_compact(val)}</text>]
      end
      |> Enum.join("\n")

    # Grid lines
    grid =
      for i <- 0..4 do
        gy = r(mt + bar_h - i / 4 * bar_h * 0.85)
        ~s[<line x1="#{@ml}" y1="#{gy}" x2="#{@ml + @pw}" y2="#{gy}" stroke="#1e293b" stroke-width="1"/>]
      end
      |> Enum.join("\n")

    Phoenix.HTML.raw("""
    <svg width="#{@w}" height="#{round(total_h)}" viewBox="0 0 #{@w} #{round(total_h)}" xmlns="http://www.w3.org/2000/svg" style="font-family: 'JetBrains Mono', monospace;">
      #{grid}
      #{bars}
      #{cum_svg}
      #{cum_label}
      #{x_labels}
      #{y_labels}
    </svg>
    """)
  end

  def render_dividend_chart(_), do: Phoenix.HTML.raw("")

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
        <path d="M #{cx - radius} #{cy} A #{radius} #{radius} 0 0 1 #{needle_x} #{needle_y}"
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
