extends SceneTree
## A seated player stays in first person, and nothing on screen reveals another player's bid
## before the reveal.
## Run with: godot --headless --path . --script res://tests/seated_view_test.gd

var passed := 0
var failed := 0
const SECRET_BIDS := {2: 83, 3: 61, 4: 47}   # distinctive values the three bots will bid


func _init() -> void:
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Every piece of text that exists anywhere in the running level (HUD, bid panel, board,
## table screens, wall displays, name tags).
func _all_text(node: Node, out: PackedStringArray) -> void:
	if node is Label: out.append((node as Label).text)
	elif node is Label3D: out.append((node as Label3D).text)
	elif node is Button: out.append((node as Button).text)
	elif node is RichTextLabel: out.append((node as RichTextLabel).get_parsed_text())
	if node is ScreenDisplay: out.append((node as ScreenDisplay).get_text())
	for c in node.get_children():
		_all_text(c, out)


func _shows_number(text: String, number: int) -> bool:
	var re := RegEx.new()
	re.compile("(^|[^0-9])%d([^0-9]|$)" % number)
	return re.search(text) != null


func _run() -> void:
	var level := (load("res://Levels/Balance Scale/auction_chamber.tscn") as PackedScene).instantiate()
	var presenter := level.get_node("Presenter") as AuctionPresenter
	var cfg := BalanceScaleConfig.new()
	cfg.intro_seconds = 0.1
	cfg.penalty_seconds = 0.1
	cfg.reveal_seconds = 4.0
	cfg.winner_seconds = 0.3
	cfg.acid_seconds = 0.3
	presenter.config = cfg
	root.add_child(level)
	var player := level.get_node("Player")
	var seating := level.get_node("Seating") as SeatingController
	await _frames(30)

	# --- third person before sitting (the level default allows it) ---
	player._first_person = false
	await _frames(40)
	_check(player.model.visible, "before sitting the player can be in third person")

	Input.action_press("interact")
	for i in 3:
		await process_frame
	Input.action_release("interact")
	await _frames(20)
	var auction := presenter.auction
	_check(player.seated, "the player sits down")
	_check(player._first_person and not player.model.visible, "sitting switches the camera to first person (own body hidden)")

	var toggle := InputEventAction.new()
	toggle.action = "toggle_camera"
	toggle.pressed = true
	Input.parse_input_event(toggle)
	await _frames(40)
	_check(player._first_person and player._cam_dist == 0.0 and not player.model.visible, "the camera toggle does nothing while seated")

	# --- secrecy during bidding ---
	for i in 600:
		if auction.state == AuctionMatch.S.BIDDING:
			break
		await physics_frame
	_check(auction.state == AuctionMatch.S.BIDDING, "bidding started")
	for id in SECRET_BIDS:
		auction.submit_bid(id, SECRET_BIDS[id])
	await _frames(30)
	var texts := PackedStringArray()
	_all_text(level, texts)
	var joined := "\n".join(texts)
	for id in SECRET_BIDS:
		_check(not _shows_number(joined, SECRET_BIDS[id]), "bot %d's secret bid (%d) is nowhere on screen while bidding" % [id, SECRET_BIDS[id]])
	_check(joined.contains("LOCKED"), "the screens do show that the bots have locked in")
	_check(not _shows_number(str(auction.public_view()), 83), "the public match view contains no bid")

	# human locks in, then the reveal
	player_bid(presenter, 5)
	for i in 600:
		if auction.state == AuctionMatch.S.BID_REVEAL:
			break
		await physics_frame
	await create_timer(2.2).timeout
	texts.clear()
	_all_text(level, texts)
	joined = "\n".join(texts)
	for id in SECRET_BIDS:
		_check(_shows_number(joined, SECRET_BIDS[id]), "after the reveal bot %d's bid (%d) is shown" % [id, SECRET_BIDS[id]])

	# --- standing up gives the old camera back ---
	seating.end_game()
	await process_frame                # start the key press at the beginning of a frame, like a real key
	Input.action_press("interact")
	for i in 3:
		await process_frame
	Input.action_release("interact")
	await _frames(10)
	_check(not player.seated and not player._first_person, "after the game the player stands and gets third person back")
	level.queue_free()
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func player_bid(presenter: AuctionPresenter, amount: int) -> void:
	presenter._on_human_bid(amount)


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)
