defmodule TaxiBeWeb.BookingController do
  use TaxiBeWeb, :controller
  alias TaxiBeWeb.TaxiAllocationJobV2

  def create(conn, req) do
    IO.inspect(req)
    booking_id = UUID.uuid1()
    TaxiAllocationJobV2.start(
      req |> Map.put("booking_id", booking_id),
      String.to_atom(booking_id)
    )
    conn
    |> put_resp_header("Location", "/api/bookings/" <> booking_id)
    |> put_status(:created)
    |> json(%{msg: "Booking submitted, wait for a driver to accept your request", bookingId: booking_id})
  end

  def update(conn, %{"action" => "accept", "username" => username, "id" => id}) do
    IO.inspect("'#{username}' is accepting a booking request")
    GenServer.cast(String.to_atom(id), {:process_accept, username})
    json(conn, %{msg: "We will process your acceptance"})
  end

  def update(conn, %{"action" => "reject", "username" => username, "id" => id}) do
    IO.inspect("'#{username}' is rejecting a booking request")
    GenServer.cast(String.to_atom(id), {:process_reject, username})
    json(conn, %{msg: "We will process your rejection"})
  end

  def update(conn, %{"action" => "cancel", "username" => username, "id" => id}) do
    IO.inspect("'#{username}' is cancelling a booking request")
    GenServer.cast(String.to_atom(id), {:process_cancel, username})
    json(conn, %{msg: "We will process your cancelation"})
  end

  def update(conn, %{"action" => "customer_cancel", "id" => id}) do
    atom_id = String.to_atom(id)
    case GenServer.whereis(atom_id) do
      nil ->
        json(conn, %{msg: "Booking not found or already ended"})
      _pid ->
        GenServer.cast(atom_id, {:customer_cancel})
        json(conn, %{msg: "Cancellation request received"})
    end
  end
end
