class_name HintBuilder
extends RefCounted
## Builds the information the reward items give, from the building generator's room data.
## Every function returns {"text": String, "true": bool, ...}. Hints are TRUE statements that name no room
## and no exact amount, so they help without solving the level. With fake = true the same kind of statement
## is built so that it is false: that is what a FALSE TIP sends to another player.

const SIDE_NAMES := ["NORTHERN", "EASTERN", "SOUTHERN", "WESTERN"]       # N, E, S, W like RoomGrid.Dir


## Rooms joined to c by a door (every neighbouring room that exists).
static func neighbours(gen, c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in 4:
		var n: Vector2i = c + RoomGrid.DIR_VECTORS[d]
		if gen.rooms.has(n):
			out.append(n)
	return out


## Distance in doors from origin to every reachable room.
static func distances_from(gen, origin: Vector2i) -> Dictionary:
	var dist := {origin: 0}
	var queue: Array[Vector2i] = [origin]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for n in neighbours(gen, c):
			if not dist.has(n):
				dist[n] = int(dist[c]) + 1
				queue.append(n)
	return dist


## Doors between two rooms, or -1.
static func door_distance(gen, a: Vector2i, b: Vector2i) -> int:
	return int(distances_from(gen, a).get(b, -1))


## Shortest way to the exit, starting with `from` itself. Empty when `from` is not a room.
static func path_to_exit(gen, from: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not gen.rooms.has(from):
		return path
	var dist := distances_from(gen, gen.exit_room)
	path.append(from)
	var at := from
	while at != gen.exit_room:
		var best := at
		for n in neighbours(gen, at):
			if dist.has(n) and int(dist[n]) < int(dist[best]):
				best = n
		if best == at:
			break
		path.append(best)
		at = best
	return path


## The neighbouring room that leads toward the exit: the default target of room-picking items.
static func default_target_room(gen, from: Vector2i) -> Vector2i:
	var path := path_to_exit(gen, from)
	return path[1] if path.size() > 1 else from


static func trap_scan(gen, room: Vector2i) -> Dictionary:
	var rd = gen.rooms[room]
	var trap: bool = rd.penalty != gen.PENALTY_NONE
	return {"text": "ROOM %s: %s" % [rd.label, "TRAP DETECTED" if trap else "NO TRAP FOUND"], "true": true, "trap": trap}


static func room_inspect(gen, room: Vector2i) -> Dictionary:
	var rd = gen.rooms[room]
	var what := "NO PENALTY"
	if rd.penalty == gen.PENALTY_LOSE_POINTS:
		what = "LOSES %d POINT%s" % [rd.amount, "" if rd.amount == 1 else "S"]
	elif rd.penalty == gen.PENALTY_SKIP_ROUND:
		what = "LOCKDOWN FOR %d ROUND%s" % [rd.amount, "" if rd.amount == 1 else "S"]
	if rd.minigame:
		what += " / OPTIONAL MINI-GAME"
	return {"text": "ROOM %s: %s" % [rd.label, what], "true": true}


## "One of the next three rooms toward the exit holds a penalty" (or, when none does, that they are clear).
static func nearby_hint(gen, from: Vector2i, fake := false) -> Dictionary:
	var path := path_to_exit(gen, from)
	var ahead := path.slice(1, 4)
	if ahead.is_empty():
		return {"text": "THE EXIT IS RIGHT HERE", "true": true}
	var any := false
	for c in ahead:
		if gen.rooms[c].penalty != gen.PENALTY_NONE:
			any = true
	var claim_penalty := any != fake                     # fake flips the statement
	var text := "AT LEAST ONE OF THE NEXT %d ROOMS TOWARD THE EXIT HOLDS A PENALTY" % ahead.size() if claim_penalty \
		else "THE NEXT %d ROOMS TOWARD THE EXIT ARE CLEAR" % ahead.size()
	return {"text": text, "true": not fake}


## "The eastern route has a dangerous room within two doors": the direction from here whose next two
## rooms hold the most penalties. When nothing is dangerous nearby it says so.
static func route_hint(gen, from: Vector2i, fake := false) -> Dictionary:
	var danger := {}                                     # direction -> penalty rooms within two doors that way
	for d in 4:
		var n: Vector2i = from + RoomGrid.DIR_VECTORS[d]
		if not gen.rooms.has(n):
			continue
		var count := int(gen.rooms[n].penalty != gen.PENALTY_NONE)
		for m in neighbours(gen, n):
			if m != from:
				count += int(gen.rooms[m].penalty != gen.PENALTY_NONE)
		danger[d] = count
	if danger.is_empty():
		return {"text": "NOTHING TO REPORT FROM HERE", "true": true}
	var worst := -1
	var safest := -1
	for d in danger:
		if worst < 0 or int(danger[d]) > int(danger[worst]):
			worst = d
		if int(danger[d]) == 0 and safest < 0:
			safest = d
	var anything: bool = int(danger[worst]) > 0
	var claim_dir := -1                                  # -1 = claim that nothing is dangerous
	if not fake and anything:
		claim_dir = worst
	elif fake and anything and safest >= 0:
		claim_dir = safest                               # a quiet direction, called dangerous
	elif fake and not anything:
		claim_dir = int(danger.keys()[0])
	var text := "NO DANGEROUS ROOM WITHIN TWO DOORS IN ANY DIRECTION" if claim_dir < 0 \
		else "THE %s ROUTE HAS A DANGEROUS ROOM WITHIN TWO DOORS" % SIDE_NAMES[claim_dir]
	return {"text": text, "true": not fake}


## "The exit is closer to the northern side": the side of the building the exit room leans toward.
static func exit_hint(gen, fake := false) -> Dictionary:
	var centre := (int(gen.rooms_per_side) - 1) / 2.0
	var off := Vector2(gen.exit_room.x - centre, gen.exit_room.y - centre)
	if absf(off.x) < 0.5 and absf(off.y) < 0.5:
		return {"text": "THE EXIT IS NEAR THE CENTRE OF THE BUILDING" if not fake else "THE EXIT IS CLOSER TO THE NORTHERN SIDE",
			"true": not fake}
	var side := 0
	if absf(off.x) >= absf(off.y):
		side = 1 if off.x > 0.0 else 3
	else:
		side = 2 if off.y > 0.0 else 0
	if fake:
		side = (side + 2) % 4                            # the opposite side
	return {"text": "THE EXIT IS CLOSER TO THE %s SIDE" % SIDE_NAMES[side], "true": not fake}


## A hint of a random kind for the room `from`; fake = false/true as above.
static func random_tip(gen, from: Vector2i, rng: RandomNumberGenerator, fake: bool) -> Dictionary:
	match rng.randi() % 3:
		0:
			return nearby_hint(gen, from, fake)
		1:
			return route_hint(gen, from, fake)
		_:
			return exit_hint(gen, fake)
