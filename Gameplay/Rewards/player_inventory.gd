class_name PlayerInventory
extends RefCounted
## One player's reward items. Plain data and rules, no UI and no nodes, so the host can own it and a
## network layer can later replicate snapshot(). Items are not stackable: one item per slot.

signal changed

var capacity := 4

var _items: Array[Dictionary] = []       # {"uid": int, "kind": String}
var _next_uid := 1


func count() -> int:
	return _items.size()


func is_full() -> bool:
	return _items.size() >= capacity


## Adds an item. Returns its uid, or 0 when the kind is unknown or the inventory is full.
func add(kind: String) -> int:
	if not RewardCatalog.exists(kind) or is_full():
		return 0
	var uid := _next_uid
	_next_uid += 1
	_items.append({"uid": uid, "kind": kind})
	changed.emit()
	return uid


func remove(uid: int) -> bool:
	for i in _items.size():
		if int(_items[i]["uid"]) == uid:
			_items.remove_at(i)
			changed.emit()
			return true
	return false


## {} when there is no such item.
func get_item(uid: int) -> Dictionary:
	for item in _items:
		if int(item["uid"]) == uid:
			return item
	return {}


## uid of the item in a slot (0-based), or 0 when the slot is empty.
func slot_uid(slot: int) -> int:
	return int(_items[slot]["uid"]) if slot >= 0 and slot < _items.size() else 0


## What the HUD shows: [{slot, uid, kind, name, category, text}], filled slots only.
func snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in _items.size():
		var def := RewardCatalog.info(_items[i]["kind"])
		out.append({"slot": i, "uid": _items[i]["uid"], "kind": _items[i]["kind"], "name": def["name"],
			"category": def["category"], "text": def["text"]})
	return out
