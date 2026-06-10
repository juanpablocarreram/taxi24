defmodule TaxiBeWeb.TaxiAllocationJobV2 do
  use GenServer

  @timeout_ms 90_000
  # Fee charged when customer cancels before any driver accepts (configurable)
  @cancellation_fee 5.00
  # Fee charged when customer cancels 3 minutes or less before driver arrival
  @late_cancel_fee 20.00
  # Estimated driver arrival time from acceptance (10 minutes)
  @eta_ms 10 * 60 * 1000
  # Window before arrival in which late cancellation fee applies (3 minutes)
  @late_cancel_threshold_ms 3 * 60 * 1000

  # ─── Public API ────────────────────────────────────────────────────────────

  def start(request, name) do
    GenServer.start(__MODULE__, request, name: name)
  end

  # ─── Initialization ────────────────────────────────────────────────────────

  @impl true
  def init(request) do
    drivers = candidate_taxis()

    Enum.each(drivers, fn driver ->
      TaxiBeWeb.Endpoint.broadcast("driver:#{driver.nickname}", "booking_request", %{
        bookingId: request["booking_id"],
        pickup_address: request["pickup_address"],
        dropoff_address: request["dropoff_address"],
        msg: "Trip from '#{request["pickup_address"]}' to '#{request["dropoff_address"]}'"
      })
    end)

    timer = Process.send_after(self(), :timeout, @timeout_ms)

    {:ok, %{
      request: request,
      pending_drivers: drivers,
      timer: timer,
      status: :pending,
      accepted_driver: nil,
      acceptance_time: nil
    }}
  end

  # ─── Timeout: no driver accepted within 1.5 minutes ────────────────────────

  @impl true
  def handle_info(:timeout, state) do
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
    Process.cancel_timer(state.timer)

    state.pending_drivers
    |> Enum.reject(fn d -> d.nickname == driver_name end)
    |> Enum.each(fn driver ->
      TaxiBeWeb.Endpoint.broadcast("driver:#{driver.nickname}", "booking_timeout", %{
        bookingId: state.request["booking_id"]
      })
    end)

    # booking_ended: false — booking is still active, customer can still cancel
    notify_customer(
      state.request["username"],
      "Driver #{driver_name} is on the way to #{state.request["pickup_address"]}.",
      false
    )

    {:noreply, %{state |
      status: :accepted,
      accepted_driver: driver_name,
      acceptance_time: :erlang.monotonic_time(:millisecond),
      pending_drivers: []
    }}
  end

  @impl true
  def handle_cast({:process_reject, driver_name}, state) do
    remaining = Enum.reject(state.pending_drivers, fn d -> d.nickname == driver_name end)

    if remaining == [] do
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

  # ─── Customer cancellation ──────────────────────────────────────────────────

  @impl true
  def handle_cast({:customer_cancel}, state) do
    {_fee, message} = determine_cancellation(state)

    case state.status do
      :pending ->
        Process.cancel_timer(state.timer)
        Enum.each(state.pending_drivers, fn driver ->
          TaxiBeWeb.Endpoint.broadcast("driver:#{driver.nickname}", "booking_timeout", %{
            bookingId: state.request["booking_id"]
          })
        end)

      :accepted ->
        TaxiBeWeb.Endpoint.broadcast("driver:#{state.accepted_driver}", "booking_cancelled", %{
          bookingId: state.request["booking_id"],
          msg: "The customer cancelled the ride."
        })
    end

    notify_customer(state.request["username"], message)
    {:stop, :normal, state}
  end

  # ─── Cancellation logic ─────────────────────────────────────────────────────

  defp determine_cancellation(%{status: :pending}) do
    {@cancellation_fee,
     "Ride cancelled before a driver accepted. A compensation fee of $#{format_fee(@cancellation_fee)} has been charged."}
  end

  defp determine_cancellation(%{status: :accepted, acceptance_time: acceptance_time}) do
    elapsed_ms = :erlang.monotonic_time(:millisecond) - acceptance_time
    remaining_ms = @eta_ms - elapsed_ms

    if remaining_ms <= @late_cancel_threshold_ms do
      {@late_cancel_fee,
       "Ride cancelled. A late cancellation fee of $#{format_fee(@late_cancel_fee)} has been charged."}
    else
      {0.0, "Ride cancelled. No charge applied."}
    end
  end

  defp format_fee(fee), do: :erlang.float_to_binary(fee, [decimals: 2])

  # ─── Helpers ────────────────────────────────────────────────────────────────

  defp notify_customer(username, message, booking_ended \\ true) do
    TaxiBeWeb.Endpoint.broadcast("customer:#{username}", "booking_request", %{
      msg: message,
      booking_ended: booking_ended
    })
  end

  def candidate_taxis do
    [
      %{nickname: "frodo", latitude: 19.0319783, longitude: -98.2349368},
      %{nickname: "samwise", latitude: 19.0061167, longitude: -98.2697737},
      %{nickname: "pippin", latitude: 19.0092933, longitude: -98.2473716}
    ]
  end
end
