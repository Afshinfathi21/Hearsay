extends SceneTree
## "Don't Blink" mini-game tests.
##   Stage A: the rules (DontBlinkGame) by stepping the clock, no scene.
##   Stage B: the real level: a player walks onto the pads, moves while the eye watches, leaves, loses, wins.
##
##   godot --headless --path . --script res://tests/dont_blink_test.gd
##
## Exit code 0 = everything passed, 1 = at least one check failed.

const LEVEL := "res://Levels/The Exit Room/BaseLevel.tscn"
const DT := 1.0 / 60.0

var passed := 0
var failed := 0


func _init() -> void:
	_run()


func _run() -> void:
	t_countdown_and_joining()
	t_rules()
	t_everyone_pays()
	t_sabotage()
	t_finish_leave_reset()
	t_time_limit()
	t_difficulty()
	t_random_phases()
	await t_level()
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


# ---- stage A: the rules -------------------------------------------------------------------------
func t_countdown_and_joining() -> void:
	_title("countdown and joining")
	var g := _game()
	check(g.state == DontBlinkGame.State.IDLE and g.join(1) and g.state == DontBlinkGame.State.COUNTDOWN, "the first player to join starts the countdown")
	check(g.join(2), "others can join during the countdown")
	_sim(g, 2.9)
	check(g.state == DontBlinkGame.State.COUNTDOWN, "still counting down after 2.9 s")
	_sim(g, 0.2)
	check(g.state == DontBlinkGame.State.RUNNING and not g.watching and g.danger == 0, "the game starts dark with no danger")
	check(not g.join(3), "nobody can join once it is running")


func t_rules() -> void:
	_title("the eye: freeze while watched, move while dark")
	var g := _fixed_game([1])
	_to_phase(g, true)
	_sim(g, 0.4, {1: 3.0})
	_sim(g, 1.2)
	check(g.danger == 0, "moving during the first 0.5 s after the light comes on is allowed (reaction time)")

	g = _fixed_game([1])
	var seen := []
	g.player_detected.connect(func(id: int) -> void: seen.append(id))
	_to_phase(g, true)
	_sim(g, 1.5, {1: 3.0})
	check(g.danger == 1 and seen == [1], "moving while watched is detected: danger +1")
	check(g.status_of(1) == "playing", "one mistake does not end the game")

	g = _fixed_game([1])
	_to_phase(g, true)
	_sim(g, 1.8, {1: 3.0})
	check(g.danger == 1, "moving the whole time counts once per watching phase, not every frame")
	_to_phase(g, false)
	_to_phase(g, true)
	_sim(g, 1.0, {1: 3.0})
	check(g.danger == 2, "the next watching phase can add danger again")

	g = _fixed_game([1])
	_sim(g, 20.0)
	check(g.danger == 0, "standing still never costs danger")

	g = _fixed_game([1])
	_to_phase(g, true)
	_sim(g, 1.5, {1: 0.1})
	check(g.danger == 0, "a tiny drift (0.1 m/s) is not movement")
	g = _fixed_game([1])
	_to_phase(g, true)
	_sim(g, 1.5, {1: 0.2})
	check(g.danger == 1, "0.2 m/s is movement")

	g = _fixed_game([1])
	_to_phase(g, false)
	_sim(g, 1.5, {1: 5.0})
	check(g.danger == 0, "moving while the eye is shut is free")


func t_everyone_pays() -> void:
	_title("one mistake raises the danger for everyone")
	var g := _fixed_game([1, 2])
	var seen := []
	g.player_detected.connect(func(id: int) -> void: seen.append(id))
	_to_phase(g, true)
	_sim(g, 1.0, {1: 0.0, 2: 3.0})
	check(g.danger == 1 and seen == [2], "player 2 moved: the room detects player 2 only")
	check(g.status_of(1) == "playing" and g.status_of(2) == "playing", "both are still in the game, sharing the one danger level")


func t_sabotage() -> void:
	_title("a player can make everyone lose")
	var g := _fixed_game([1, 2, 3])
	g.max_danger = 3
	var won := []
	var lost := []
	var ended := [0]
	g.player_won.connect(func(id: int) -> void: won.append(id))
	g.player_lost.connect(func(id: int) -> void: lost.append(id))
	g.ended.connect(func() -> void: ended[0] += 1)
	check(g.finish(3), "player 3 reaches the exit early and wins")
	for i in 3:
		_to_phase(g, false)
		_to_phase(g, true)                                   # a NEW watching phase each time
		_sim(g, 1.0, {2: 3.0})                               # player 2 keeps moving on purpose
	check(g.state == DontBlinkGame.State.ENDED and ended[0] == 1, "at maximum danger the game ends")
	lost.sort()
	check(lost == [1, 2] and won == [3], "everyone still playing loses (even the one who stood still); the winner keeps the win")
	check(g.status_of(3) == "won", "player 3 stays a winner")


func t_finish_leave_reset() -> void:
	_title("finishing, leaving, resetting")
	var g := _game()
	g.join(1)
	g.join(2)
	check(not g.finish(1), "the exit does not count before the game is running")
	_sim_until(g, func() -> bool: return g.state == DontBlinkGame.State.RUNNING)
	var lost := []
	g.player_lost.connect(func(id: int) -> void: lost.append(id))
	check(g.finish(1) and g.state == DontBlinkGame.State.RUNNING, "player 1 wins; the game goes on for player 2")
	check(not g.finish(1), "a win counts once")
	check(g.finish(2) and g.state == DontBlinkGame.State.ENDED and lost.is_empty(), "when everyone finished the game ends with no loser")
	check(not g.join(3), "no joining after the end")
	g.reset()
	check(g.state == DontBlinkGame.State.IDLE and g.join(3), "after a reset the room can be played again")

	g = _game()
	g.join(1)
	g.join(2)
	g.leave(1)
	g.leave(2)
	check(g.state == DontBlinkGame.State.IDLE, "everybody walked away during the countdown: back to idle")

	g = _game()
	g.join(1)
	g.join(2)
	_sim_until(g, func() -> bool: return g.state == DontBlinkGame.State.RUNNING)
	g.leave(1)
	check(g.status_of(1) == "left" and g.state == DontBlinkGame.State.RUNNING, "leaving costs nothing and the others carry on")
	g.finish(2)
	check(g.state == DontBlinkGame.State.ENDED and g.status_of(1) == "left", "the one who left is not counted as a loser")

	g = _game()
	g.join(1)
	_sim_until(g, func() -> bool: return g.state == DontBlinkGame.State.RUNNING)
	g.leave(1)
	check(g.state == DontBlinkGame.State.IDLE, "the last player walking out resets the room (no result)")


func t_time_limit() -> void:
	_title("optional time limit")
	var g := _fixed_game([1])
	check(g.time_left() == -1.0, "no time limit by default")
	g.time_limit = 5.0
	_sim(g, 5.5)
	check(g.state == DontBlinkGame.State.ENDED and g.status_of(1) == "lost", "when the time is up everyone still playing loses")


func t_difficulty() -> void:
	_title("danger makes the eye more watchful")
	var g := _game()
	var w0 := g.current_watch_range()
	var d0 := g.current_dark_range()
	g.danger = 4
	check(g.current_watch_range().y > w0.y and g.current_watch_range().x > w0.x, "at danger 4 the eye watches longer")
	check(g.current_dark_range().y < d0.y and g.current_dark_range().x < d0.x, "at danger 4 the dark phases are shorter")
	g.danger = 50
	check(g.current_dark_range().y >= d0.y * 0.4 - 0.001, "the dark phases never shrink below 40% of normal")


func t_random_phases() -> void:
	_title("the light flashes at random")
	var g := _game()
	g.countdown_time = 0.0
	g.join(1)
	var watch := []
	var dark := []
	var t := [0.0]
	var last := [0.0]
	g.tick(DT)                                               # countdown 0 -> running (the first dark phase starts)
	g.watching_changed.connect(func(w: bool) -> void:
		var length: float = t[0] - last[0]
		last[0] = t[0]
		(dark if w else watch).append(length))                # a change TO watching ends a dark phase
	for i in 20000:
		t[0] += DT
		g.tick(DT)
		if dark.size() >= 15 and watch.size() >= 15:
			break
	var ok_dark := true
	var ok_watch := true
	for d in dark:
		ok_dark = ok_dark and d >= 2.0 - 0.05 and d <= 4.5 + 0.05
	for w in watch:
		ok_watch = ok_watch and w >= 1.5 - 0.05 and w <= 3.0 + 0.05
	check(dark.size() >= 15 and watch.size() >= 15, "many phases were produced (%d dark, %d watching)" % [dark.size(), watch.size()])
	check(ok_dark and ok_watch, "every dark phase lasts 2.0-4.5 s and every watching phase 1.5-3.0 s")
	check(dark.max() - dark.min() > 0.5 and watch.max() - watch.min() > 0.3, "the lengths differ from phase to phase (random)")

	var a := _timeline(7)
	var b := _timeline(7)
	var c := _timeline(8)
	check(a == b, "the same seed gives the same light pattern")
	check(a != c, "a different seed gives a different light pattern")


# ---- stage B: the real level -----------------------------------------------------------------------
func t_level() -> void:
	_title("level: pads, eye, lights, HUD, reward")
	var level: Node = (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for i in 20:
		await physics_frame
	var gen: Node3D
	for n in level.find_children("*", "Node3D", true, false):
		if "door_records" in n:
			gen = n
	var player := get_first_node_in_group("player") as Node3D
	var solo := level.get_node("SoloMatch")
	var hud: GameHUD = solo.hud
	player.set_process(false)
	player.set_physics_process(false)
	for rd in gen.room_list:
		solo._penalised[rd.label] = true
	var rooms_with_game := 0
	var rd = null
	for r in gen.room_list:
		if r.minigame:
			rooms_with_game += 1
			if rd == null:
				rd = r
	check(rd != null and solo._minigames.size() == rooms_with_game, "every mini-game room has a Don't Blink game (%d)" % rooms_with_game)
	var gr: DontBlinkRoom = solo._minigames[rd.label]
	var floor_c: Vector3 = gen.get_room_floor_center(rd)
	var start_p: Vector3 = gr._start_pad["root"].global_position
	var exit_p: Vector3 = gr._finish_pad["root"].global_position
	var half: float = gen.room_cells * 4.0 * 0.5
	check(absf(start_p.x - floor_c.x) < half - 1.0 and absf(start_p.z - floor_c.z) < half - 1.0 and absf(exit_p.x - floor_c.x) < half - 1.0
		and absf(exit_p.z - floor_c.z) < half - 1.0 and start_p.distance_to(exit_p) > 6.0, "both pads are inside the room, far apart")
	check(gr._eye_root.global_position.y - DontBlinkRoom.EYE_RADIUS - floor_c.y >= 2.2, "the eye hangs above head height (nobody bumps into it)")
	check(gr._room_lights.size() > 0, "the room's lights are found, so they can flash with the eye")

	gr.game.countdown_time = 0.3
	gr.game.watch_time = Vector2(1.0, 1.0)
	gr.game.dark_time = Vector2(0.5, 0.5)
	gr.game.reaction_grace = 0.2
	solo._on_room_entered(rd, player)

	# 1) walking away during the countdown just cancels it
	await _put(player, start_p)
	await _frames(3)
	check(gr.game.state == DontBlinkGame.State.COUNTDOWN and hud.mini_game_panel.visible, "stepping on the START pad begins the countdown and shows the panel")
	await _put(player, floor_c + Vector3(25.0, 0.1, 0.0))
	await _frames(3)
	check(gr.game.state == DontBlinkGame.State.IDLE and not hud.mini_game_panel.visible, "walking out of the room cancels it, no penalty, panel hidden")

	# 2) moving while watched: danger, then everyone loses
	gr.game.max_danger = 2
	var points_before: int = solo._points
	var items_before: int = solo._rewards.inventory_of(1).count()
	await _put(player, start_p)
	var open_seen := false
	var dark_seen := false
	var base_energy: float = float(gr._room_lights[0]["base"])
	var wiggle := 0.05
	for i in 900:
		await physics_frame
		if gr.game.state == DontBlinkGame.State.RUNNING:
			player.global_position += Vector3(wiggle, 0.0, 0.0)
			wiggle = -wiggle
			if gr._open > 0.95 and gr._lid_pivot.rotation.x < 0.3 and float((gr._room_lights[0]["light"] as OmniLight3D).light_energy) > base_energy * 1.5:
				open_seen = true
			if gr._open < 0.05 and gr._lid_pivot.rotation.x > PI - 0.3 and float((gr._room_lights[0]["light"] as OmniLight3D).light_energy) < base_energy * 0.5:
				dark_seen = true
		if gr.game.state == DontBlinkGame.State.ENDED:
			break
	check(open_seen, "while the eye watches: the lid is open and the room lights flash bright")
	check(dark_seen, "while the eye is shut: the lid is closed and the room is dark")
	check(gr.game.state == DontBlinkGame.State.ENDED and gr.game.status_of(1) == "lost", "moving while watched raised the danger to the maximum: the player lost")
	check(str(hud.mini_game_panel._status.text).contains("FOUND"), "the HUD says the eye found you")
	check(solo._points == points_before and solo._rewards.inventory_of(1).count() == items_before, "losing costs no points and gives no reward")
	await _frames(240)                                       # RESULT_SECONDS later the room can be played again
	check(gr.game.state == DontBlinkGame.State.IDLE and not hud.mini_game_panel.visible, "after the result the room resets and the panel hides")

	# 3) standing still while watched, then reaching the exit pad: the reward
	gr.game.max_danger = 5
	await _put(player, floor_c + Vector3(25.0, 0.1, 0.0))    # step off the pad first: stepping ON it starts a try
	await _frames(3)
	await _put(player, start_p)
	await _wait_for(func() -> bool: return gr.game.state == DontBlinkGame.State.RUNNING, 300)
	await _frames(40)                                        # stand still through a light flash
	check(gr.game.danger == 0 and gr.game.state == DontBlinkGame.State.RUNNING, "standing still through the flashes costs nothing")
	await _put(player, exit_p)
	await _frames(5)
	var inv: PlayerInventory = solo._rewards.inventory_of(1)
	check(inv.count() == items_before + 1 and inv.snapshot()[inv.count() - 1]["kind"] == RewardCatalog.TRAP_SCAN, "reaching the EXIT pad gives a TRAP SCAN: a hint about one nearby room")
	check(gr.claimed and hud.inventory_bar.filled_count() == inv.count(), "the reward shows in the inventory bar and the eye goes to sleep")
	await _put(player, start_p)
	await _frames(5)
	check(gr.game.state == DontBlinkGame.State.IDLE, "a claimed room cannot be started again")
	var uid := inv.slot_uid(inv.count() - 1)
	var result: Dictionary = solo._rewards.use_item(1, uid, {"generator": gen, "room": rd.coord})
	check(result["ok"] and str(result["text"]).begins_with("ROOM "), "the TRAP SCAN works: %s" % result["text"])


# ---- helpers -----------------------------------------------------------------------------------------
func _game(seed_value := 1) -> DontBlinkGame:
	var g := DontBlinkGame.new()
	g.rng.seed = seed_value
	return g


## Fixed 2 s dark / 2 s watching phases that never change with danger, so timings are exact.
func _fixed_game(ids: Array) -> DontBlinkGame:
	var g := _game()
	g.watch_time = Vector2(2.0, 2.0)
	g.dark_time = Vector2(2.0, 2.0)
	g.watch_growth = 0.0
	g.dark_shrink = 0.0
	for id in ids:
		g.join(id)
	_sim_until(g, func() -> bool: return g.state == DontBlinkGame.State.RUNNING)
	return g


func _sim(g: DontBlinkGame, seconds: float, speeds := {}) -> void:
	for i in int(round(seconds / DT)):
		g.tick(DT, speeds)


func _sim_until(g: DontBlinkGame, cond: Callable) -> void:
	for i in 100000:
		if cond.call():
			return
		g.tick(DT, {})


func _to_phase(g: DontBlinkGame, watching: bool) -> void:
	_sim_until(g, func() -> bool: return g.state != DontBlinkGame.State.RUNNING or g.watching == watching)


func _timeline(seed_value: int) -> Array:
	var g := _game(seed_value)
	g.countdown_time = 0.0
	g.join(1)
	var times := []
	var t := [0.0]
	g.watching_changed.connect(func(_w: bool) -> void: times.append(snappedf(t[0], 0.001)))
	for i in 3000:
		t[0] += DT
		g.tick(DT)
	return times


func _put(player: Node3D, at: Vector3) -> void:
	player.global_position = at + Vector3(0.0, 0.05, 0.0)
	await physics_frame


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _wait_for(cond: Callable, max_frames: int) -> void:
	for i in max_frames:
		if cond.call():
			return
		await physics_frame


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)


func _title(text: String) -> void:
	print("\n== ", text)
