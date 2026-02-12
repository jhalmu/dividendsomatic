defmodule DividendsomaticWeb.DataGapsLive do
  use DividendsomaticWeb, :live_view

  import DividendsomaticWeb.Helpers.FormatHelpers

  alias Dividendsomatic.Portfolio

  @impl true
  def mount(_params, _session, socket) do
    coverage = Portfolio.broker_coverage()
    stock_gaps = Portfolio.stock_gaps()
    dividend_gaps = Portfolio.dividend_gaps()
    costs_summary = Portfolio.costs_summary()

    summary = compute_summary(stock_gaps)

    socket =
      socket
      |> assign(:coverage, coverage)
      |> assign(:stock_gaps, stock_gaps)
      |> assign(:dividend_gaps, dividend_gaps)
      |> assign(:costs_summary, costs_summary)
      |> assign(:summary, summary)
      |> assign(:current_only, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_filter", _params, socket) do
    current_only = !socket.assigns.current_only
    stock_gaps = Portfolio.stock_gaps(current_only: current_only)
    summary = compute_summary(stock_gaps)

    {:noreply,
     socket
     |> assign(:current_only, current_only)
     |> assign(:stock_gaps, stock_gaps)
     |> assign(:summary, summary)}
  end

  defp format_cost_type("commission"), do: "Commission"
  defp format_cost_type("withholding_tax"), do: "Withholding Tax"
  defp format_cost_type("foreign_tax"), do: "Foreign Tax"
  defp format_cost_type("loan_interest"), do: "Loan Interest"
  defp format_cost_type("capital_interest"), do: "Capital Interest"
  defp format_cost_type(other), do: String.capitalize(other)

  defp compute_summary(stock_gaps) do
    total = length(stock_gaps)
    with_gap = Enum.count(stock_gaps, & &1.has_gap)
    both_brokers = Enum.count(stock_gaps, fn g -> length(g.brokers) == 2 end)
    total_gap_days = Enum.reduce(stock_gaps, 0, fn g, acc -> acc + g.gap_days end)

    %{
      total_isins: total,
      with_gap: with_gap,
      both_brokers: both_brokers,
      total_gap_days: total_gap_days
    }
  end
end
