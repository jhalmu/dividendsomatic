defmodule DividendsomaticWeb.PortfolioLive do
  use DividendsomaticWeb, :live_view

  alias Dividendsomatic.Portfolio

  @impl true
  def mount(_params, _session, socket) do
    snapshot = Portfolio.get_latest_snapshot()

    socket =
      socket
      |> assign(:snapshot, snapshot)
      |> assign(:page_title, format_page_title(snapshot))

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"date" => date_string}, _uri, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        snapshot = Portfolio.get_snapshot_by_date(date)
        {:noreply, assign(socket, snapshot: snapshot, page_title: format_page_title(snapshot))}
      
      _ ->
        {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("navigate_prev", _params, socket) do
    case socket.assigns.snapshot do
      nil -> {:noreply, socket}
      snapshot ->
        case Portfolio.get_previous_snapshot(snapshot.report_date) do
          nil -> {:noreply, socket}
          prev_snapshot ->
            {:noreply, push_patch(socket, to: ~p"/portfolio/#{prev_snapshot.report_date}")}
        end
    end
  end

  @impl true
  def handle_event("navigate_next", _params, socket) do
    case socket.assigns.snapshot do
      nil -> {:noreply, socket}
      snapshot ->
        case Portfolio.get_next_snapshot(snapshot.report_date) do
          nil -> {:noreply, socket}
          next_snapshot ->
            {:noreply, push_patch(socket, to: ~p"/portfolio/#{next_snapshot.report_date}")}
        end
    end
  end

  # Keyboard navigation
  @impl true
  def handle_event("keydown", %{"key" => "ArrowLeft"}, socket) do
    handle_event("navigate_prev", %{}, socket)
  end

  def handle_event("keydown", %{"key" => "ArrowRight"}, socket) do
    handle_event("navigate_next", %{}, socket)
  end

  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end

  defp format_page_title(nil), do: "Portfolio"
  defp format_page_title(snapshot) do
    "Portfolio - #{Calendar.strftime(snapshot.report_date, "%d.%m.%Y")}"
  end

  defp calculate_totals(holdings) do
    holdings
    |> Enum.reduce(%{eur: Decimal.new("0"), usd: Decimal.new("0")}, fn holding, acc ->
      value = holding.position_value || Decimal.new("0")
      currency = holding.currency_primary
      
      case currency do
        "EUR" -> %{acc | eur: Decimal.add(acc.eur, value)}
        "USD" -> %{acc | usd: Decimal.add(acc.usd, value)}
        _ -> acc
      end
    end)
  end

  defp format_currency(amount, currency) do
    amount
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> then(&"#{currency} #{&1}")
  end

  defp format_decimal(nil), do: "-"
  defp format_decimal(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end
end
