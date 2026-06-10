import React, {useEffect, useState} from 'react';
import Button from '@mui/material/Button'

import socket from '../services/taxi_socket';
import { TextField, Box, Typography, Alert, CircularProgress } from '@mui/material';

function Customer(props) {
  let [pickupAddress, setPickupAddress] = useState("Tecnologico de Monterrey, campus Puebla, Mexico");
  let [dropOffAddress, setDropOffAddress] = useState("Triangulo Las Animas, Puebla, Mexico");
  let [msg, setMsg] = useState("");
  let [msg1, setMsg1] = useState("");
  let [loading, setLoading] = useState(false);
  let [bookingStatus, setBookingStatus] = useState("idle"); // idle, sending, success, error
  let [bookingId, setBookingId] = useState(null);
  let [bookingActive, setBookingActive] = useState(false);

  useEffect(() => {
    let channel = socket.channel("customer:" + props.username, {token: "123"});
    channel.on("greetings", data => console.log(data));
    channel.on("booking_request", dataFromPush => {
      console.log("Customer received update:", dataFromPush);
      setMsg1(dataFromPush.msg);
      if (dataFromPush.booking_ended !== false) {
        setBookingActive(false);
        setBookingId(null);
      }
    });
    channel.join();
    console.log(`Customer ${props.username} connected to channel`);
    return () => { channel.leave(); };
  }, [props.username]);

  let submit = () => {
    setLoading(true);
    setBookingStatus("sending");
    setMsg("");
    setMsg1("");
    setBookingId(null);
    setBookingActive(false);

    console.log("Customer submitting booking:", {pickup_address: pickupAddress, dropoff_address: dropOffAddress, username: props.username});

    fetch(`http://localhost:4000/api/bookings`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({pickup_address: pickupAddress, dropoff_address: dropOffAddress, username: props.username})
    })
      .then(resp => {
        if (!resp.ok) throw new Error(`HTTP error! status: ${resp.status}`);
        return resp.json();
      })
      .then(dataFromPOST => {
        console.log("Booking submitted successfully:", dataFromPOST);
        setMsg(dataFromPOST.msg);
        setBookingStatus("success");
        setLoading(false);
        setBookingId(dataFromPOST.bookingId);
        setBookingActive(true);
      })
      .catch(error => {
        console.error("Error submitting booking:", error);
        setMsg(`Error: ${error.message}`);
        setBookingStatus("error");
        setLoading(false);
      });
  };

  let cancelBooking = () => {
    if (!bookingId) return;
    console.log("Customer cancelling booking:", bookingId);

    fetch(`http://localhost:4000/api/bookings/${bookingId}`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({action: "customer_cancel"})
    })
      .then(resp => resp.json())
      .then(data => {
        console.log("Cancel response:", data);
        setBookingActive(false);
        setBookingId(null);
      })
      .catch(error => console.error("Error cancelling booking:", error));
  };

  return (
    <div style={{textAlign: "center", borderStyle: "solid", padding: "20px", margin: "10px"}}>
      <Typography variant="h6">Customer: {props.username}</Typography>
      <div style={{marginTop: "20px"}}>
        <TextField
          id="pickup-address"
          label="Pickup address"
          fullWidth
          onChange={ev => setPickupAddress(ev.target.value)}
          value={pickupAddress}
          disabled={loading || bookingActive}
          style={{marginBottom: "10px"}}
        />
        <TextField
          id="dropoff-address"
          label="Drop off address"
          fullWidth
          onChange={ev => setDropOffAddress(ev.target.value)}
          value={dropOffAddress}
          disabled={loading || bookingActive}
          style={{marginBottom: "10px"}}
        />
        <Box style={{display: "flex", gap: "10px", justifyContent: "center", marginTop: "10px"}}>
          <Button
            onClick={submit}
            variant="contained"
            color="primary"
            disabled={loading || bookingActive}
          >
            {loading ? <CircularProgress size={24} /> : "Submit Booking"}
          </Button>
          {bookingActive && (
            <Button
              onClick={cancelBooking}
              variant="outlined"
              color="error"
            >
              Cancel Booking
            </Button>
          )}
        </Box>
      </div>

      {msg && (
        <Alert severity={bookingStatus === "success" ? "success" : "error"} style={{marginTop: "15px"}}>
          {msg}
        </Alert>
      )}

      {msg1 && (
        <Alert severity="info" style={{marginTop: "10px"}}>
          <strong>Driver Update:</strong> {msg1}
        </Alert>
      )}
    </div>
  );
}

export default Customer;
