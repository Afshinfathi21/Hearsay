class_name NotificationFeed
extends VBoxContainer
## The stack of notifications in the bottom-right corner (newest at the bottom).
## Presentation only: the host sends events, this decides how they look.
##
## event = { "type": String, ... } with these types:
##   "points_deducted"  amount            red, "-2"
##   "lockdown"         rounds            red, critical (frame flash)
##   "exit_payment"     amount            amber, "-3"
##   "random_reward"    amount            amber, "+2"
##   "random_penalty"   amount            red, "-2"
##   "protected"                          white
##   "eliminated"       player, reason    red, critical (frame flash)
##   "info"             title             white
## Every event may also set "title" and "detail" to replace the default texts.

## Emitted for critical events so the screen frame can flash this colour.
signal critical_event(colour: Color)

@export var card_scene: PackedScene
@export var max_cards := 4
@export var normal_seconds := 4.0
@export var critical_seconds := 6.5


func push(event: Dictionary) -> void:
	assert(card_scene != null, "NotificationFeed: assign Card Scene in the Inspector.")
	var amount: int = event.get("amount", 0)
	var detail := str(event.get("detail", ""))
	var title := str(event.get("title", ""))
	var delta := ""
	var colour := UIStyle.TEXT
	var critical := false

	match str(event.get("type", "info")):
		"points_deducted":
			title = title if title != "" else "POINTS DEDUCTED"
			delta = "-%d" % amount
			colour = UIStyle.RED
		"lockdown":
			var rounds: int = event.get("rounds", 1)
			title = title if title != "" else "LOCKDOWN"
			if detail == "":
				detail = "YOU CANNOT LEAVE FOR %d ROUND%s" % [rounds, "" if rounds == 1 else "S"]
			colour = UIStyle.RED
			critical = true
		"exit_payment":
			title = title if title != "" else "EXIT PAYMENT"
			if detail == "":
				detail = "ADDITIONAL PAYMENT TO LEAVE"
			delta = "-%d" % amount
			colour = UIStyle.AMBER
		"random_reward":
			title = title if title != "" else "REWARD"
			delta = "+%d" % amount
			colour = UIStyle.AMBER
		"random_penalty":
			title = title if title != "" else "PENALTY"
			delta = "-%d" % amount
			colour = UIStyle.RED
		"protected":
			title = title if title != "" else "PROTECTED"
			if detail == "":
				detail = "GROUP PENALTY AVOIDED"
		"eliminated":
			var who := str(event.get("player", "")).to_upper()
			title = title if title != "" else ("%s ELIMINATED" % who if who != "" else "ELIMINATED")
			if detail == "":
				detail = str(event.get("reason", ""))
			colour = UIStyle.RED
			critical = true
		_:
			title = title if title != "" else "NOTICE"

	# Too many on screen: remove the oldest at once.
	while get_child_count() >= max_cards:
		var oldest := get_child(0) as NotificationCard
		remove_child(oldest)
		oldest.dismiss()

	var card := card_scene.instantiate() as NotificationCard
	add_child(card)
	card.setup(title, detail, delta, colour, critical_seconds if critical else normal_seconds, critical)
	if critical:
		critical_event.emit(colour)
