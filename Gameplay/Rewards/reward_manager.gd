class_name RewardManager
extends RefCounted
## The host's rules for mini-game rewards: who owns which items, what using an item does, which protections are
## armed. It never touches the UI, nodes, points or the scene: it returns plain result Dictionaries, so the
## authoritative host decides what to show and apply, and a network layer can later call the same methods.
##
## Player actions the host validates through this class:
##   complete_minigame()  a mini-game ended; a win puts ONE reward item in the player's inventory
##   use_item()           the player uses an item whenever and wherever they like (not tied to the room won in)
##   discard() / transfer_item()
## Events the host reports before it applies them:
##   resolve_lose_points() / resolve_lockdown()   protections that were armed by the player
##
## Open design questions are switches, not assumptions: `tradable` and `reusable` default to false.

signal item_granted(player_id: int, kind: String)
signal item_used(player_id: int, kind: String, result: Dictionary)
## A tip (possibly false) reached a player. The sender and the truth are only in tips_log.
signal tip_received(player_id: int, text: String)
signal protection_used(player_id: int, kind: String)

const REASONS := {
	"unknown_player": "NO SUCH PLAYER",
	"no_such_item": "YOU DO NOT HAVE THAT ITEM",
	"lost": "MINI-GAME LOST: NO REWARD",
	"already_done": "YOU ALREADY CLAIMED THIS ROOM'S REWARD",
	"inventory_full": "INVENTORY FULL: DISCARD AN ITEM FIRST",
	"already_armed": "THAT PROTECTION IS ALREADY ARMED",
	"out_of_range": "THAT ROOM IS TOO FAR AWAY",
	"bad_target": "INVALID TARGET",
	"no_context": "NOTHING TO READ HERE",
	"not_tradable": "ITEMS CANNOT BE TRADED",
	"target_full": "THEIR INVENTORY IS FULL",
}

## Inventory slots per player (applied to players added after the change).
var slots := 4
## Can players give items to each other? Undecided in the design: off until decided.
var tradable := false
## Is an item kept after use? Undecided in the design: off (items are used up) until decided.
var reusable := false
## Points a SHIELD takes off the next penalty.
var shield_reduction := 1
## How many doors away a room may be for TRAP SCAN / ROOM INSPECT.
var scan_range := 2
## Every tip sent with FALSE TIP, for the host: {"from", "to", "text", "true"}.
var tips_log: Array[Dictionary] = []

var _inventories := {}                   # player id -> PlayerInventory
var _armed := {}                         # player id -> {kind: true}
var _jammed := {}                        # player id -> true: the next information item shows nothing
var _claimed := {}                       # "player|room label" -> true


func add_player(player_id: int) -> void:
	if _inventories.has(player_id):
		return
	var inv := PlayerInventory.new()
	inv.capacity = slots
	_inventories[player_id] = inv
	_armed[player_id] = {}


func has_player(player_id: int) -> bool:
	return _inventories.has(player_id)


func inventory_of(player_id: int) -> PlayerInventory:
	return _inventories.get(player_id)


func minigame_claimed(player_id: int, room_label: String) -> bool:
	return _claimed.has(_claim_key(player_id, room_label))


func is_armed(player_id: int, kind: String) -> bool:
	return (_armed.get(player_id, {}) as Dictionary).has(kind)


## Names of the protections the player has armed, for the HUD.
func armed_names(player_id: int) -> Array[String]:
	var out: Array[String] = []
	for kind in (_armed.get(player_id, {}) as Dictionary):
		out.append(str(RewardCatalog.info(kind)["name"]))
	return out


# ---- rewards -------------------------------------------------------------------------------------
## A mini-game ended. Only a win gives something: one item, once per player and room. The item is random for the
## room's zone unless the mini-game names its own reward (forced_kind, e.g. Don't Blink always gives TRAP SCAN).
## A full inventory refuses the reward WITHOUT using the claim up, so the player can free a slot and try again.
func complete_minigame(player_id: int, room_label: String, won: bool, zone: int,
		rng: RandomNumberGenerator, allow_manipulation := true, forced_kind := "") -> Dictionary:
	var inv: PlayerInventory = inventory_of(player_id)
	if inv == null:
		return _fail("unknown_player")
	if minigame_claimed(player_id, room_label):
		return _fail("already_done")
	if not won:
		return _fail("lost")
	if inv.is_full():
		return _fail("inventory_full")
	var kind := forced_kind if RewardCatalog.exists(forced_kind) else RewardCatalog.roll(rng, zone, allow_manipulation)
	var uid := inv.add(kind)
	_claimed[_claim_key(player_id, room_label)] = true
	item_granted.emit(player_id, kind)
	var def := RewardCatalog.info(kind)
	return {"ok": true, "reason": "", "kind": kind, "uid": uid, "title": def["name"], "text": "ADDED TO YOUR INVENTORY", "data": {}}


# ---- using items ---------------------------------------------------------------------------------
## Use an item. ctx (all keys optional unless the item needs them):
##   "generator"      the building generator (room data)             needed by information items
##   "room"           Vector2i, the room the player is in            default: the start room
##   "target_room"    Vector2i, for TRAP SCAN / ROOM INSPECT         default: the next room toward the exit
##   "target_player"  int, for manipulation items
##   "player_rooms"   {player id: Vector2i}, where players are       used by FALSE TIP
##   "rng"            RandomNumberGenerator                          used by FALSE TIP
## Returns {ok, reason, kind, uid, title, text, data}. A failed use changes nothing and keeps the item.
func use_item(player_id: int, uid: int, ctx := {}) -> Dictionary:
	var inv: PlayerInventory = inventory_of(player_id)
	if inv == null:
		return _fail("unknown_player")
	var item := inv.get_item(uid)
	if item.is_empty():
		return _fail("no_such_item")
	var kind: String = item["kind"]
	var def := RewardCatalog.info(kind)
	var result := {"ok": true, "reason": "", "kind": kind, "uid": uid, "title": def["name"], "text": "", "data": {}}
	var category := int(def["category"])

	if category == RewardCatalog.Category.INFORMATION:
		var gen = ctx.get("generator")
		if gen == null:
			return _fail("no_context", kind)
		if _jammed.has(player_id):                       # a JAMMER hit this player: the item is wasted
			_jammed.erase(player_id)
			result["text"] = "SIGNAL JAMMED: NOTHING RECEIVED"
			result["data"] = {"jammed": true}
			return _finish(inv, player_id, uid, kind, result)
		var from: Vector2i = ctx.get("room", gen.start_room)
		var read := _read_information(gen, kind, from, ctx)
		if read.has("error"):
			return _fail(str(read["error"]), kind)
		result["text"] = read["text"]
		result["data"] = read
		return _finish(inv, player_id, uid, kind, result)

	if category == RewardCatalog.Category.PROTECTION:
		if is_armed(player_id, kind):
			return _fail("already_armed", kind)
		_armed[player_id][kind] = true
		result["text"] = "ARMED: WAITING FOR THE NEXT MATCHING EFFECT"
		return _finish(inv, player_id, uid, kind, result)

	# manipulation: needs another player
	var target := int(ctx.get("target_player", -1))
	if target == player_id or not has_player(target):
		return _fail("bad_target", kind)
	if kind == RewardCatalog.FALSE_TIP:
		var gen = ctx.get("generator")
		if gen == null:
			return _fail("no_context", kind)
		var rooms: Dictionary = ctx.get("player_rooms", {})
		var at: Vector2i = rooms.get(target, gen.start_room)
		var rng: RandomNumberGenerator = ctx.get("rng", RandomNumberGenerator.new())
		var tip := HintBuilder.random_tip(gen, at, rng, true)
		tips_log.append({"from": player_id, "to": target, "text": tip["text"], "true": tip["true"]})
		tip_received.emit(target, tip["text"])
		result["text"] = "TIP SENT"
	else:                                                # INFO_JAMMER
		_jammed[target] = true
		result["text"] = "THEIR NEXT INFORMATION ITEM WILL SHOW NOTHING"
	return _finish(inv, player_id, uid, kind, result)


## Information items. Returns the hint Dictionary, or {"error": reason} when the target is not valid.
func _read_information(gen, kind: String, from: Vector2i, ctx: Dictionary) -> Dictionary:
	match kind:
		RewardCatalog.NEARBY_HINT:
			return HintBuilder.nearby_hint(gen, from)
		RewardCatalog.ROUTE_HINT:
			return HintBuilder.route_hint(gen, from)
		RewardCatalog.EXIT_HINT:
			return HintBuilder.exit_hint(gen)
	var target: Vector2i = ctx.get("target_room", HintBuilder.default_target_room(gen, from))
	if not gen.rooms.has(target):
		return {"error": "bad_target"}
	var dist := HintBuilder.door_distance(gen, from, target)
	if dist < 0 or dist > scan_range:
		return {"error": "out_of_range"}
	return HintBuilder.trap_scan(gen, target) if kind == RewardCatalog.TRAP_SCAN else HintBuilder.room_inspect(gen, target)


# ---- protections ---------------------------------------------------------------------------------
## The host calls this when a room is about to take points from the player. Returns
## {"amount": points to take after protection, "blocked": bool, "by": item kind or ""}.
## A POINT GUARD blocks the whole penalty; otherwise a SHIELD takes `shield_reduction` off.
func resolve_lose_points(player_id: int, amount: int) -> Dictionary:
	if _consume_armed(player_id, RewardCatalog.POINT_GUARD):
		return {"amount": 0, "blocked": true, "by": RewardCatalog.POINT_GUARD}
	if _consume_armed(player_id, RewardCatalog.PENALTY_SHIELD):
		var left := maxi(amount - shield_reduction, 0)
		return {"amount": left, "blocked": left == 0, "by": RewardCatalog.PENALTY_SHIELD}
	return {"amount": amount, "blocked": false, "by": ""}


## The host calls this when a lockdown is about to hit the player. True = a LOCKDOWN BREAKER absorbed it.
func resolve_lockdown(player_id: int) -> bool:
	return _consume_armed(player_id, RewardCatalog.LOCKDOWN_BREAKER)


# ---- inventory management ------------------------------------------------------------------------
func discard(player_id: int, uid: int) -> bool:
	var inv: PlayerInventory = inventory_of(player_id)
	return inv != null and inv.remove(uid)


## Give an item to another player. Refused while `tradable` is off.
func transfer_item(from_id: int, uid: int, to_id: int) -> Dictionary:
	var from_inv: PlayerInventory = inventory_of(from_id)
	var to_inv: PlayerInventory = inventory_of(to_id)
	if from_inv == null or to_inv == null or from_id == to_id:
		return _fail("bad_target")
	if not tradable:
		return _fail("not_tradable")
	var item := from_inv.get_item(uid)
	if item.is_empty():
		return _fail("no_such_item")
	if to_inv.is_full():
		return _fail("target_full")
	var kind: String = item["kind"]
	from_inv.remove(uid)
	to_inv.add(kind)
	return {"ok": true, "reason": "", "kind": kind, "uid": uid, "title": RewardCatalog.info(kind)["name"], "text": "ITEM GIVEN", "data": {}}


# ---- internals -----------------------------------------------------------------------------------
func _finish(inv: PlayerInventory, player_id: int, uid: int, kind: String, result: Dictionary) -> Dictionary:
	if not reusable:
		inv.remove(uid)
	item_used.emit(player_id, kind, result)
	return result


func _consume_armed(player_id: int, kind: String) -> bool:
	var armed: Dictionary = _armed.get(player_id, {})
	if not armed.has(kind):
		return false
	armed.erase(kind)
	protection_used.emit(player_id, kind)
	return true


func _claim_key(player_id: int, room_label: String) -> String:
	return "%d|%s" % [player_id, room_label]


func _fail(reason: String, kind := "") -> Dictionary:
	return {"ok": false, "reason": reason, "kind": kind, "uid": 0, "title": "", "text": REASONS.get(reason, reason), "data": {}}
