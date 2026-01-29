defmodule DividendsomaticWeb.PortfolioLive do
  use DividendsomaticWeb, :live_view
  
  alias Dividendsomatic.Portfolio

  @impl true
  def mount(_params, _session, socket) do
    snapshot = Portfolio.get_latest_snapshot()
    
    {:ok, assign(socket, 
      snapshot: snapshot,
      loading: false
    )}
  end

  @impl true
  def handle_event("navigate", %{"direction" => "prev"}, socket) do
    case socket.assigns.snapshot do
      nil -> {:noreply, socket}
      snapshot ->
        case Portfolio.get_previous_snapshot(snapshot.report_date) do
          nil -> {:noreply, put_flash(socket, :info, "No earlier snapshots")}
          prev_snapshot -> {:noreply, assign(socket, snapshot: prev_snapshot)}
        end
    end
  end

  def handle_event("navigate", %{"direction" => "next"}, socket) do
    case socket.assigns.snapshot do
      nil -> {:noreply, socket}
      snapshot ->
        case Portfolio.get_next_snapshot(snapshot.report_date) do
          nil -> {:noreply, put_flash(socket, :info, "No later snapshots")}
          next_snapshot -> {:noreply, assign(socket, snapshot: next_snapshot)}
        end
    end
  end

  @impl true
  def handle_event("key_down", %{"key" => "ArrowLeft"}, socket) do
    handle_event("navigate", %{"direction" => "prev"}, socket)
  end

  def handle_event("key_down", %{"key" => "ArrowRight"}, socket) do
    handle_event("navigate", %{"direction" => "next"}, socket)
  end

  def handle_event("key_down", _params, socket), do: {:noreply, socket}

  # Helper functions
  defp format_currency(value, currency) when is_struct(value, Decimal) do
    num = Decimal.to_float(value)
    case currency do
      "EUR" -> "€#{:erlang.float_to_binary(num, decimals: 2)}"
      "USD" -> "$#{:erlang.float_to_binary(num, decimals: 2)}"
      _ -> "#{:erlang.float_to_binary(num, decimals: 2)} #{currency}"
    end
  end

  defp format_percent(value) when is_struct(value, Decimal) do
    num = Decimal.to_float(value)
    "#{:erlang.float_to_binary(num, decimals: 2)}%"
  end

  defp pnl_class(value) when is_struct(value, Decimal) do
    if Decimal.negative?(value), do: "text-error", else: "text-success"
  end
end
