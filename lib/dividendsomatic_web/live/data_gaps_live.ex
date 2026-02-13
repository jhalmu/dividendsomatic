defmodule DividendsomaticWeb.DataGapsLive do
  use DividendsomaticWeb, :live_view

  import DividendsomaticWeb.Helpers.FormatHelpers

  alias Dividendsomatic.Portfolio

  @impl true
  def mount(_params, _session, socket) do
    coverage = Portfolio.broker_coverage()
    all_stock_gaps = Portfolio.stock_gaps()
    dividend_gaps = Portfolio.dividend_gaps()
    costs_summary = Portfolio.costs_summary()

    socket =
      socket
      |> assign(:coverage, coverage)
      |> assign(:all_stock_gaps, all_stock_gaps)
      |> assign(:dividend_gaps, dividend_gaps)
      |> assign(:costs_summary, costs_summary)
      |> assign(:current_only, false)
      |> assign(:search, "")
      |> assign(:sort_by, :name)
      |> assign(:sort_dir, :asc)
      |> assign(:show_dividends, false)
      |> apply_filters_and_sort()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_filter", _params, socket) do
    current_only = !socket.assigns.current_only
    all_stock_gaps = Portfolio.stock_gaps(current_only: current_only)

    socket =
      socket
      |> assign(:current_only, current_only)
      |> assign(:all_stock_gaps, all_stock_gaps)
      |> apply_filters_and_sort()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    socket =
      socket
      |> assign(:search, search)
      |> apply_filters_and_sort()

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)

    {sort_by, sort_dir} =
      if socket.assigns.sort_by == field do
        {field, toggle_dir(socket.assigns.sort_dir)}
      else
        {field, default_dir(field)}
      end

    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:sort_dir, sort_dir)
      |> apply_filters_and_sort()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_dividends", _params, socket) do
    {:noreply, assign(socket, :show_dividends, !socket.assigns.show_dividends)}
  end

  defp apply_filters_and_sort(socket) do
    gaps = socket.assigns.all_stock_gaps
    search = String.downcase(socket.assigns.search)

    filtered =
      if search == "" do
        gaps
      else
        Enum.filter(gaps, fn g ->
          String.contains?(String.downcase(g.name), search) ||
            String.contains?(String.downcase(g.isin), search) ||
            String.contains?(String.downcase(Map.get(g, :symbol, "")), search)
        end)
      end

    sorted = sort_gaps(filtered, socket.assigns.sort_by, socket.assigns.sort_dir)
    summary = compute_summary(filtered)

    socket
    |> assign(:stock_gaps, sorted)
    |> assign(:summary, summary)
  end

  defp sort_gaps(gaps, :name, dir), do: Enum.sort_by(gaps, & &1.name, sort_fn(dir))
  defp sort_gaps(gaps, :gap_days, dir), do: Enum.sort_by(gaps, & &1.gap_days, sort_fn(dir))

  defp sort_gaps(gaps, :brokers, dir),
    do: Enum.sort_by(gaps, &length(&1.brokers), sort_fn(dir))

  defp sort_gaps(gaps, _field, dir), do: Enum.sort_by(gaps, & &1.name, sort_fn(dir))

  defp sort_fn(:asc), do: :asc
  defp sort_fn(:desc), do: :desc

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  defp default_dir(:gap_days), do: :desc
  defp default_dir(_), do: :asc

  defp sort_indicator(field, current, dir) when field == current do
    if dir == :asc, do: Phoenix.HTML.raw("&#9650;"), else: Phoenix.HTML.raw("&#9660;")
  end

  defp sort_indicator(_field, _current, _dir), do: ""

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
    nordnet_only = Enum.count(stock_gaps, fn g -> g.brokers == ["nordnet"] end)
    ibkr_only = Enum.count(stock_gaps, fn g -> g.brokers == ["ibkr"] end)
    total_gap_days = Enum.reduce(stock_gaps, 0, fn g, acc -> acc + g.gap_days end)

    %{
      total_isins: total,
      with_gap: with_gap,
      both_brokers: both_brokers,
      nordnet_only: nordnet_only,
      ibkr_only: ibkr_only,
      total_gap_days: total_gap_days
    }
  end
end
