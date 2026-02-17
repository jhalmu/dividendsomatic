import ApexCharts from "apexcharts"

const ApexChartHook = {
  mounted() {
    const config = JSON.parse(this.el.dataset.chartConfig)
    this.chart = new ApexCharts(this.el, config)
    this.chart.render()

    this.handleEvent(`update-chart-${this.el.id}`, ({series, options}) => {
      if (options) this.chart.updateOptions(options, false, true)
      if (series) this.chart.updateSeries(series, true)
    })
  },
  updated() {
    if (!this.chart) {
      const config = JSON.parse(this.el.dataset.chartConfig)
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
