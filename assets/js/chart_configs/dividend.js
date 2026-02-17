// Default config for the dividend bar+line chart
export function dividendChartConfig(series) {
  return {
    chart: {
      type: "bar",
      height: 260,
      toolbar: { show: false },
      fontFamily: "'IBM Plex Mono', monospace",
      background: "transparent",
      animations: {
        enabled: true,
        easing: "easeinout",
        speed: 600
      }
    },
    series: series,
    plotOptions: {
      bar: {
        borderRadius: 4,
        borderRadiusApplication: "end",
        columnWidth: "60%"
      }
    },
    stroke: {
      width: [0, 2.5],
      curve: "smooth"
    },
    colors: ["#FBBF24", "#F59E0B"],
    fill: {
      opacity: [0.85, 1]
    },
    xaxis: {
      categories: [],
      labels: {
        style: {
          colors: "#4C5772",
          fontSize: "10px"
        },
        rotate: -45,
        rotateAlways: false
      },
      axisBorder: { show: false },
      axisTicks: { show: false }
    },
    yaxis: [
      {
        title: { text: "" },
        labels: {
          style: {
            colors: "#4C5772",
            fontSize: "10px"
          },
          formatter: (val) => val.toFixed(0)
        }
      },
      {
        opposite: true,
        title: { text: "" },
        labels: {
          style: {
            colors: "#4C5772",
            fontSize: "10px"
          },
          formatter: (val) => val >= 1000 ? (val / 1000).toFixed(1) + "k" : val.toFixed(0)
        }
      }
    ],
    grid: {
      borderColor: "rgba(76, 87, 114, 0.12)",
      strokeDashArray: 3,
      xaxis: { lines: { show: false } }
    },
    tooltip: {
      theme: "dark",
      shared: true,
      intersect: false,
      style: { fontSize: "12px" },
      y: {
        formatter: (val) => val != null ? val.toLocaleString("en", {minimumFractionDigits: 2, maximumFractionDigits: 2}) : ""
      }
    },
    legend: { show: false },
    dataLabels: { enabled: false }
  }
}
