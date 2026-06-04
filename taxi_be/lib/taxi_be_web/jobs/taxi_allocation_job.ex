defmodule TaxiBeWeb.TaxiAllocationJob do
  use GenServer

  # --- API Pública ---
  def start_link(request, name) do
    GenServer.start_link(__MODULE__, request, name: name)
  end

  # --- Inicialización ---
  @impl true
  def init(request) do
    state = %{
      request: request,
      drivers: candidate_taxis(),
      current_driver: nil,
      timer: nil
    }

    # Iniciamos de inmediato la primera asignación
    send(self(), :next_driver)
    {:ok, state}
  end

  # --- Manejo de Mensajes (handle_info) ---

  @impl true
  def handle_info(:next_driver, %{drivers: []} = state) do
    IO.puts("Sin conductores disponibles para el viaje.")
    notify(state.request["username"], "No encontramos taxis disponibles.")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:next_driver, %{drivers: [driver | remaining]} = state) do
    IO.puts("Ofreciendo viaje a: #{driver.nickname}")

    # Enviar la alerta de viaje al frontend del conductor seleccionado
    TaxiBeWeb.Endpoint.broadcast("driver:#{driver.nickname}", "booking_request", %{
      bookingId: state.request["booking_id"],
      pickup_address: state.request["pickup_address"],
      dropoff_address: state.request["dropoff_address"],
      msg: "Viaje de '#{state.request["pickup_address"]}' a '#{state.request["dropoff_address"]}'"
    })

    timer = Process.send_after(self(), :timeout, 10000)

    {:noreply, %{state | drivers: remaining, current_driver: driver, timer: timer}}
  end


  @impl true
  def handle_info(:timeout, state) do
    IO.puts("Tiempo agotado (10s) para #{state.current_driver.nickname}. Saltando...")

    # Avisar al React del conductor actual que remueva la tarjeta de su pantalla
    TaxiBeWeb.Endpoint.broadcast("driver:#{state.current_driver.nickname}", "booking_timeout", %{
      bookingId: state.request["booking_id"]
    })

    # Forzar el brinco al siguiente conductor inmediatamente
    send(self(), :next_driver)
    {:noreply, state}
  end

  # --- Decisiones del Conductor (handle_cast) ---

  @impl true
  def handle_cast({:process_accept, driver_name}, state) do
    IO.puts("¡Viaje aceptado por #{driver_name}!")
    cancel_timer(state.timer)

    msg = "Tu conductor #{driver_name} va en camino a #{state.request["pickup_address"]}."
    notify(state.request["username"], msg)

    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:process_reject, driver_name}, state) do
    IO.puts("#{driver_name} rechazó el viaje. Buscando al siguiente...")
    cancel_timer(state.timer)

    # Si rechaza, no esperamos los 10 segundos; saltamos ya al siguiente
    send(self(), :next_driver)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:process_cancel, _driver_name}, state) do
    cancel_timer(state.timer)
    {:stop, :normal, state}
  end

  # --- Funciones Auxiliares ---
  defp notify(customer_username, message) do
    TaxiBeWeb.Endpoint.broadcast("customer:#{customer_username}", "booking_request", %{msg: message})
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  def candidate_taxis do
    [
      %{nickname: "frodo", latitude: 19.0319783, longitude: -98.2349368},
      %{nickname: "samwise", latitude: 19.0061167, longitude: -98.2697737},
      %{nickname: "pippin", latitude: 19.0092933, longitude: -98.2473716}
    ]
  end
end
