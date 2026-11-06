const http = require("node:http");
const { randomInt } = require("node:crypto");
const { WebSocketServer, WebSocket } = require("ws");

const PORT = Number(process.env.PORT || 8080);
const MAX_PLAYERS = 4;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 6;
const MAX_MESSAGE_BYTES = 16 * 1024;
const HEARTBEAT_INTERVAL_MS = 30_000;

const rooms = new Map();
const clients = new Map();
let nextPeerId = 1;

function makeRoomCode() {
  let code;
  do {
    code = Array.from({ length: CODE_LENGTH }, () =>
      CODE_ALPHABET[randomInt(CODE_ALPHABET.length)]
    ).join("");
  } while (rooms.has(code));
  return code;
}

function send(socket, message) {
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}

function sendError(socket, code, message) {
  send(socket, { type: "error", code, message });
}

function cleanPlayerName(value) {
  if (typeof value !== "string") return "Player";
  const name = value.trim().replace(/[\u0000-\u001f\u007f]/g, "").slice(0, 16);
  return name || "Player";
}

function getPublicPlayers(room) {
  return [...room.players.values()].map(({ peerId, name, ready, isHost }) => ({
    peer_id: peerId,
    name,
    ready,
    is_host: isHost
  }));
}

function detachClient(socket, reason = "left") {
  const client = clients.get(socket);
  if (!client) return;

  clients.delete(socket);
  const room = rooms.get(client.roomCode);
  if (!room) return;

  room.players.delete(client.peerId);

  if (client.isHost) {
    for (const player of room.players.values()) {
      send(player.socket, {
        type: "room_closed",
        reason: "host_disconnected"
      });
      clients.delete(player.socket);
      player.socket.close(1000, "Host disconnected");
    }
    rooms.delete(room.code);
    return;
  }

  for (const player of room.players.values()) {
    send(player.socket, {
      type: "peer_left",
      peer_id: client.peerId,
      reason
    });
  }

  if (room.players.size === 0) rooms.delete(room.code);
}

function handleCreateRoom(socket, message) {
  if (clients.has(socket)) {
    sendError(socket, "ALREADY_IN_ROOM", "You are already in a room.");
    return;
  }

  const code = makeRoomCode();
  const peerId = nextPeerId++;
  const player = {
    socket,
    peerId,
    name: cleanPlayerName(message.player_name),
    ready: false,
    isHost: true
  };

  const room = {
    code,
    hostPeerId: peerId,
    maxPlayers: MAX_PLAYERS,
    players: new Map([[peerId, player]])
  };

  rooms.set(code, room);
  clients.set(socket, { roomCode: code, peerId, isHost: true });

  send(socket, {
    type: "room_created",
    room_code: code,
    peer_id: peerId,
    max_players: room.maxPlayers,
    players: getPublicPlayers(room)
  });
}

function handleJoinRoom(socket, message) {
  if (clients.has(socket)) {
    sendError(socket, "ALREADY_IN_ROOM", "You are already in a room.");
    return;
  }

  const code = typeof message.room_code === "string"
    ? message.room_code.trim().toUpperCase()
    : "";

  if (!/^[A-HJ-NP-Z2-9]{6}$/.test(code)) {
    sendError(socket, "INVALID_CODE", "Enter a valid 6-character room code.");
    return;
  }

  const room = rooms.get(code);
  if (!room) {
    sendError(socket, "ROOM_NOT_FOUND", "That room does not exist.");
    return;
  }

  if (room.players.size >= room.maxPlayers) {
    sendError(socket, "ROOM_FULL", "That room is full.");
    return;
  }

  const peerId = nextPeerId++;
  const player = {
    socket,
    peerId,
    name: cleanPlayerName(message.player_name),
    ready: false,
    isHost: false
  };

  const existingPlayers = getPublicPlayers(room);
  room.players.set(peerId, player);
  clients.set(socket, { roomCode: code, peerId, isHost: false });

  send(socket, {
    type: "room_joined",
    room_code: code,
    peer_id: peerId,
    host_peer_id: room.hostPeerId,
    max_players: room.maxPlayers,
    players: existingPlayers
  });

  for (const other of room.players.values()) {
    if (other.peerId === peerId) continue;
    send(other.socket, {
      type: "peer_joined",
      player: {
        peer_id: player.peerId,
        name: player.name,
        ready: player.ready,
        is_host: false
      }
    });
  }
}

function handleSignal(socket, message) {
  const client = clients.get(socket);
  if (!client) {
    sendError(socket, "NOT_IN_ROOM", "Join a room before sending signals.");
    return;
  }

  const room = rooms.get(client.roomCode);
  const targetPeerId = Number(message.target_peer_id);
  const target = room?.players.get(targetPeerId);

  if (!target || !message.data || typeof message.data !== "object") {
    sendError(socket, "INVALID_SIGNAL", "The signaling target or payload is invalid.");
    return;
  }

  send(target.socket, {
    type: "signal",
    from_peer_id: client.peerId,
    data: message.data
  });
}

function handleReady(socket, message) {
  const client = clients.get(socket);
  if (!client) {
    sendError(socket, "NOT_IN_ROOM", "Join a room first.");
    return;
  }

  const room = rooms.get(client.roomCode);
  const player = room?.players.get(client.peerId);
  if (!player) return;

  player.ready = message.ready === true;

  for (const member of room.players.values()) {
    send(member.socket, {
      type: "player_updated",
      player: {
        peer_id: player.peerId,
        name: player.name,
        ready: player.ready,
        is_host: player.isHost
      }
    });
  }
}

function handleStartMatch(socket) {
  const client = clients.get(socket);
  if (!client?.isHost) {
    sendError(socket, "HOST_ONLY", "Only the host can start the match.");
    return;
  }

  const room = rooms.get(client.roomCode);
  if (!room || room.players.size < 2) {
    sendError(socket, "NOT_ENOUGH_PLAYERS", "At least two players are required.");
    return;
  }

  const allReady = [...room.players.values()].every(player => player.ready);
  if (!allReady) {
    sendError(socket, "PLAYERS_NOT_READY", "All players must be ready.");
    return;
  }

  for (const player of room.players.values()) {
    send(player.socket, { type: "start_match" });
  }
}

function handleMessage(socket, raw) {
  let message;
  try {
    message = JSON.parse(raw.toString());
  } catch {
    sendError(socket, "BAD_JSON", "Message must be valid JSON.");
    return;
  }

  if (!message || typeof message !== "object" || typeof message.type !== "string") {
    sendError(socket, "BAD_MESSAGE", "Message type is required.");
    return;
  }

  switch (message.type) {
    case "create_room":
      handleCreateRoom(socket, message);
      break;
    case "join_room":
      handleJoinRoom(socket, message);
      break;
    case "signal":
      handleSignal(socket, message);
      break;
    case "set_ready":
      handleReady(socket, message);
      break;
    case "start_match":
      handleStartMatch(socket);
      break;
    case "leave_room":
      detachClient(socket);
      send(socket, { type: "left_room" });
      break;
    default:
      sendError(socket, "UNKNOWN_MESSAGE", "Unknown message type.");
  }
}

const server = http.createServer((request, response) => {
  if (request.url === "/health") {
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify({
      status: "ok",
      active_rooms: rooms.size,
      connected_clients: clients.size
    }));
    return;
  }

  response.writeHead(404, { "content-type": "application/json" });
  response.end(JSON.stringify({ error: "not_found" }));
});

const wss = new WebSocketServer({
  noServer: true,
  maxPayload: MAX_MESSAGE_BYTES
});

server.on("upgrade", (request, socket, head) => {
  if (request.url !== "/ws") {
    socket.write("HTTP/1.1 404 Not Found\r\n\r\n");
    socket.destroy();
    return;
  }

  wss.handleUpgrade(request, socket, head, websocket => {
    wss.emit("connection", websocket, request);
  });
});

wss.on("connection", socket => {
  socket.isAlive = true;
  socket.on("pong", () => { socket.isAlive = true; });
  socket.on("message", raw => handleMessage(socket, raw));
  socket.on("close", () => detachClient(socket));
  socket.on("error", () => detachClient(socket, "connection_error"));
  send(socket, { type: "connected", protocol_version: 1 });
});

const heartbeat = setInterval(() => {
  for (const socket of wss.clients) {
    if (!socket.isAlive) {
      socket.terminate();
      continue;
    }
    socket.isAlive = false;
    socket.ping();
  }
}, HEARTBEAT_INTERVAL_MS);

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Hearsay signaling server listening on port ${PORT}`);
});

function shutdown() {
  clearInterval(heartbeat);
  for (const socket of wss.clients) socket.close(1001, "Server shutting down");
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5_000).unref();
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
