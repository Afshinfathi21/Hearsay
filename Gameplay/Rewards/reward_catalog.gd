class_name RewardCatalog
extends RefCounted
## Every reward item a mini-game can grant. Data only: what an item does lives in RewardManager.
##
## Three categories (see the design):
##   INFORMATION  - hints about rooms, routes and the exit. Useful, but never the whole answer.
##   PROTECTION   - armed by the player, consumed by the next matching room effect.
##   MANIPULATION - affects what OTHER players see; needs a target player.

enum Category { INFORMATION, PROTECTION, MANIPULATION }

const TRAP_SCAN := "trap_scan"
const ROOM_INSPECT := "room_inspect"
const NEARBY_HINT := "nearby_hint"
const ROUTE_HINT := "route_hint"
const EXIT_HINT := "exit_hint"
const PENALTY_SHIELD := "penalty_shield"
const POINT_GUARD := "point_guard"
const LOCKDOWN_BREAKER := "lockdown_breaker"
const FALSE_TIP := "false_tip"
const INFO_JAMMER := "info_jammer"

## name: short label on the HUD slot. text: tooltip. needs_room: the player may pick a room within range.
const ITEMS := {
	TRAP_SCAN: {"name": "TRAP SCAN", "category": Category.INFORMATION, "needs_room": true,
		"text": "Tells you whether one nearby room holds a trap."},
	ROOM_INSPECT: {"name": "ROOM INSPECT", "category": Category.INFORMATION, "needs_room": true,
		"text": "Shows the exact effect of one nearby room."},
	NEARBY_HINT: {"name": "AHEAD HINT", "category": Category.INFORMATION, "needs_room": false,
		"text": "Says whether a penalty waits among the next three rooms toward the exit."},
	ROUTE_HINT: {"name": "ROUTE HINT", "category": Category.INFORMATION, "needs_room": false,
		"text": "Names a direction that has a dangerous room within two doors."},
	EXIT_HINT: {"name": "EXIT HINT", "category": Category.INFORMATION, "needs_room": false,
		"text": "Tells you which side of the building the exit is closer to."},
	PENALTY_SHIELD: {"name": "SHIELD", "category": Category.PROTECTION, "needs_room": false,
		"text": "The next points penalty you take is reduced."},
	POINT_GUARD: {"name": "POINT GUARD", "category": Category.PROTECTION, "needs_room": false,
		"text": "The next points penalty you would take is blocked completely."},
	LOCKDOWN_BREAKER: {"name": "LOCKDOWN BREAKER", "category": Category.PROTECTION, "needs_room": false,
		"text": "The next lockdown does not apply to you."},
	FALSE_TIP: {"name": "FALSE TIP", "category": Category.MANIPULATION, "needs_room": false,
		"text": "Sends another player a believable hint that is wrong."},
	INFO_JAMMER: {"name": "JAMMER", "category": Category.MANIPULATION, "needs_room": false,
		"text": "Another player's next information item shows nothing."},
}

## Chance of each category by zone of the room that holds the mini-game: [information, protection, manipulation].
## Near the start information is common; near the exit protection matters more.
const CATEGORY_WEIGHTS := [
	[0.60, 0.30, 0.10],     # near start
	[0.40, 0.40, 0.20],     # middle
	[0.25, 0.55, 0.20],     # near exit
]


static func exists(kind: String) -> bool:
	return ITEMS.has(kind)


static func info(kind: String) -> Dictionary:
	return ITEMS.get(kind, {})


static func kinds_in(category: int) -> Array[String]:
	var out: Array[String] = []
	for kind in ITEMS:
		if int(ITEMS[kind]["category"]) == category:
			out.append(kind)
	return out


## Picks a reward kind. The host owns the rng (seed it from the match seed, room and player so it is repeatable).
## allow_manipulation = false when there is nobody else to target (solo play).
static func roll(rng: RandomNumberGenerator, zone: int, allow_manipulation := true) -> String:
	var weights: Array = (CATEGORY_WEIGHTS[clampi(zone, 0, 2)] as Array).duplicate()
	if not allow_manipulation:
		weights[Category.MANIPULATION] = 0.0
	var total := 0.0
	for w in weights:
		total += float(w)
	var pick := rng.randf() * total
	var category := int(Category.INFORMATION)
	for i in weights.size():
		if float(weights[i]) <= 0.0:
			continue
		category = i
		pick -= float(weights[i])
		if pick < 0.0:
			break
	var kinds := kinds_in(category)
	return kinds[rng.randi() % kinds.size()]
