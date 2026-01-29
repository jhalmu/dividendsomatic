defmodule DividendsomaticWeb.PortfolioLive do
  use DividendsomaticWeb, :live_view
  alias Dividendsomatic.Portfolio

  @impl true
  def mount(_params, _session, socket) do
    snapshot = Portfolio.get_latest_snapshot()
    
    socket =
      socket
      |> assign(:snapshot, snapshot)
      |> assign(:loading, false)
    
    {:ok, socket}
  end

  @impl true
  def handle_event("navigate", %{"direction" => "prev"}, socket) do
    if snapshot = socket.assigns.snapshot do
      case Portfolio.get_previous_snapshot(snapshot.report_date) do
        nil -> {:noreply, socket}
        prev_snapshot -> {:noreply, assign(socket, :snapshot, prev_snapshot)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("navigate", %{"direction" => "next"}, socket) do
    if snapshot = socket.assigns.snapshot do
      case Portfolio.get_next_snapshot(snapshot.report_date) do
        nil -> {:noreply, socket}
        next_snapshot -> {:noreply, assign(socket, :snapshot, next_snapshot)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 p-[var(--space-md)]">
      <div class="max-w-7xl mx-auto">
        <%= if @snapshot do %>
          <!-- Header with Navigation -->
          <div class="card bg-base-100 shadow-xl mb-[var(--space-md)]">
            <div class="card-body">
              <div class="flex items-center justify-between">
                <div>
                  <h1 class="text-[var(--text-2xl)] font-bold">Portfolio Snapshot</h1>
                  <p class="text-[var(--text-lg)] text-base-content/70">
                    <%= Calendar.strftime(@snapshot.report_date, "%B %d, %Y") %>
                  </p>
                </div>
                
                <div class="flex gap-[var(--space-sm)]">
                  <button 
                    phx-click="navigate" 
                    phx-value-direction="prev"
                    class="btn btn-circle btn-primary"
                    title="Previous day (←)"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
                    </svg>
                  </button>
                  
                  <button 
                    phx-click="navigate" 
                    phx-value-direction="next"
                    class="btn btn-circle btn-primary"
                    title="Next day (→)"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                    </svg>
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- Summary Cards -->
          <div class="grid grid-cols-1 md:grid-cols-3 gap-[var(--space-md)] mb-[var(--space-md)]">
            <div class="card bg-base-100 shadow-xl">
              <div class="card-body">
                <h2 class="card-title text-[var(--text-base)]">Total Holdings</h2>
                <p class="text-[var(--text-2xl)] font-bold"><%= length(@snapshot.holdings) %></p>
              </div>
            </div>
            
            <div class="card bg-base-100 shadow-xl">
              <div class="card-body">
                <h2 class="card-title text-[var(--text-base)]">Total Value</h2>
                <p class="text-[var(--text-2xl)] font-bold">
                  <%= format_total_value(@snapshot.holdings) %>
                </p>
              </div>
            </div>
            
            <div class="card bg-base-100 shadow-xl">
              <div class="card-body">
                <h2 class="card-title text-[var(--text-base)]">Unrealized P&L</h2>
                <p class={[
                  "text-[var(--text-2xl)] font-bold",
                  pnl_color(@snapshot.holdings)
                ]}>
                  <%= format_total_pnl(@snapshot.holdings) %>
                </p>
              </div>
            </div>
          </div>

          <!-- Holdings Table -->
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="card-title mb-[var(--space-sm)]">Holdings</h2>
              
              <div class="overflow-x-auto">
                <table class="table table-zebra">
                  <thead>
                    <tr>
                      <th>Symbol</th>
                      <th>Description</th>
                      <th class="text-right">Quantity</th>
                      <th class="text-right">Price</th>
                      <th class="text-right">Value</th>
                      <th class="text-right">Cost Basis</th>
                      <th class="text-right">P&L</th>
                      <th class="text-right">% of NAV</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for holding <- @snapshot.holdings do %>
                      <tr>
                        <td class="font-mono font-bold"><%= holding.symbol %></td>
                        <td><%= holding.description %></td>
                        <td class="text-right font-mono"><%= format_number(holding.quantity) %></td>
                        <td class="text-right font-mono">
                          <%= holding.currency_primary %> <%= format_decimal(holding.mark_price) %>
                        </td>
                        <td class="text-right font-mono font-bold">
                          <%= holding.currency_primary %> <%= format_decimal(holding.position_value) %>
                        </td>
                        <td class="text-right font-mono">
                          <%= holding.currency_primary %> <%= format_decimal(holding.cost_basis_money) %>
                        </td>
                        <td class={["text-right font-mono font-bold", pnl_color_single(holding.fifo_pnl_unrealized)]}>
                          <%= format_pnl(holding.fifo_pnl_unrealized) %>
                        </td>
                        <td class="text-right font-mono">
                          <%= format_decimal(holding.percent_of_nav) %>%
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        <% else %>
          <!-- Empty State -->
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body items-center text-center">
              <h2 class="card-title">No Portfolio Data</h2>
              <p>Import a CSV file to get started:</p>
              <code class="bg-base-200 p-[var(--space-sm)] rounded mt-[var(--space-sm)]">
                mix import.csv path/to/file.csv
              </code>
            </div>
          </div>
        <% end %>
      </div>
    </div>

    <!-- Keyboard Navigation -->
    <div 
      phx-window-keydown="navigate"
      phx-key="ArrowLeft"
      phx-value-direction="prev"
      style="display: none;"
    ></div>
    <div 
      phx-window-keydown="navigate"
      phx-key="ArrowRight"
      phx-value-direction="next"
      style="display: none;"
    ></div>
    """
  end

  ## Helpers

  defp format_decimal(nil), do: "0.00"
  defp format_decimal(decimal) do
    decimal
    |> Decimal.to_string(:normal)
    |> String.replace(~r/(\.\d{2})\d+$/, "\\1")
  end

  defp format_number(nil), do: "0"
  defp format_number(decimal) do
    Decimal.to_string(decimal, :normal)
  end

  defp format_pnl(nil), do: "0.00"
  defp format_pnl(decimal) do
    value = Decimal.to_float(decimal)
    sign = if value >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(abs(value), decimals: 2)}"
  end

  defp format_total_value(holdings) do
    # Group by currency and sum
    holdings
    |> Enum.group_by(& &1.currency_primary)
    |> Enum.map(fn {currency, items} ->
      total = 
        items
        |> Enum.map(& &1.position_value)
        |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
      
      "#{currency} #{format_decimal(total)}"
    end)
    |> Enum.join(" | ")
  end

  defp format_total_pnl(holdings) do
    total =
      holdings
      |> Enum.map(& &1.fifo_pnl_unrealized)
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
    
    format_pnl(total)
  end

  defp pnl_color(holdings) do
    total =
      holdings
      |> Enum.map(& &1.fifo_pnl_unrealized)
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)
    
    pnl_color_single(total)
  end

  defp pnl_color_single(decimal) do
    if Decimal.negative?(decimal) do
      "text-error"
    else
      "text-success"
    end
  end
end
