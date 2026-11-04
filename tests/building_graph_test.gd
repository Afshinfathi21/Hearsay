extends SceneTree
## Building graph tests (phases 5 and 6). They run the generator's own steps (rooms, exit, start, effects,
## links) for many seeds WITHOUT building meshes, then analyse the room graph:
##
##   godot --headless --path . --script res://tests/building_graph_test.gd
##
## Exit code 0 = everything passed, 1 = at least one check failed.

const GEN := "res://Levels/The Exit Room/building_generator.gd"
const SEEDS := 300

var failed := 0
var passed := 0
var gen_script: Script


func _init() -> void:
	gen_script = load(GEN)
	var st := {
		"seeds": 0, "unreachable": 0, "dead_end": 0, "exit_unreachable": 0, "start_too_far": 0,
		"no_margin": 0, "no_lockdown_free": 0, "choke_penalised": 0, "protected_penalised": 0,
		"near_lockdown": 0, "near_big": 0, "recorded_mismatch": 0, "repaired": 0, "left_sum": 0, "left_min": 999,
		"dist_sum": 0, "dist_max": 0, "dist_min": 999, "nondeterministic": 0,
		"zone_rooms": [0, 0, 0], "zone_pen": [0, 0, 0], "zone_cost": [0, 0, 0], "lockdown": 0, "lose": 0,
	}
	var budget := 10
	var margin := 2
	for s in range(1, SEEDS + 1):
		var g := _generate(s)
		budget = g.point_budget
		margin = g.min_route_margin
		_analyse(g, st)
		var again := _generate(s)                    # same seed must give the same building and effects
		if _signature(g) != _signature(again):
			st.nondeterministic += 1
		g.free()
		again.free()

	print("\n== graph invariants over %d seeds (7 x 7 rooms)" % SEEDS)
	check(st.unreachable == 0, "every room is reachable from the start room")
	check(st.dead_end == 0, "no room has fewer than 2 doors (no dead ends)")
	check(st.exit_unreachable == 0, "the exit room is reachable from the start room")
	check(st.nondeterministic == 0, "same seed gives the same start, exit and effects")

	print("\n== economy and effect rules")
	check(st.start_too_far == 0, "the start room is never farther than the budget allows")
	check(st.no_margin == 0, "a route to the exit always leaves at least %d of %d points" % [margin, budget])
	check(st.no_lockdown_free == 0, "a route without any lockdown room always exists")
	check(st.recorded_mismatch == 0, "the generator's recorded safe route matches an independent calculation")
	check(st.protected_penalised == 0, "start and exit rooms never carry an effect")
	check(st.choke_penalised == 0, "chokepoint rooms never carry an effect")
	check(st.near_lockdown == 0, "no lockdown near the start")
	check(st.near_big == 0, "near the start effects only cost 1 point")

	var n: int = st.seeds
	print("\n== report")
	print("  start->exit distance in doors: min %d, avg %.1f, max %d" % [st.dist_min, float(st.dist_sum) / n, st.dist_max])
	print("  points left on the validated route: avg %.1f, min %d" % [float(st.left_sum) / n, st.left_min])
	print("  effects removed by validation: %.1f per building" % (float(st.repaired) / n))
	print("  effects: %d lose-points, %d lockdown" % [st.lose, st.lockdown])
	var names := ["near start", "middle", "near exit"]
	for i in 3:
		print("  %-10s: effect rate %.0f%%, avg lose-points cost %.2f per effect room" % [names[i],
			100.0 * st.zone_pen[i] / maxi(st.zone_rooms[i], 1), float(st.zone_cost[i]) / maxi(st.zone_pen[i], 1)])
	check(st.zone_pen[0] * st.zone_rooms[2] < st.zone_pen[2] * st.zone_rooms[0], "effects are rarer near the start than near the exit")

	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _generate(seed_value: int) -> Node3D:
	var g := Node3D.new()
	g.set_script(gen_script)
	g.seed_value = seed_value
	g.rng.seed = seed_value
	g._make_rooms()
	g._choose_exit()
	g._choose_start()
	g._assign_penalties()
	g._build_links()
	return g


func _signature(g: Node3D) -> String:
	var parts: Array[String] = ["%s>%s" % [g.start_room, g.exit_room]]
	for rd in g.room_list:
		parts.append("%s:%d:%d" % [rd.coord, rd.penalty, rd.amount])
	return "|".join(parts)


func _analyse(g: Node3D, st: Dictionary) -> void:
	st.seeds += 1
	var adj := {}
	for rd in g.room_list:
		adj[rd.coord] = []
	for rec in g.door_records:
		if rec.is_exit:
			continue
		adj[rec.room_a].append(rec.room_b)
		adj[rec.room_b].append(rec.room_a)

	var reach := _reach(adj, g.start_room, Vector2i(-99, -99))
	if reach.size() != g.room_list.size():
		st.unreachable += 1
	if not reach.has(g.exit_room):
		st.exit_unreachable += 1
	for rd in g.room_list:
		if adj[rd.coord].size() + (1 if rd.is_exit else 0) < 2:
			st.dead_end += 1
			break

	var d: int = g.start_distance
	st.dist_sum += d
	st.dist_max = maxi(st.dist_max, d)
	st.dist_min = mini(st.dist_min, d)
	if d * g.door_cost > g.point_budget - g.min_route_margin:
		st.start_too_far += 1

	# independent route calculation: lockdown rooms cannot be entered, lose-points rooms cost extra
	var best := _cheapest(g, adj)
	if best >= 100000:
		st.no_lockdown_free += 1
	elif best > g.point_budget - g.min_route_margin:
		st.no_margin += 1
	if best != g.route_cost or g.route_points_left != g.point_budget - best:
		st.recorded_mismatch += 1
	st.left_sum += g.route_points_left
	st.left_min = mini(st.left_min, g.route_points_left)
	st.repaired += g.effects_repaired

	var chokes: Dictionary = g._chokepoints()
	for rd in g.room_list:
		var has_effect: bool = rd.penalty != g.PENALTY_NONE
		if has_effect and (rd.is_start or rd.is_exit):
			st.protected_penalised += 1
		if has_effect and chokes.has(rd.coord):
			st.choke_penalised += 1
		if rd.is_start or rd.is_exit:
			continue
		st.zone_rooms[rd.zone] += 1
		if not has_effect:
			continue
		st.zone_pen[rd.zone] += 1
		if rd.penalty == g.PENALTY_LOSE_POINTS:
			st.lose += 1
			st.zone_cost[rd.zone] += rd.amount
		else:
			st.lockdown += 1
		if rd.zone == g.ZONE_NEAR:
			if rd.penalty == g.PENALTY_SKIP_ROUND:
				st.near_lockdown += 1
			elif rd.amount > 1:
				st.near_big += 1


func _reach(adj: Dictionary, from: Vector2i, blocked: Vector2i) -> Dictionary:
	var seen := {from: true}
	var queue: Array = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for n in adj[c]:
			if n != blocked and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


## Dijkstra over the door graph; lockdown rooms are impassable. 100000 = no route.
func _cheapest(g: Node3D, adj: Dictionary) -> int:
	var cost := {g.start_room: 0}
	var open: Array = [g.start_room]
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if cost[open[i]] < cost[open[bi]]:
				bi = i
		var c: Vector2i = open.pop_at(bi)
		if c == g.exit_room:
			return cost[c]
		for n in adj[c]:
			var room = g.rooms[n]
			if room.penalty == g.PENALTY_SKIP_ROUND:
				continue
			var nc: int = cost[c] + g.door_cost + (room.amount if room.penalty == g.PENALTY_LOSE_POINTS else 0)
			if not cost.has(n) or nc < cost[n]:
				cost[n] = nc
				if not open.has(n):
					open.append(n)
	return 100000


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)
