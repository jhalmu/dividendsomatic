defmodule DividendsomaticWeb.PortfolioLive do
  use DividendsomaticWeb, :live_view

  alias Dividendsomatic.Portfolio

  def mount(_params, _session, socket) do
    snapshot = Portfolio.get_latest_snapshot()

    socket =
      socket
      |> assign(:snapshot, snapshot)
      |> assign(:total_value, calculate_total_value(snapshot))

    {:ok, socket}
  end

  def handle_event("navigate", %{"direction" => "prev"}, socket) do
    current_date = socket.assigns.snapshot.report_date
    snapshot = Portfolio.get_previous_snapshot(current_date)

    socket =
      case snapshot do
        nil ->
          put_flash(socket, :info, "No earlier snapshot available")

        snapshot ->
          socket
          |> assign(:snapshot, snapshot)
          |> assign(:total_value, calculate_total_value(snapshot))
      end

    {:noreply, socket}
  end

  def handle_event("navigate", %{"direction" => "next"}, socket) do
    current_date = socket.assigns.snapshot.report_date
    snapshot = Portfolio.get_next_snapshot(current_date)

    socket =
      case snapshot do
        nil ->
          put_flash(socket, :info, "No later snapshot available")

        snapshot ->
          socket
          |> assign(:snapshot, snapshot)
          |> assign(:total_value, calculate_total_value(snapshot))
      end

    {:noreply, socket}
  end

  def handle_event("key", %{"key" => "ArrowLeft"}, socket) do
    handle_event("navigate", %{"direction" => "prev"}, socket)
  end

  def handle_event("key", %{"key" => "ArrowRight"}, socket) do
    handle_event("navigate", %{"direction" => "next"}, socket)
  end

  def handle_event("key", _params, socket) do
    {:noreply, socket}
  end

  defp calculate_total_value(nil), do: Decimal.new("0")

  defp calculate_total_value(snapshot) do
    snapshot.holdings
    |> Enum.map(& &1.position_value)
    |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
  end

  defp format_currency(nil), do: "-"

  defp format_currency(amount) do
    amount
    |> Decimal.to_float()
    |> :erlang.float_to_binary(decimals: 2)
  end

  defp format_date(date) do
    Calendar.strftime(date, "%Y-%m-%d")
  end
end
