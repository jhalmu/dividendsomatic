// Default config for the portfolio area chart
export function portfolioChartConfig(series, annotations) {
  return {
    chart: {
      type: "area",
      height: 320,
      toolbar: { show: false },
      zoom: { enabled: true },
      fontFamily: "'JetBrains Mono', monospace",
      background: "transparent",
      animations: {
        enabled: true,
        easing: "easeinout",
        speed: 600,
        dynamicAnimation: { enabled: true, speed: 350 }
      }
    },
    series: series,
    stroke: {
      width: [2.5, 1.5],
      curve: "smooth",
      dashArray: [0, 5]
    },
    colors: ["#38BDF8", "#78716C"],
    fill: {
      type: ["gradient", "solid"],
      gradient: {
        shadeIntensity: 1,
        opacityFrom: 0.12,
        opacityTo: 0.02,
        stops: [0, 90, 100]
      },
      opacity: [1, 0]
    },
    xaxis: {
      type: "datetime",
      labels: {
        style: {
          colors: "#78716C",
          fontSize: "10px"
        }
      },
      axisBorder: { show: false },
      axisTicks: { show: false }
    },
    yaxis: {
      labels: {
        style: {
          colors: "#78716C",
          fontSize: "10px"
        },
        formatter: (val) => val >= 1000 ? (val / 1000).toFixed(0) + "k" : val.toFixed(0)
      }
    },
    grid: {
      borderColor: "rgba(120, 113, 108, 0.15)",
      strokeDashArray: 3,
      xaxis: { lines: { show: false } }
    },
    tooltip: {
      theme: "dark",
      x: { format: "dd MMM yyyy" },
      style: { fontSize: "12px" },
      custom: function({series, seriesIndex, dataPointIndex, w}) {
        const val = series[0][dataPointIndex]
        const cost = series[1] ? series[1][dataPointIndex] : null
        const date = w.globals.seriesX[0][dataPointIndex]
        const dateStr = new Date(date).toLocaleDateString("en-GB", {
          day: "numeric", month: "short", year: "numeric"
        })
        const pnl = cost != null ? val - cost : null

        let html = `<div style="padding: 8px 12px; font-family: 'JetBrains Mono', monospace; font-size: 12px;">`
        html += `<div style="color: #A8A29E; margin-bottom: 4px;">${dateStr}</div>`
        html += `<div style="color: #F5F5F4;">Value: <b>${val.toLocaleString("en", {minimumFractionDigits: 0})}</b></div>`
        if (cost != null) {
          html += `<div style="color: #78716C;">Cost: ${cost.toLocaleString("en", {minimumFractionDigits: 0})}</div>`
        }
        if (pnl != null) {
          const color = pnl >= 0 ? "#22C55E" : "#EF4444"
          const sign = pnl >= 0 ? "+" : ""
          html += `<div style="color: ${color};">P&L: ${sign}${pnl.toLocaleString("en", {minimumFractionDigits: 0})}</div>`
        }
        html += `</div>`
        return html
      }
    },
    legend: { show: false },
    annotations: annotations || {},
    dataLabels: { enabled: false }
  }
}
