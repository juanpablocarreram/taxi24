// 1. Asegúrate de que "phoenix" esté en minúsculas y bien escrito
import { Socket } from "phoenix";

// 2. Creamos la instancia apuntando al backend de Elixir
const socket = new Socket("ws://localhost:4000/socket", {
  params: { userToken: "123" }
});

// 3. Conectamos el cable principal
socket.connect();

// 4. Lo exportamos por defecto para que Driver.jsx y Customer.jsx lo usen
export default socket;