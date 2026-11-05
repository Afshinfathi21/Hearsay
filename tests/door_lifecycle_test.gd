extends SceneTree
## Door lifecycle tests. They run against the real level, the real player, the real SoloMatch
## (the stand-in host) and the real hitscan, headless:
##
##   godot --headless --path . --script res://tests/door_lifecycle_test.gd
##
## Exit code 0 = everything passed, 1 = at least one check failed.

const LEVEL := "res://Levels/The Exit Room/BaseLevel.tscn"
const HALF_HEIGHT := 0.94                 # half of the player's capsule

var level: Node
var gen: Node
var player: CharacterBody3D
var solo: Node
var door: StandardDoor
var passed_checks := 0
var failed_checks := 0
var _dummies: Array[Node3D] = []


func _init() -> void:
	_run()


func _run() -> void:
	level = (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for i in 15:
		await physics_frame
	for n in level.find_children("*", "Node3D", true, false):
		if "door_records" in n:
			gen = n
	player = get_first_node_in_group("player")
	solo = level.get_node("SoloMatch")
	# These tests are about doors only: mark every room's effect as already triggered, so teleporting the
	# player around never charges a room penalty.
	for rd in gen.room_list:
		solo._penalised[rd.label] = true
	player.set_process(false)
	player.set_physics_process(false)
	for rec in gen.door_records:
		if rec.door != null and not rec.is_exit:
			door = rec.door
			break
	if door != null:
		door.set_generation_lock(false)
		door.set_round_state(2)

	await t_setup()
	await t_full_lifecycle()
	await t_timeout()
	await t_cancel()
	await t_back_out()
	await t_unreserved_blocked()
	await t_per_round_capacity()
	await t_stale_timer()
	await t_reserve_while_closing()
	await t_points_drop_before_crossing()
	await t_exit_door()
	await t_monitor()
	await t_reserve_inside_doorway()
	await t_interact_key_via_hitscan()
	await t_locked_door()
	await t_two_reservations_share_door()
	await t_mid_crossing_is_protected()
	await t_cross_from_other_side()
	await t_closes_immediately()
	await t_two_physical_bodies()
	await t_spam_interact()
	await t_freed_reservation_holder()

	print("\n%d passed, %d failed" % [passed_checks, failed_checks])
	quit(1 if failed_checks > 0 else 0)


# ---- tests -----------------------------------------------------------------------------------
func t_setup() -> void:
	_title("setup")
	check(gen != null and door != null and player != null, "level, door and player found")
	check(door.capacity == 2 and door.cost == 1 and not door.generation_locked, "test door has capacity 2 and is unlocked")
	check(solo._points == 10, "player starts with 10 points")
	check(not door.is_open and door.reserved == 0, "door starts closed with no reservation")


func t_full_lifecycle() -> void:
	_title("full lifecycle: reserve -> open -> cross -> pay -> close")
	await reset_state()
	await place(1.0, 2.5)
	door.interact(player)
	check(door.reserved == 1, "interact reserves a place")
	check(solo._points == 10, "nothing is charged when the place is reserved")
	check(await wait_until(func() -> bool: return door.is_open, 4.0), "door opens after the reservation")
	var reached := await walk(1.0, 2.5)
	check(reached, "reserved player walks through the open door")
	await frames(5)
	check(solo._points == 9, "charged exactly once, after crossing (10 -> %d)" % solo._points)
	check(door.reserved == 0, "reservation is gone after crossing")
	check(await wait_until(func() -> bool: return not door.is_open, 4.0), "door closes by itself after the last crossing")


func t_timeout() -> void:
	_title("reservation timeout")
	await reset_state()
	door.reservation_timeout = 1.0
	await place(1.0, 2.5)
	door.interact(player)
	check(door.reserved == 1, "reserved")
	await wait_seconds(1.6)
	check(door.reserved == 0, "reservation released after the timeout")
	check(solo._points == 10, "an expired reservation costs nothing")
	check(solo._pending_door == null, "host forgets the expired reservation")
	check(await wait_until(func() -> bool: return not door.is_open, 4.0), "door closes after the timeout")


func t_cancel() -> void:
	_title("cancel before crossing")
	await reset_state()
	await place(1.0, 2.5)
	door.interact(player)
	check(door.reserved == 1, "reserved")
	door.interact(player)
	check(door.reserved == 0, "pressing interact again releases the place")
	check(solo._points == 10, "a cancelled reservation costs nothing")


func t_back_out() -> void:
	_title("walking into the doorway and back out")
	await reset_state()
	await place(1.0, 2.5)
	door.interact(player)
	await wait_until(func() -> bool: return door.is_open, 4.0)
	await walk_to_local_z(0.5 * 1.0)         # inside the doorway, still on the entry side
	check(door.reserved == 1, "reservation kept while inside the doorway")
	await walk_to_local_z(2.5 * 1.0)         # back out the way we came
	await frames(5)
	check(door.reserved == 0, "backing out on the same side releases the reservation")
	check(solo._points == 10, "backing out costs nothing")


func t_unreserved_blocked() -> void:
	_title("per-player barrier")
	await reset_state()
	var other := make_dummy()
	check(door.reserve_passage(other), "another player reserves the door (it opens)")
	await wait_until(func() -> bool: return door.is_open, 4.0)
	check(door.is_open, "door is open")
	await place(1.0, 2.5)
	var reached := await walk(1.0, 2.5)
	check(not reached, "a player WITHOUT a reservation cannot walk through the open door")
	check(passed_of(door) == 0 and solo._points == 10, "no crossing counted, nothing charged")
	door.release_passage(other)
	await wait_until(func() -> bool: return not door.is_open, 4.0)


func t_per_round_capacity() -> void:
	_title("per-round capacity")
	await reset_state()
	if not door.has_method("reset_round"):
		check(false, "door has reset_round() (not in the old code)")
		return
	for i in 2:
		await place(1.0, 2.5)
		door.interact(player)
		await wait_until(func() -> bool: return door.is_open, 4.0)
		var reached := await walk(1.0, 2.5)
		check(reached, "crossing %d completes" % (i + 1))
		await wait_until(func() -> bool: return not door.is_open, 4.0)
	check(door.passed == 2 and door.available == 0, "two crossings use up the two places")
	check(solo._points == 8, "two crossings cost 2 points (got %d left)" % solo._points)
	await place(1.0, 2.5)
	door.interact(player)
	check(door.reserved == 0, "a full door cannot be reserved")
	door.reset_round()
	check(door.passed == 0 and door.available == 2, "reset_round() restores the places")
	door.interact(player)
	check(door.reserved == 1, "the door can be reserved again after the reset")
	door.reset_round()
	check(door.reserved == 0, "reset_round() frees unused reservations")


func t_stale_timer() -> void:
	_title("old timer must not release a newer reservation")
	await reset_state()
	door.reservation_timeout = 7.0
	await place(1.0, 2.5)
	var t0 := Time.get_ticks_msec()
	door.interact(player)                     # first reservation: its 7 s timer starts now
	await wait_until(func() -> bool: return door.is_open, 4.0)
	await walk(1.0, 2.5)                      # crosses and pays
	await wait_until(func() -> bool: return not door.is_open, 4.0)
	await place(-1.0, 2.5)                    # far side: reserve the SAME door again, well before 7 s
	door.interact(player)
	check(door.reserved == 1, "second reservation made (%.1f s after the first)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	while (Time.get_ticks_msec() - t0) / 1000.0 < 7.8:   # past the first reservation's 7 s mark
		await physics_frame
	check(door.reserved == 1, "second reservation is still held after the FIRST one's timer would have ended")


func t_reserve_while_closing() -> void:
	_title("reservation made while the door is closing")
	await reset_state()
	var a := make_dummy()
	var b := make_dummy()
	door.reserve_passage(a)
	await wait_until(func() -> bool: return door.is_open, 4.0)
	door.release_passage(a)                   # closing animation starts
	await frames(3)
	door.reserve_passage(b)
	check(await wait_until(func() -> bool: return door.is_open, 4.0), "door ends up open for the new reservation")
	check(door.reserved == 1, "the new reservation is held")
	door.release_passage(b)
	await wait_until(func() -> bool: return not door.is_open, 4.0)


func t_points_drop_before_crossing() -> void:
	_title("points drop between reserving and crossing")
	await reset_state()
	await place(1.0, 2.5)
	door.interact(player)
	await wait_until(func() -> bool: return door.is_open, 4.0)
	solo._points = 0                          # e.g. transferred away while holding the reservation
	var reached := await walk(1.0, 2.5)
	check(not reached, "the crossing is refused and the player stays blocked")
	check(door.reserved == 0 and passed_of(door) == 0, "reservation dropped, nothing counted")
	check(solo._points == 0, "nothing was charged")
	solo._points = 10


func t_exit_door() -> void:
	_title("exit door")
	await reset_state()
	var ex: StandardDoor = gen.exit_door
	check(ex != null and ex.is_exit, "exit door found")
	ex.interact(player)
	check(await wait_until(func() -> bool: return ex.is_open, 4.0), "exit door opens when interacted with")
	ex.interact(player)
	check(await wait_until(func() -> bool: return not ex.is_open, 4.0), "exit door closes again")
	ex.set_locked(true)
	ex.interact(player)
	await wait_seconds(0.5)
	check(not ex.is_open, "a locked exit door stays closed")
	ex.set_locked(false)


func t_monitor() -> void:
	_title("monitor follows every reservation change")
	await reset_state()
	if not door.has_method("reset_round"):
		check(false, "door has per-round places (not in the old code)")
		return
	var m = door.get_meta("monitors")[0]
	var other := make_dummy()
	check(lit_pips(m) == 2 and units_lit(m) == "ABDEG", "start: digits show capacity 2, 2 places lit")
	door.reserve_passage(other)
	check(lit_pips(m) == 1, "a reservation lights one place less")
	check(units_lit(m) == "ABDEG", "the digits keep showing the capacity (2)")
	door.release_passage(other)
	check(lit_pips(m) == 2, "releasing the reservation gives the place back on the monitor")
	await wait_until(func() -> bool: return not door.is_open, 4.0)
	check(await cross_once(), "a crossing completes")
	check(lit_pips(m) == 1, "after a crossing the place stays used (1 of 2 left)")
	check(await cross_once(), "second crossing completes")
	check(lit_pips(m) == 0 and m._lamp_mat.emission == DoorMonitor.RED, "full door: no places lit and the lamp is red")
	door.reset_round()
	check(lit_pips(m) == 2 and m._lamp_mat.emission == DoorMonitor.AMBER, "new round: places and amber lamp are back")


func t_reserve_inside_doorway() -> void:
	_title("reserving while already standing in the doorway")
	await reset_state()
	await place(1.0, 0.6)                     # closer than 1 m: already inside the passage zone
	door.interact(player)
	check(door.reserved == 1, "reservation made from inside the doorway")
	check(await wait_until(func() -> bool: return door.is_open, 4.0), "door opens")
	var reached := await walk(1.0, 2.5)
	await frames(5)
	check(reached and solo._points == 9, "the crossing is still detected and charged once (points %d)" % solo._points)


func t_interact_key_via_hitscan() -> void:
	_title("pressing E through the real hitscan")
	await reset_state()
	await place(1.0, 2.0)
	var hs := get_first_node_in_group("hitscan") as Node3D
	var origin := player.global_position + Vector3(0, 1.5, 0)
	var target := door.global_position + Vector3(0, 1.1, 0)
	hs.global_transform = Transform3D(Basis.looking_at(target - origin, Vector3.UP), origin)
	await frames(2)
	Input.action_press("interact")
	await frames(2)
	Input.action_release("interact")
	await frames(3)
	check(door.reserved == 1, "E on a door reserves a place")


func t_locked_door() -> void:
	_title("locked door (lockdown)")
	await reset_state()
	door.set_locked(true)
	await place(1.0, 2.5)
	door.interact(player)
	check(door.reserved == 0, "a locked door cannot be reserved through interact")
	check(not door.reserve_passage(make_dummy()), "reserve_passage() is refused while locked")
	check(door.reserved == 0 and not door.is_open, "locked door stays closed with no reservation")
	door.set_locked(false)
	door.interact(player)
	check(door.reserved == 1, "the door can be reserved again once unlocked")
	door.release_passage(player)


func t_two_reservations_share_door() -> void:
	_title("two reservations: door stays open until the last one is done")
	await reset_state()
	var other := make_dummy()
	check(door.reserve_passage(other), "first reservation (another player)")
	await place(1.0, 2.5)
	door.interact(player)
	check(door.reserved == 2 and door.available == 0, "both places reserved, none available")
	check(not door.reserve_passage(make_dummy()), "a third reservation is refused (capacity 2)")
	await wait_until(func() -> bool: return door.is_open, 4.0)
	check(await walk(1.0, 2.5), "the player crosses")
	await frames(5)
	check(solo._points == 9, "only the player who crossed is charged (10 -> %d)" % solo._points)
	check(door.reserved == 1 and door.is_open, "door stays open while the other reservation is still held")
	door.release_passage(other)
	check(await wait_until(func() -> bool: return not door.is_open, 4.0), "door closes right after the last reservation ends")


func t_mid_crossing_is_protected() -> void:
	_title("a player who is already crossing may always finish")
	await reset_state()
	await place(1.0, 2.5)
	door.interact(player)
	await wait_until(func() -> bool: return door.is_open, 4.0)
	await walk_to_local_z(-0.3)               # past the middle plane, still inside the doorway
	check(door.reserved == 1, "reservation held while crossing")
	check(not door.release_passage(player), "cancel is refused once the player is past the middle of the doorway")
	door._expires[player.get_instance_id()] = door._clock    # force the timeout to be due now
	await frames(5)
	check(door.reserved == 1, "an expired reservation is not removed while the player is crossing")
	door.reset_round()
	check(door.reserved == 1, "reset_round() does not remove a player who is crossing")
	check(door.is_open or door._target_open, "the door does not close while the player is crossing")
	await walk_to_local_z(-2.5)               # finish the crossing
	await frames(5)
	check(solo._points == 9, "the crossing is charged once, after it finished (10 -> %d)" % solo._points)
	check(door.reserved == 0, "reservation is gone after the crossing")
	check(await wait_until(func() -> bool: return not door.is_open, 4.0), "door closes after the player finished crossing")


func t_cross_from_other_side() -> void:
	_title("crossing in the opposite direction")
	await reset_state()
	await place(-1.0, 2.5)
	door.interact(player)
	await wait_until(func() -> bool: return door.is_open, 4.0)
	var reached := await walk(-1.0, 2.5)
	await frames(5)
	check(reached and solo._points == 9 and passed_of(door) == 1, "a crossing from the back side is detected and charged once")


func t_closes_immediately() -> void:
	_title("the door starts closing the moment the last reserved player is through")
	await reset_state()
	var done := [false]
	door.passage_completed.connect(func(_b: Node3D) -> void: done[0] = true, CONNECT_ONE_SHOT)
	await place(1.0, 2.5)
	door.interact(player)
	await wait_until(func() -> bool: return door.is_open, 4.0)
	var dir := -door.global_transform.basis.z
	for i in 300:
		player.move_and_collide(dir * 3.0 / 60.0)
		await physics_frame
		if done[0]:
			break
	await physics_frame
	check(done[0], "the crossing completed")
	check(not door._target_open and door._anim.is_playing(), "the closing animation is already running one frame later")


func t_two_physical_bodies() -> void:
	_title("two physical bodies at once: the reserved one passes, the other is stopped")
	await reset_state()
	var npc := make_body()
	var holder := make_dummy()                 # keeps the door open for the whole test
	var back := door.global_transform.basis.z
	var y := door.global_position.y + HALF_HEIGHT + 0.05
	npc.global_position = Vector3(door.global_position.x, y, door.global_position.z) + back * 2.0
	await place(1.0, 4.0)                      # the player stands 2 m behind the other body
	var saved := door.passage_validator
	door.passage_validator = func(_b: Node3D, _d: StandardDoor) -> bool: return true
	door.reserve_passage(npc)
	door.reserve_passage(holder)
	await wait_until(func() -> bool: return door.is_open, 4.0)
	for i in 240:                              # both walk at 2 m/s towards and through the door
		npc.move_and_collide(-back * 2.0 / 60.0)
		player.move_and_collide(-back * 2.0 / 60.0)
		await physics_frame
	await frames(5)
	check(passed_of(door) == 1 and door.to_local(npc.global_position).z < -1.0, "the reserved body crossed")
	check(door.is_open, "the door is still open (another reservation is held)")
	check(door.to_local(player.global_position).z > 0.0, "the unreserved player was stopped at the OPEN door")
	check(solo._points == 10, "the unreserved player was not charged")
	for i in 120:                              # the crossed body tries to go back
		npc.move_and_collide(back * 2.0 / 60.0)
		await physics_frame
	check(door.to_local(npc.global_position).z < 0.0, "after its crossing the same body is blocked again (exception removed)")
	door.passage_validator = saved


func t_spam_interact() -> void:
	_title("reserve / cancel spam")
	await reset_state()
	await place(1.0, 2.5)
	for i in 11:
		door.interact(player)
		await frames(2)
	check(door.reserved == 1, "an odd number of presses leaves one reservation")
	door.interact(player)
	check(door.reserved == 0 and door.available == 2 and solo._pending_door == null, "the next press cancels it: no leftovers anywhere")
	check(await wait_until(func() -> bool: return not door.is_open, 5.0), "the door ends up closed")
	check(solo._points == 10, "no points moved")


func t_freed_reservation_holder() -> void:
	_title("a player that disappears while holding a reservation")
	await reset_state()
	door.reservation_timeout = 1.0
	var ghost := make_dummy()
	door.reserve_passage(ghost)
	ghost.free()
	await wait_seconds(1.6)
	check(door.reserved == 0 and door.available == 2, "the orphaned reservation is cleaned up")
	check(await wait_until(func() -> bool: return not door.is_open, 5.0), "the door closes")


# ---- helpers ---------------------------------------------------------------------------------
func check(cond: bool, label: String) -> void:
	if cond:
		passed_checks += 1
		print("  PASS  ", label)
	else:
		failed_checks += 1
		print("  FAIL  ", label)


func _title(text: String) -> void:
	print("\n== ", text)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func wait_seconds(seconds: float) -> void:
	await frames(maxi(int(seconds * 60.0), 1))


func wait_until(cond: Callable, timeout: float) -> bool:
	var n := int(timeout * 60.0)
	for i in n:
		if cond.call():
			return true
		await physics_frame
	return cond.call()


## One complete crossing from the +z side. True if the player ended up on the far side.
func cross_once() -> bool:
	await place(1.0, 2.5)
	door.interact(player)
	await wait_until(func() -> bool: return door.is_open, 4.0)
	var reached := await walk(1.0, 2.5)
	await wait_until(func() -> bool: return not door.is_open, 4.0)
	return reached


func lit_pips(m) -> int:
	var n := 0
	for pip in m._pips:
		if pip.material_override == m._pip_on:
			n += 1
	return n


func units_lit(m) -> String:
	var letters: Array[String] = []
	for letter in "ABCDEFG":
		if m._segs["Units"][letter].material_override == m._digit_on:
			letters.append(letter)
	return "".join(letters)


func passed_of(d: StandardDoor) -> int:
	var v = d.get("passed")
	return int(v) if v != null else 0


## A second physical body (same capsule as the player) so two bodies can use the doorway at once.
func make_body() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.88
	shape.shape = capsule
	body.add_child(shape)
	level.add_child(body)
	_dummies.append(body)
	return body


func make_dummy() -> Node3D:
	var d := Node3D.new()
	level.add_child(d)
	_dummies.append(d)
	return d


## Back to a known state: no reservations, door closed, 10 points.
func reset_state() -> void:
	for d in _dummies:
		if is_instance_valid(d):
			door.release_passage(d)
			d.queue_free()
	_dummies.clear()
	door.release_passage(player)
	if door.has_method("reset_round"):
		door.reset_round()
	door.reservation_timeout = 15.0
	solo._points = 10
	solo._pending_door = null
	solo._eliminated = false
	player.global_position = door.global_position + Vector3(0, 40, 0)
	await wait_until(func() -> bool: return not door.is_open and not door._anim.is_playing(), 5.0)
	await frames(3)


## Put the player on one side of the doorway: side = +1 / -1 (local z of the door), dist metres away.
func place(side: float, dist: float) -> void:
	var pos := door.global_position + door.global_transform.basis.z * side * dist
	pos.y = door.global_position.y + HALF_HEIGHT + 0.05
	player.global_position = pos
	player.velocity = Vector3.ZERO
	await frames(4)


## Walk straight through the doorway until `dist` metres past it. True if the far side was reached.
func walk(side: float, dist: float) -> bool:
	var dir := -door.global_transform.basis.z * side
	for i in 420:
		player.move_and_collide(dir * 3.0 / 60.0)
		await physics_frame
		if door.to_local(player.global_position).z * side <= -dist + 0.05:
			await frames(3)
			return true
	return false


## Walk along the door axis to a given local z (used for backing out).
func walk_to_local_z(target_z: float) -> void:
	for i in 420:
		var z := door.to_local(player.global_position).z
		if absf(z - target_z) < 0.05:
			break
		var dir := door.global_transform.basis.z * signf(target_z - z)
		player.move_and_collide(dir * 3.0 / 60.0)
		await physics_frame
	await frames(3)
