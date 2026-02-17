// Default config for the portfolio area chart
export function portfolioChartConfig(series, annotations) {
  return {
    chart: {
      type: "area",
      height: 320,
      toolbar: { show: false },
      zoom: { enabled: true },
      fontFamily: "'IBM Plex Mono', monospace",
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
    colors: ["#5EADF7", "#4C5772"],
    fill: {
      type: ["gradient", "solid"],
      gradient: {
        shadeIntensity: 1,
        opacityFrom: 0.15,
        opacityTo: 0.01,
        stops: [0, 85, 100]
      },
      opacity: [1, 0]
    },
    xaxis: {
      type: "datetime",
      labels: {
        style: {
          colors: "#4C5772",
          fontSize: "10px"
        }
      },
      axisBorder: { show: false },
      axisTicks: { show: false }
    },
    yaxis: {
      labels: {
        style: {
          colors: "#4C5772",
          fontSize: "10px"
        },
        formatter: (val) => val >= 1000 ? (val / 1000).toFixed(0) + "k" : val.toFixed(0)
      }
    },
    grid: {
      borderColor: "rgba(76, 87, 114, 0.12)",
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

        let html = `<div style="padding: 8px 12px; font-family: 'IBM Plex Mono', monospace; font-size: 12px; background: rgba(14, 18, 27, 0.95); border: 1px solid rgba(45, 55, 80, 0.5); border-radius: 8px; backdrop-filter: blur(8px);">`
        html += `<div style="color: #7E8BA3; margin-bottom: 4px;">${dateStr}</div>`
        html += `<div style="color: #D8DEE9;">Value: <b>${val.toLocaleString("en", {minimumFractionDigits: 0})}</b></div>`
        if (cost != null) {
          html += `<div style="color: #4C5772;">Cost: ${cost.toLocaleString("en", {minimumFractionDigits: 0})}</div>`
        }
        if (pnl != null) {
          const color = pnl >= 0 ? "#34D399" : "#F87171"
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
