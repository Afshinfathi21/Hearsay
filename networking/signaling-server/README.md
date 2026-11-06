# Hearsay Signaling Server

A small WebSocket service for room-code matchmaking and WebRTC signaling.
It does **not** host the game simulation. The room creator remains the
authoritative game host.

## Requirements

- Node.js 20+
- npm

## Run locally

```sh
cd networking/signaling-server
npm install
npm start
```

The HTTP health check is available at `http://localhost:8080/health`.
WebSocket clients connect to `ws://localhost:8080/ws`.

For internet testing, deploy this service to a host that supports persistent
WebSocket connections and configure TLS. The game client should then use
`wss://YOUR-SERVICE-HOST/ws`. Do not ship a public game build using plain
`ws://` over the internet.

## Protocol v1

Every WebSocket message is a JSON object with a `type` field.

### Client messages

- `{"type":"create_room","player_name":"Player"}`
- `{"type":"join_room","room_code":"ABC234","player_name":"Player"}`
- `{"type":"signal","target_peer_id":2,"data":{"kind":"offer","sdp":"..."}}`
- `{"type":"signal","target_peer_id":1,"data":{"kind":"answer","sdp":"..."}}`
- `{"type":"signal","target_peer_id":1,"data":{"kind":"candidate","candidate":{}}}`
- `{"type":"set_ready","ready":true}`
- `{"type":"start_match"}` (host only; all players must be ready)
- `{"type":"leave_room"}`

The signaling payload is forwarded unchanged to the target peer. The game client
is responsible for creating WebRTC peer connections and exchanging offers,
answers, and ICE candidates.

### Server messages

- `connected`
- `room_created`: includes the room code and host peer ID.
- `room_joined`: includes the joining peer ID and the existing players.
- `peer_joined`
- `peer_left`
- `player_updated`
- `signal`: includes `from_peer_id` and the forwarded payload.
- `start_match`
- `left_room`
- `room_closed`
- `error`: includes a machine-readable code and message.

Room codes are six characters and ignore easily confused characters. Rooms
are private and in-memory: restarting the service closes every room. A room
supports up to four players. If the host disconnects, the room is closed.

## Important limitations

This is the first networking milestone, not the complete multiplayer client.
It provides room discovery and a signaling relay only. It does not provide
NAT traversal or TURN relay service. Direct WebRTC connections may fail for
players behind restrictive NATs; a TURN service will be needed for reliable
internet play.

There is currently no authentication, persistent room storage, public room
browser, invitation integration, or abuse-prevention beyond message-size and
room-capacity limits. Use it for controlled testing, not as a production
service.
