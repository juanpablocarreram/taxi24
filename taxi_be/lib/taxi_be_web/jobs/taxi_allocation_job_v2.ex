defmodule TaxiBeWeb.TaxiAllocationJobV2 do
  use GenServer

  # 1.5 minutes in milliseconds
  @timeout_ms 90_000

  # ─── Public API ────────────────────────────────────────────────────────────

  def start(request, name) do
    GenServer.start(__MODULE__, request, name: name)
  end

  # ─── Initialization ────────────────────────────────────────────────────────

  @impl true
  def init(request) do
    drivers = candidate_taxis()

    # Notify ALL three drivers at the same time
    Enum.each(drivers, fn driver ->
      TaxiBeWeb.Endpoint.broadcast("driver:#{driver.nickname}", "booking_request", %{
        bookingId: request["booking_id"],
        pickup_address: request["pickup_address"],
        dropoff_address: request["dropoff_address"],
        msg: "Trip from '#{request["pickup_address"]}' to '#{request["dropoff_address"]}'"
      })
    end)

    # One shared timer for all three drivers — 1.5 minutes
    timer = Process.send_after(self(), :timeout, @timeout_ms)

    state = %{
      request: request,
      # Tracks which drivers have not yet replied (accept or reject)
      pending_drivers: drivers,
      timer: timer
    }

    {:ok, state}
  end

  # ─── Timeout: no driver accepted within 1.5 minutes ────────────────────────

  @impl true
  def handle_info(:timeout, state) do
    IO.puts("Timeout reached. No driver accepted the ride.")

    # Tell every driver still waiting to remove the booking from their screen
    Enum.each(state.pending_drivers, fn driver ->
      TaxiBeWeb.Endpoint.broadcast("driver:#{driver.nickname}", "booking_timeout", %{
        bookingId: state.request["booking_id"]
      })
    end)

    notify_customer(state.request["username"], "No driver accepted your ride. Please try again.")

    {:stop, :normal, state}
  end

  # ─── Driver decisions ───────────────────────────────────────────────────────

  @impl true
  def handle_cast({:process_accept, driver_name}, state) do
    IO.puts("#{driver_name} accepted the ride!")
    Process.cancel_timer(state.timer)

    # Tell all OTHER pending drivers that the booking is already taken
    state.pending_drivers
    |> Enum.reject(fn d -> d.nickname == driver_name end)
    |> Enum.each(fn driver ->
      TaxiBeWeb.Endpoint.broadcast("driver:#{driver.nickname}", "booking_timeout", %{
        bookingId: state.request["booking_id"]
      })
    end)

    notify_customer(
      state.request["username"],
      "Driver #{driver_name} is on the way to #{state.request["pickup_address"]}."
    )

    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:process_reject, driver_name}, state) do
    IO.puts("#{driver_name} rejected the ride.")

    remaining = Enum.reject(state.pending_drivers, fn d -> d.nickname == driver_name end)

    if remaining == [] do
      # Every driver said no — cancel the timer and tell the customer
      Process.cancel_timer(state.timer)
      notify_customer(state.request["username"], "All drivers rejected your ride. Please try again.")
      {:stop, :normal, state}
    else
      {:noreply, %{state | pending_drivers: remaining}}
    end
  end

  @impl true
  def handle_cast({:process_cancel, _driver_name}, state) do
    Process.cancel_timer(state.timer)
    {:stop, :normal, state}
  end

  # ─── Helpers ────────────────────────────────────────────────────────────────

  defp notify_customer(username, message) do
    TaxiBeWeb.Endpoint.broadcast("customer:#{username}", "booking_request", %{msg: message})
  end

  def candidate_taxis do
    [
      %{nickname: "frodo", latitude: 19.0319783, longitude: -98.2349368},
      %{nickname: "samwise", latitude: 19.0061167, longitude: -98.2697737},
      %{nickname: "pippin", latitude: 19.0092933, longitude: -98.2473716}
    ]
  end
end
