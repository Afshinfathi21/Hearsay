# Steam networking foundation

Hearsay is moving to Steamworks for online multiplayer. The intended architecture is:

- Steam lobbies for creating, discovering, joining, and inviting players.
- Steam Networking Sockets through a Godot `MultiplayerPeer` implementation for game traffic.
- Godot's high-level multiplayer API for gameplay replication and RPCs.
- One player remains the host/authority; the other players connect as clients.
- Maximum lobby size: four players.

## Current status

This is an initial scaffold, not a working multiplayer implementation yet.

- The previous Node.js signaling server has been removed.
- `SteamManager` is registered as an autoload.
- The manager detects the Steam singleton and the `SteamMultiplayerPeer` class.
- It exposes an explicit Steam initialization method using Valve's public test App ID 480.
- No lobby creation, joining, invitations, peer creation, or gameplay synchronization has been implemented yet.

## Required native dependency

Install a GodotSteam GDExtension build that matches this project's Godot version and exposes **both**:

- the `Steam` singleton
- the `SteamMultiplayerPeer` class

The regular GodotSteam GDExtension and the MultiplayerPeer-enabled build are not interchangeable. Do not assume that installing the regular Steamworks API extension provides the multiplayer peer.

Before choosing a binary, verify that its release explicitly supports Godot 4.7 and includes the MultiplayerPeer component. Keep the native plugin binaries out of this repository unless we deliberately decide to vendor them.

Official GodotSteam project and documentation:
- https://godotsteam.com/
- https://codeberg.org/godotsteam/godotsteam

## Local testing

1. Install and run the Steam desktop client.
2. Install the matching GodotSteam MultiplayerPeer GDExtension in the project.
3. Open Hearsay in Godot and check the Output panel for the Steam extension detection warning.
4. Call `SteamManager.initialize()` from a temporary test button or test script.
5. Confirm that initialization succeeds and `SteamManager.is_ready_for_multiplayer()` returns true.

App ID 480 is Valve's shared Spacewar test application. It is suitable for initial integration experiments, not a final Hearsay release identity. Do not commit local Steam credentials, SDK files, or a local `steam_appid.txt`.

## Planned implementation order

1. Verify the native extension loads on the project's Godot version.
2. Initialize Steam and handle initialization failure cleanly.
3. Create a friends-only lobby with a four-player limit.
4. Join a lobby by Steam invite or lobby ID.
5. Create the host/client `SteamMultiplayerPeer` and assign it to the scene's `MultiplayerAPI`.
6. Replicate lobby player data and ready state.
7. Only then connect the match start flow and synchronize gameplay.
