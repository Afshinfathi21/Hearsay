class_name DontBlinkGame
extends RefCounted
## The rules of the "Don't Blink" mini-game. Plain logic: no nodes, no UI, no physics. The room (presentation)
## feeds it the players' speeds every frame and shows what it decides, so the host can own an instance later.
##
## A giant eye watches the room. The light flashes at random:
##   light ON  (the eye WATCHES)  everyone must stand completely still
##   light OFF (the eye is shut)  everyone may move toward the exit
## A player who moves while watched is detected: the danger level goes up for EVERYONE. At maximum danger every
## player who has not reached the exit loses. A player who reaches the exit wins at that moment and is safe,
## whatever the others do afterwards. Players may walk out of the room at any time (they just stop taking part).
##
## Flow: join() -> countdown -> running (starts dark) -> ended. Call tick() every frame while it is not IDLE.

signal watching_changed(watching: bool)
signal player_detected(player_id: int)
signal danger_changed(level: int)
signal player_won(player_id: int)
signal player_lost(player_id: int)
signal ended

enum State { IDLE, COUNTDOWN, RUNNING, ENDED }

## Danger level at which everybody still playing loses.
var max_danger := 5
## Speed (metres per second) above which a player counts as moving. Turning the camera is not moving.
var still_speed := 0.15
## Seconds after the light comes on before moving is punished, so players have time to stop.
var reaction_grace := 0.5
## Seconds between the first player joining and the first (dark) phase. Others may join meanwhile.
var countdown_time := 3.0
## Seconds before everybody still playing loses. 0 = no time limit.
var time_limit := 0.0
## (min, max) seconds the eye watches / the room is dark. Each phase picks a random value in range.
var watch_time := Vector2(1.5, 3.0)
var dark_time := Vector2(2.0, 4.5)
## Every danger level makes the eye watch this much longer and the dark phases this much shorter.
var watch_growth := 0.12
var dark_shrink := 0.10
var rng := RandomNumberGenerator.new()

var state := State.IDLE
var watching := false
var danger := 0
var elapsed := 0.0

var _players := {}                       # player id -> "playing" | "won" | "lost" | "left"
var _countdown := 0.0
var _phase_left := 0.0
var _watch_elapsed := 0.0
var _caught := {}                        # players already detected in the current watching phase


## A player steps up to take part. Only possible before the first dark phase starts.
func join(player_id: int) -> bool:
	if state != State.IDLE and state != State.COUNTDOWN:
		return false
	if status_of(player_id) == "playing":
		return true
	_players[player_id] = "playing"
	if state == State.IDLE:
		state = State.COUNTDOWN
		_countdown = countdown_time
	return true


## The player stopped taking part (walked out of the room). No result, no penalty.
func leave(player_id: int) -> void:
	if status_of(player_id) != "playing":
		return
	_players[player_id] = "left"
	_check_end()


## The player reached the exit. Returns true when that counted as a win.
func finish(player_id: int) -> bool:
	if state != State.RUNNING or status_of(player_id) != "playing":
		return false
	_players[player_id] = "won"
	player_won.emit(player_id)
	_check_end()
	return true


## Advance by `delta` seconds. speeds: {player id: speed in m/s} for the players taking part.
func tick(delta: float, speeds := {}) -> void:
	if state == State.COUNTDOWN:
		_countdown -= delta
		if _countdown <= 0.0:
			state = State.RUNNING
			elapsed = 0.0
			danger = 0
			_set_watching(false)             # the first phase is dark
		return
	if state != State.RUNNING:
		return
	elapsed += delta
	if time_limit > 0.0 and elapsed >= time_limit:
		_lose_all()
		return
	if watching:
		_watch_elapsed += delta
		if _watch_elapsed >= reaction_grace:
			for id in playing_ids():
				if _caught.has(id) or float(speeds.get(id, 0.0)) <= still_speed:
					continue
				_caught[id] = true
				danger += 1
				player_detected.emit(id)
				danger_changed.emit(danger)
				if danger >= max_danger:
					_lose_all()
					return
	_phase_left -= delta
	if _phase_left <= 0.0:
		_set_watching(not watching)


func status_of(player_id: int) -> String:
	return _players.get(player_id, "")


func playing_ids() -> Array[int]:
	var out: Array[int] = []
	for id in _players:
		if _players[id] == "playing":
			out.append(id)
	return out


## Back to the start, ready for a new attempt.
func reset() -> void:
	state = State.IDLE
	watching = false
	danger = 0
	elapsed = 0.0
	_players.clear()
	_caught.clear()
	_countdown = 0.0
	_phase_left = 0.0
	_watch_elapsed = 0.0


## Seconds left in the countdown (0 once running).
func countdown_left() -> float:
	return maxf(_countdown, 0.0) if state == State.COUNTDOWN else 0.0


## Seconds left before the time limit, or -1 when there is none.
func time_left() -> float:
	return maxf(time_limit - elapsed, 0.0) if time_limit > 0.0 and state == State.RUNNING else -1.0


## The (min, max) the next watching / dark phase is drawn from at the current danger level.
func current_watch_range() -> Vector2:
	return watch_time * (1.0 + watch_growth * danger)


func current_dark_range() -> Vector2:
	return dark_time * maxf(1.0 - dark_shrink * danger, 0.4)


func _set_watching(value: bool) -> void:
	watching = value
	_caught.clear()
	_watch_elapsed = 0.0
	var r := current_watch_range() if value else current_dark_range()
	_phase_left = rng.randf_range(r.x, r.y)
	watching_changed.emit(value)


func _lose_all() -> void:
	for id in playing_ids():
		_players[id] = "lost"
		player_lost.emit(id)
	state = State.ENDED
	watching = false
	ended.emit()


## Nobody is still playing: the game is over (or, when everybody just walked away, simply reset).
func _check_end() -> void:
	if state != State.COUNTDOWN and state != State.RUNNING:
		return
	if not playing_ids().is_empty():
		return
	for id in _players:
		if _players[id] == "won" or _players[id] == "lost":
			state = State.ENDED
			watching = false
			ended.emit()
			return
	reset()
