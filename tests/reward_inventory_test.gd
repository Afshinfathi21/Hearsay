extends SceneTree
## Mini-game reward and inventory tests (phase 7).
##   Stage A: the rules (RewardManager, PlayerInventory, HintBuilder, mini-game room placement), no scene.
##   Stage B: the real level: mini-game result -> inventory -> HUD slot -> armed protection -> room effect.
##
##   godot --headless --path . --script res://tests/reward_inventory_test.gd
##
## Exit code 0 = everything passed, 1 = at least one check failed.

const GEN := "res://Levels/The Exit Room/building_generator.gd"
const LEVEL := "res://Levels/The Exit Room/BaseLevel.tscn"
const R = preload("res://Gameplay/Rewards/reward_catalog.gd")

var passed := 0
var failed := 0
var gen_script: Script


func _init() -> void:
	gen_script = load(GEN)
	_run()


func _run() -> void:
	t_catalog()
	t_inventory()
	t_minigame_rewards()
	t_information()
	t_hints_are_vague()
	t_protection()
	t_manipulation()
	t_trading_and_reuse()
	t_minigame_rooms()
	await t_level()
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


# ---- stage A -----------------------------------------------------------------------------------
func t_catalog() -> void:
	_title("catalog and reward rolls")
	var ok := true
	for kind in R.ITEMS:
		var d: Dictionary = R.ITEMS[kind]
		ok = ok and d.has("name") and d.has("text") and int(d["category"]) in [0, 1, 2]
	check(ok, "every item has a name, a description and a category")
	check(R.kinds_in(R.Category.INFORMATION).size() >= 4 and R.kinds_in(R.Category.PROTECTION).size() >= 3
		and R.kinds_in(R.Category.MANIPULATION).size() >= 2, "all three reward categories have items")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var manip := 0
	for i in 2000:
		if int(R.info(R.roll(rng, i % 3, false))["category"]) == R.Category.MANIPULATION:
			manip += 1
	check(manip == 0, "no manipulation item is rolled when there is nobody to target")
	var prot := [0, 0, 0]
	for z in 3:
		for i in 3000:
			if int(R.info(R.roll(rng, z, true))["category"]) == R.Category.PROTECTION:
				prot[z] += 1
	check(prot[0] < prot[2], "protection is more common near the exit than near the start (%d vs %d of 3000)" % [prot[0], prot[2]])


func t_inventory() -> void:
	_title("inventory")
	var inv := PlayerInventory.new()
	inv.capacity = 2
	var a := inv.add(R.EXIT_HINT)
	var b := inv.add(R.POINT_GUARD)
	check(a > 0 and b > 0 and a != b, "items get distinct ids")
	check(inv.is_full() and inv.add(R.TRAP_SCAN) == 0, "a full inventory refuses a third item")
	check(inv.add("nonsense") == 0, "an unknown kind is refused")
	check(inv.slot_uid(0) == a and inv.slot_uid(1) == b and inv.slot_uid(2) == 0, "slots map to item ids")
	var snap := inv.snapshot()
	check(snap.size() == 2 and snap[1]["name"] == "POINT GUARD" and snap[0]["slot"] == 0, "the snapshot has what the HUD needs")
	check(inv.remove(a) and not inv.remove(a) and not inv.is_full(), "removing frees the slot, only once")
	check(inv.slot_uid(0) == b, "later items move up")


func t_minigame_rewards() -> void:
	_title("mini-game rewards")
	var mgr := _mgr()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lost := mgr.complete_minigame(1, "C4", false, 1, rng)
	check(not lost["ok"] and lost["reason"] == "lost" and mgr.inventory_of(1).count() == 0, "losing gives nothing")
	check(not mgr.minigame_claimed(1, "C4"), "a loss does not use up the room's reward")
	var won := mgr.complete_minigame(1, "C4", true, 1, rng)
	check(won["ok"] and mgr.inventory_of(1).count() == 1 and R.exists(won["kind"]), "winning adds one item to the inventory")
	var again := mgr.complete_minigame(1, "C4", true, 1, rng)
	check(not again["ok"] and again["reason"] == "already_done" and mgr.inventory_of(1).count() == 1, "the same room rewards a player only once")
	check(mgr.complete_minigame(2, "C4", true, 1, rng)["ok"], "another player can still win that room")
	check(mgr.complete_minigame(1, "D1", true, 1, rng)["ok"], "another room rewards again")
	check(not mgr.complete_minigame(99, "C4", true, 1, rng)["ok"], "an unknown player gets nothing")
	check(mgr.complete_minigame(3, "X1", true, 0, rng, false, R.TRAP_SCAN)["kind"] == R.TRAP_SCAN, "a mini-game can name its own reward instead of the random roll")
	check(R.exists(mgr.complete_minigame(3, "X2", true, 0, rng, false, "nonsense")["kind"]), "an unknown named reward falls back to the random roll")
	mgr.complete_minigame(1, "D2", true, 1, rng)
	mgr.complete_minigame(1, "D3", true, 1, rng)
	check(mgr.inventory_of(1).is_full(), "the inventory fills up (4 slots)")
	var full := mgr.complete_minigame(1, "D4", true, 1, rng)
	check(not full["ok"] and full["reason"] == "inventory_full" and not mgr.minigame_claimed(1, "D4"), "a full inventory refuses the reward and keeps the claim")
	mgr.discard(1, mgr.inventory_of(1).slot_uid(0))
	check(mgr.complete_minigame(1, "D4", true, 1, rng)["ok"], "after discarding, the same room can reward again")


func t_information() -> void:
	_title("information items")
	var gen := _generate(7)
	var from: Vector2i = gen.start_room
	var path := HintBuilder.path_to_exit(gen, from)
	var mgr := _mgr()
	var ctx := {"generator": gen, "room": from}

	var uid := mgr.inventory_of(1).add(R.TRAP_SCAN)
	var res := mgr.use_item(1, uid, ctx)
	var target: Vector2i = path[1]
	check(res["ok"] and res["data"]["trap"] == (gen.rooms[target].penalty != gen.PENALTY_NONE), "TRAP SCAN tells the truth about the room toward the exit")
	check(mgr.inventory_of(1).count() == 0, "the item is used up")

	uid = mgr.inventory_of(1).add(R.TRAP_SCAN)
	check(gen.start_distance > mgr.scan_range, "(test setup) the exit is out of scan range")
	var far := mgr.use_item(1, uid, {"generator": gen, "room": from, "target_room": gen.exit_room})
	check(not far["ok"] and far["reason"] == "out_of_range" and mgr.inventory_of(1).count() == 1, "a room out of range is refused and the item is kept")
	var picked: Vector2i = HintBuilder.neighbours(gen, from)[0]
	var near := mgr.use_item(1, uid, {"generator": gen, "room": from, "target_room": picked})
	check(near["ok"] and near["text"].contains(gen.rooms[picked].label), "the player can pick a nearby room to scan")

	uid = mgr.inventory_of(1).add(R.ROOM_INSPECT)
	var insp := mgr.use_item(1, uid, ctx)
	var rd = gen.rooms[path[1]]
	var expect := "NO PENALTY"
	if rd.penalty == gen.PENALTY_LOSE_POINTS:
		expect = "LOSES %d" % rd.amount
	elif rd.penalty == gen.PENALTY_SKIP_ROUND:
		expect = "LOCKDOWN"
	check(insp["ok"] and insp["text"].contains(expect), "ROOM INSPECT shows the room's effect (%s)" % insp["text"])

	uid = mgr.inventory_of(1).add(R.EXIT_HINT)
	var nogen := mgr.use_item(1, uid, {})
	check(not nogen["ok"] and nogen["reason"] == "no_context" and mgr.inventory_of(1).count() == 1, "an information item without level data fails and is kept")

	# the three vague hints are TRUE, checked against the raw room data from several rooms and seeds
	var wrong := 0
	var total := 0
	for s in range(1, 31):
		var g := _generate(s)
		for room: Vector2i in [g.start_room, g.exit_room, g.room_list[g.room_list.size() / 2].coord]:
			total += 1
			if not _hint_is_true(g, room, HintBuilder.nearby_hint(g, room), "nearby"):
				wrong += 1
			if not _hint_is_true(g, room, HintBuilder.route_hint(g, room), "route"):
				wrong += 1
			if not _hint_is_true(g, room, HintBuilder.exit_hint(g), "exit"):
				wrong += 1
		g.free()
	check(wrong == 0, "AHEAD, ROUTE and EXIT hints were true in all %d cases checked" % (total * 3))
	gen.free()


func t_hints_are_vague() -> void:
	_title("hints are useful but not complete")
	var leaks := 0
	var checked := 0
	for s in range(1, 21):
		var g := _generate(s)
		var from: Vector2i = g.start_room
		for hint in [HintBuilder.nearby_hint(g, from), HintBuilder.route_hint(g, from), HintBuilder.exit_hint(g)]:
			checked += 1
			for rd in g.room_list:
				if str(hint["text"]).contains(rd.label):
					leaks += 1
		g.free()
	check(leaks == 0, "AHEAD, ROUTE and EXIT hints never name a room (%d hints)" % checked)
	var g := _generate(3)
	var exact: String = HintBuilder.exit_hint(g)["text"]
	check(not exact.contains(g.rooms[g.exit_room].label), "the exit hint gives a side, not the exit room")
	g.free()


func t_protection() -> void:
	_title("protection items")
	var mgr := _mgr()
	var inv := mgr.inventory_of(1)
	check(mgr.resolve_lose_points(1, 2)["amount"] == 2 and not mgr.resolve_lockdown(1), "with nothing armed, effects hit in full")

	var uid := inv.add(R.PENALTY_SHIELD)
	var armed := mgr.use_item(1, uid, {})
	check(armed["ok"] and mgr.is_armed(1, R.PENALTY_SHIELD) and inv.count() == 0, "using a SHIELD arms it and uses up the item")
	check(mgr.armed_names(1) == ["SHIELD"], "the HUD can list what is armed")
	uid = inv.add(R.PENALTY_SHIELD)
	var twice := mgr.use_item(1, uid, {})
	check(not twice["ok"] and twice["reason"] == "already_armed" and inv.count() == 1, "arming the same protection twice is refused and the item kept")
	check(not mgr.is_armed(2, R.PENALTY_SHIELD), "one player's protection does not protect another")
	var hit := mgr.resolve_lose_points(1, 2)
	check(hit["amount"] == 1 and not hit["blocked"] and hit["by"] == R.PENALTY_SHIELD, "a SHIELD takes 1 point off the penalty (2 -> 1)")
	check(not mgr.is_armed(1, R.PENALTY_SHIELD) and mgr.resolve_lose_points(1, 2)["amount"] == 2, "the SHIELD protects once only")
	mgr.use_item(1, uid, {})
	check(mgr.resolve_lose_points(1, 1)["blocked"], "a SHIELD fully blocks a 1-point penalty")

	inv.add(R.POINT_GUARD)
	mgr.use_item(1, inv.slot_uid(0), {})
	inv.add(R.PENALTY_SHIELD)
	mgr.use_item(1, inv.slot_uid(0), {})
	var g := mgr.resolve_lose_points(1, 3)
	check(g["blocked"] and g["amount"] == 0 and g["by"] == R.POINT_GUARD and mgr.is_armed(1, R.PENALTY_SHIELD), "a POINT GUARD blocks everything and is used before a SHIELD")

	inv.add(R.LOCKDOWN_BREAKER)
	mgr.use_item(1, inv.slot_uid(0), {})
	check(mgr.resolve_lose_points(1, 1)["by"] == R.PENALTY_SHIELD, "a LOCKDOWN BREAKER does not touch points penalties")
	check(mgr.resolve_lockdown(1) and not mgr.resolve_lockdown(1), "a LOCKDOWN BREAKER absorbs one lockdown only")


func t_manipulation() -> void:
	_title("manipulation items")
	var gen := _generate(9)
	var mgr := _mgr()
	var got: Array = []
	mgr.tip_received.connect(func(pid: int, text: String) -> void: got.append([pid, text]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var uid := mgr.inventory_of(1).add(R.FALSE_TIP)
	var ctx := {"generator": gen, "target_player": 2, "rng": rng, "player_rooms": {2: gen.start_room}}
	var sent := mgr.use_item(1, uid, ctx)
	check(sent["ok"] and got.size() == 1 and got[0][0] == 2 and got[0][1] != "", "FALSE TIP delivers a hint to the target player")
	check(mgr.tips_log.size() == 1 and mgr.tips_log[0]["from"] == 1 and mgr.tips_log[0]["true"] == false, "the host logs who sent it and that it is false")

	var same := 0
	for s in range(1, 41):
		var g := _generate(s)
		var from: Vector2i = g.start_room
		for pair in [[HintBuilder.nearby_hint(g, from, true), HintBuilder.nearby_hint(g, from)],
				[HintBuilder.route_hint(g, from, true), HintBuilder.route_hint(g, from)],
				[HintBuilder.exit_hint(g, true), HintBuilder.exit_hint(g)]]:
			if pair[0]["text"] == pair[1]["text"] or pair[0]["true"]:
				same += 1
		g.free()
	check(same == 0, "a false tip never matches the true hint of the same kind (120 pairs)")

	uid = mgr.inventory_of(1).add(R.FALSE_TIP)
	var self_t := mgr.use_item(1, uid, {"generator": gen, "target_player": 1})
	var nobody := mgr.use_item(1, uid, {"generator": gen, "target_player": 42})
	check(not self_t["ok"] and not nobody["ok"] and mgr.inventory_of(1).count() == 1, "a manipulation item needs another existing player; failed uses keep the item")

	mgr.inventory_of(1).add(R.INFO_JAMMER)
	var jam := mgr.use_item(1, mgr.inventory_of(1).slot_uid(1), {"target_player": 2})
	check(jam["ok"], "JAMMER aimed at player 2")
	var inv2 := mgr.inventory_of(2)
	inv2.add(R.PENALTY_SHIELD)
	check(mgr.use_item(2, inv2.slot_uid(0), {})["ok"] and mgr.is_armed(2, R.PENALTY_SHIELD), "a jammer does not affect protection items")
	inv2.add(R.EXIT_HINT)
	inv2.add(R.EXIT_HINT)
	var jammed := mgr.use_item(2, inv2.slot_uid(0), {"generator": gen})
	check(jammed["ok"] and jammed["data"].get("jammed", false) and jammed["text"].contains("JAMMED"), "the target's next information item shows nothing")
	var normal := mgr.use_item(2, inv2.slot_uid(0), {"generator": gen})
	check(normal["ok"] and not normal["data"].has("jammed") and normal["text"].contains("EXIT"), "the item after that works normally")
	gen.free()


func t_trading_and_reuse() -> void:
	_title("undecided rules are switches (off by default)")
	var mgr := _mgr()
	var uid := mgr.inventory_of(1).add(R.POINT_GUARD)
	var t := mgr.transfer_item(1, uid, 2)
	check(not t["ok"] and t["reason"] == "not_tradable" and mgr.inventory_of(1).count() == 1 and mgr.inventory_of(2).count() == 0, "items cannot be traded by default")
	mgr.tradable = true
	t = mgr.transfer_item(1, uid, 2)
	check(t["ok"] and mgr.inventory_of(1).count() == 0 and mgr.inventory_of(2).count() == 1, "with trading switched on the item moves to the other player")
	for i in 4:
		mgr.inventory_of(1).add(R.EXIT_HINT)
	var uid2 := mgr.inventory_of(2).slot_uid(0)
	check(mgr.transfer_item(2, uid2, 1)["reason"] == "target_full" and mgr.inventory_of(2).count() == 1, "a full inventory cannot receive a traded item")

	var keep := _mgr()
	keep.reusable = true
	var gen := _generate(4)
	var hint := keep.inventory_of(1).add(R.EXIT_HINT)
	keep.use_item(1, hint, {"generator": gen})
	check(keep.inventory_of(1).count() == 1, "with re-use switched on the item stays after use")
	gen.free()


func t_minigame_rooms() -> void:
	_title("optional mini-game rooms")
	var bad := 0
	var rooms := 0
	var with_game := 0
	var zone_rooms := [0, 0, 0]
	var zone_games := [0, 0, 0]
	var changed_effects := 0
	for s in range(1, 201):
		var g := _generate(s)
		var off := _generate(s, 0.0)
		if _effects(g) != _effects(off):
			changed_effects += 1
		for rd in g.room_list:
			rooms += 1
			if rd.is_start or rd.is_exit:
				continue
			zone_rooms[rd.zone] += 1
			if rd.minigame:
				with_game += 1
				zone_games[rd.zone] += 1
				if rd.penalty == g.PENALTY_SKIP_ROUND:
					bad += 1
		if g.rooms[g.start_room].minigame or g.rooms[g.exit_room].minigame:
			bad += 1
		g.free()
		off.free()
	var share := float(with_game) / rooms
	check(bad == 0, "no mini-game in the start room, the exit room or a lockdown room")
	check(share > 0.05 and share < 0.20, "about 12%% of rooms offer a mini-game (%.1f%%)" % (share * 100.0))
	check(float(zone_games[0]) / zone_rooms[0] < float(zone_games[1]) / zone_rooms[1], "mini-games are more common in the middle than near the start")
	check(changed_effects == 0, "mini-games never change the penalties or the route guarantee")
	var a := _generate(8)
	var b := _generate(8)
	check(_games(a) == _games(b), "the same seed puts mini-games in the same rooms")
	a.free()
	b.free()


# ---- stage B: the real level -------------------------------------------------------------------
func t_level() -> void:
	_title("level: mini-game -> inventory -> HUD -> protection")
	var level: Node = (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for i in 15:
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
		solo._penalised[rd.label] = true                  # no room effects unless a test asks for one
	check(gen != null and player != null and hud != null and hud.inventory_bar != null, "level, player and HUD with an inventory bar found")

	var game_room = null
	for rd in gen.room_list:
		if rd.minigame:
			game_room = rd
			break
	check(game_room != null, "the level has an optional mini-game room")
	var early: Dictionary = solo.report_minigame_result(game_room.label, true)
	check(not early["ok"] and early["reason"] == "no_minigame" and solo._rewards.inventory_of(1).count() == 0, "a result cannot be claimed from another room")
	solo._on_room_entered(game_room, player)
	check(not solo.report_minigame_result(game_room.label, false)["ok"], "a lost mini-game gives nothing")
	var win: Dictionary = solo.report_minigame_result(game_room.label, true)
	check(win["ok"] and solo._rewards.inventory_of(1).count() == 1, "a won mini-game puts an item in the inventory (%s)" % win.get("title", ""))
	check(hud.inventory_bar.filled_count() == 1, "the HUD shows the item in a slot")
	check(not solo.report_minigame_result(game_room.label, true)["ok"], "the same room does not reward twice")

	# protection through the HUD button and a real room effect
	var inv: PlayerInventory = solo._rewards.inventory_of(1)
	inv.remove(inv.slot_uid(0))
	inv.add(RewardCatalog.PENALTY_SHIELD)
	solo._push_state()
	hud.inventory_bar._buttons[0].pressed.emit()
	check(solo._rewards.is_armed(1, RewardCatalog.PENALTY_SHIELD), "pressing the slot makes the host arm the SHIELD")
	check(hud.inventory_bar.filled_count() == 0 and hud.inventory_bar._armed_label.visible, "the slot is used up and the HUD shows it as armed")
	var lose_room = null                                  # prefer a 2-point room so the reduction is visible
	for want in [2, 1]:
		for rd in gen.room_list:
			if lose_room == null and rd.penalty == gen.PENALTY_LOSE_POINTS and rd.amount == want and not rd.is_start:
				lose_room = rd
	solo._points = 10
	solo._penalised.erase(lose_room.label)
	solo._on_room_entered(lose_room, player)
	check(solo._points == 10 - (lose_room.amount - 1), "the room takes %d instead of %d points (10 -> %d)" % [lose_room.amount - 1, lose_room.amount, solo._points])
	check(not solo._rewards.is_armed(1, RewardCatalog.PENALTY_SHIELD), "the SHIELD is used up by that room")

	inv.add(RewardCatalog.LOCKDOWN_BREAKER)
	solo._push_state()
	hud.inventory_bar._buttons[0].pressed.emit()
	var lock_room = null
	for rd in gen.room_list:
		if rd.penalty == gen.PENALTY_SKIP_ROUND:
			lock_room = rd
			break
	var before: int = solo._points
	solo._penalised.erase(lock_room.label)
	solo._on_room_entered(lock_room, player)
	check(not solo._rewards.is_armed(1, RewardCatalog.LOCKDOWN_BREAKER) and solo._points == before, "a LOCKDOWN BREAKER absorbs the lockdown")
	solo._on_room_entered(lose_room, player)
	solo._on_room_entered(lose_room, player)
	check(solo._points == 10 - (lose_room.amount - 1), "walking into the same room again does not charge it again")


# ---- helpers -----------------------------------------------------------------------------------
func _mgr() -> RewardManager:
	var m := RewardManager.new()
	for id in [1, 2, 3]:
		m.add_player(id)
	return m


func _generate(seed_value: int, minigames := 0.12) -> Node3D:
	var g := Node3D.new()
	g.set_script(gen_script)
	g.seed_value = seed_value
	g.minigame_fraction = minigames
	g.rng.seed = seed_value
	g._make_rooms()
	g._choose_exit()
	g._choose_start()
	g._assign_penalties()
	g._assign_minigames()
	g._build_links()
	return g


func _effects(g: Node3D) -> String:
	var parts: Array[String] = ["%s>%s" % [g.start_room, g.exit_room]]
	for rd in g.room_list:
		parts.append("%d:%d" % [rd.penalty, rd.amount])
	return "|".join(parts)


func _games(g: Node3D) -> String:
	var parts: Array[String] = []
	for rd in g.room_list:
		if rd.minigame:
			parts.append(rd.label)
	return ",".join(parts)


## Independent check of a hint against the raw room data.
func _hint_is_true(g: Node3D, from: Vector2i, hint: Dictionary, kind: String) -> bool:
	var text: String = hint["text"]
	if not hint["true"]:
		return false
	if kind == "nearby":
		var ahead := HintBuilder.path_to_exit(g, from).slice(1, 4)
		if ahead.is_empty():
			return true
		var any := false
		for c in ahead:
			any = any or g.rooms[c].penalty != g.PENALTY_NONE
		return text.begins_with("AT LEAST ONE") == any
	if kind == "route":
		var names := ["NORTHERN", "EASTERN", "SOUTHERN", "WESTERN"]
		for d in 4:
			if text.contains(names[d]):
				return _danger(g, from, d) > 0
		if text.begins_with("NO DANGEROUS"):
			for d in 4:
				if _danger(g, from, d) > 0:
					return false
		return true
	var centre := (int(g.rooms_per_side) - 1) / 2.0
	var ox: float = g.exit_room.x - centre
	var oy: float = g.exit_room.y - centre
	if text.contains("NORTHERN"):
		return oy < 0.0
	if text.contains("SOUTHERN"):
		return oy > 0.0
	if text.contains("EASTERN"):
		return ox > 0.0
	if text.contains("WESTERN"):
		return ox < 0.0
	return absf(ox) < 0.5 and absf(oy) < 0.5


func _danger(g: Node3D, from: Vector2i, d: int) -> int:
	var n: Vector2i = from + RoomGrid.DIR_VECTORS[d]
	if not g.rooms.has(n):
		return 0
	var count := int(g.rooms[n].penalty != g.PENALTY_NONE)
	for m in HintBuilder.neighbours(g, n):
		if m != from:
			count += int(g.rooms[m].penalty != g.PENALTY_NONE)
	return count


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)


func _title(text: String) -> void:
	print("\n== ", text)
