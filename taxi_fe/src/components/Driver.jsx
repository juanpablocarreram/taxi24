import React, {useEffect, useState} from 'react';
import Button from '@mui/material/Button';

import socket from '../services/taxi_socket';
import { Card, CardContent, Typography, Box, Chip, Alert } from '@mui/material';

function Driver(props) {
  let [requests, setRequests] = useState([]);
  let [currentIndex, setCurrentIndex] = useState(0);
  let [processingId, setProcessingId] = useState(null);
  let [connectionStatus, setConnectionStatus] = useState("connecting");
  let [driverNotification, setDriverNotification] = useState(null);

  useEffect(() => {
    console.log(`[Driver ${props.username}] Initializing WebSocket connection...`);
    
    let channel = socket.channel("driver:" + props.username, {token: "123"});
    
    channel.on("booking_request", data => {
      console.log(`[Driver ${props.username}] Received new booking request:`, data);
      setDriverNotification(null);
      setRequests(prev => {
        const newRequests = [...prev, {
          bookingId: data.bookingId,
          message: data.msg,
          pickupAddress: data.pickup_address,
          dropoffAddress: data.dropoff_address,
          timestamp: new Date().toLocaleTimeString()
        }];
        console.log(`[Driver ${props.username}] Updated requests queue. Total: ${newRequests.length}`);
        return newRequests;
      });
    });
    channel.on("booking_cancelled", data => {
      console.log(`[Driver ${props.username}] Booking ${data.bookingId} cancelled by customer.`);
      setRequests(prev => prev.filter(req => req.bookingId !== data.bookingId));
      setCurrentIndex(prev => (prev > 0 ? prev - 1 : 0));
      setDriverNotification(data.msg || "The customer cancelled the booking.");
    });
    channel.on("booking_timeout", data => {
      console.log(`[Driver ${props.username}] Request ${data.bookingId} timed out on server.`);
      setRequests(prev => prev.filter(req => req.bookingId !== data.bookingId));
      setCurrentIndex(prev => (prev > 0 ? prev - 1 : 0));
    });
    channel.on("phx_reply", (status, response) => {
      console.log(`[Driver ${props.username}] Channel reply:`, status, response);
    });

    channel.on("phx_error", (reason) => {
      console.error(`[Driver ${props.username}] Channel error:`, reason);
      setConnectionStatus("error");
    });

    channel.on("phx_close", (reason) => {
      console.log(`[Driver ${props.username}] Channel closed:`, reason);
      setConnectionStatus("closed");
    });
    
    channel.join()
      .receive("ok", () => {
        console.log(`[Driver ${props.username}] Successfully connected to channel`);
        setConnectionStatus("connected");
      })
      .receive("error", (reason) => {
        console.error(`[Driver ${props.username}] Failed to join channel:`, reason);
        setConnectionStatus("error");
      });

    return () => {
      console.log(`[Driver ${props.username}] Cleaning up channel`);
      channel.leave();
    };
  }, [props.username]);

  let currentRequest = requests[currentIndex];

  let reply = (decision) => {
    if (!currentRequest) {
      console.error("No current request to reply to");
      return;
    }
    
    setProcessingId(currentRequest.bookingId);
    console.log(`[Driver ${props.username}] Sending ${decision} for booking:`, currentRequest.bookingId);
    
    fetch(`http://localhost:4000/api/bookings/${currentRequest.bookingId}`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({action: decision, username: props.username})
    })
      .then(resp => {
        if (!resp.ok) throw new Error(`HTTP error! status: ${resp.status}`);
        return resp.json();
      })
      .then((data) => {
        console.log(`[Driver ${props.username}] Successfully ${decision}ed booking:`, data);
        // Remove the current request and move to the next one
        setRequests(prev => prev.filter((_, idx) => idx !== currentIndex));
        if (currentIndex > 0) {
          setCurrentIndex(currentIndex - 1);
        }
        setProcessingId(null);
      })
      .catch(error => {
        console.error(`[Driver ${props.username}] Error ${decision}ing booking:`, error);
        setProcessingId(null);
      });
  };

  let handleNext = () => {
    if (currentIndex < requests.length - 1) {
      setCurrentIndex(currentIndex + 1);
    }
  };

  let handlePrevious = () => {
    if (currentIndex > 0) {
      setCurrentIndex(currentIndex - 1);
    }
  };

  return (
    <div style={{textAlign: "center", borderStyle: "solid", padding: "20px", margin: "10px"}}>
      <Typography variant="h6">Driver: {props.username}</Typography>
      
      <Box style={{marginBottom: "10px"}}>
        <Chip 
          label={`Connection: ${connectionStatus}`}
          color={connectionStatus === "connected" ? "success" : connectionStatus === "error" ? "error" : "warning"}
          size="small"
          style={{marginRight: "10px"}}
        />
        <Chip 
          label={`${requests.length} Request${requests.length !== 1 ? 's' : ''} Pending`}
          color={requests.length > 0 ? "error" : "default"}
          size="small"
        />
      </Box>
      
      {driverNotification && (
        <Alert severity="warning" style={{marginBottom: "10px"}}>
          {driverNotification}
        </Alert>
      )}

      {requests.length > 0 ? (
        <div>
          <Box style={{backgroundColor: "lavender", minHeight: "250px", padding: "20px"}}>
            <Card variant="outlined" style={{margin: "auto", width: "100%", maxWidth: "600px"}}>
              <CardContent>
                <Box style={{marginBottom: "15px", textAlign: "left"}}>
                  <Typography variant="caption" color="textSecondary">
                    Request {currentIndex + 1} of {requests.length} • {currentRequest?.timestamp}
                  </Typography>
                </Box>
                <Typography variant="body1" style={{marginBottom: "15px", minHeight: "60px", textAlign: "left"}}>
                  {currentRequest?.message}
                </Typography>
                {currentRequest?.pickupAddress && (
                  <Typography variant="body2" style={{marginBottom: "10px", textAlign: "left"}}>
                    <strong>From:</strong> {currentRequest.pickupAddress}
                  </Typography>
                )}
                {currentRequest?.dropoffAddress && (
                  <Typography variant="body2" style={{marginBottom: "15px", textAlign: "left"}}>
                    <strong>To:</strong> {currentRequest.dropoffAddress}
                  </Typography>
                )}
                <Box style={{display: "flex", gap: "10px", justifyContent: "center", flexWrap: "wrap"}}>
                  <Button 
                    onClick={() => reply("accept")} 
                    variant="contained" 
                    color="success"
                    disabled={processingId !== null}
                  >
                    ✓ Accept
                  </Button>
                  <Button 
                    onClick={() => reply("reject")} 
                    variant="contained" 
                    color="error"
                    disabled={processingId !== null}
                  >
                    ✗ Reject
                  </Button>
                </Box>
              </CardContent>
            </Card>
          </Box>

          {requests.length > 1 && (
            <Box style={{marginTop: "15px", display: "flex", gap: "10px", justifyContent: "center"}}>
              <Button 
                onClick={handlePrevious} 
                disabled={currentIndex === 0}
                size="small"
              >
                ← Previous
              </Button>
              <Typography variant="caption" style={{alignSelf: "center"}}>
                {currentIndex + 1} / {requests.length}
              </Typography>
              <Button 
                onClick={handleNext} 
                disabled={currentIndex === requests.length - 1}
                size="small"
              >
                Next →
              </Button>
            </Box>
          )}
        </div>
      ) : (
        <Box style={{backgroundColor: "lavender", minHeight: "250px", display: "flex", alignItems: "center", justifyContent: "center"}}>
          <Typography variant="body2" color="textSecondary">
            No active requests. Waiting for new bookings...
          </Typography>
        </Box>
      )}
    </div>
  );
}

export default Driver;