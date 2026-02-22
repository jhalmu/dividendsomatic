function addFormatters(config) {
  const fmt = (val) =>
    val != null
      ? val.toLocaleString("fi-FI", {
          minimumFractionDigits: 0,
          maximumFractionDigits: 0,
        }) + " €"
      : ""

  const fmtTwo = (val) =>
    val != null
      ? val.toLocaleString("fi-FI", {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        }) + " €"
      : ""

  // Y-axis label formatter
  if (Array.isArray(config.yaxis)) {
    config.yaxis.forEach((axis) => {
      axis.labels = axis.labels || {}
      axis.labels.formatter = fmt
    })
  } else if (config.yaxis) {
    config.yaxis.labels = config.yaxis.labels || {}
    config.yaxis.labels.formatter = fmt
  }

  // Tooltip value formatter (show 2 decimals)
  config.tooltip = config.tooltip || {}
  config.tooltip.y = config.tooltip.y || {}
  config.tooltip.y.formatter = fmtTwo

  return config
}

const ApexChartHook = {
  async mounted() {
    const {default: ApexCharts} = await import("apexcharts")
    const config = addFormatters(JSON.parse(this.el.dataset.chartConfig))
    this.chart = new ApexCharts(this.el, config)
    this.chart.render()

    this.handleEvent(`update-chart-${this.el.id}`, ({series, options}) => {
      if (options) this.chart.updateOptions(options, false, true)
      if (series) this.chart.updateSeries(series, true)
    })
  },
  async updated() {
    if (!this.chart) {
      const {default: ApexCharts} = await import("apexcharts")
      const config = addFormatters(JSON.parse(this.el.dataset.chartConfig))
      this.chart = new ApexCharts(this.el, config)
      this.chart.render()
    }
  },
  destroyed() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }
}

export default ApexChartHook
