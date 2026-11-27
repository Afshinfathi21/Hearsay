class_name BotBidder
extends RefCounted
## Chooses a bot's bid. Bots only know what a human would: their own points, their own acid,
## the capacity and the round penalty. They never see other players' bids or points.

const PERSONALITIES: Array[String] = ["cautious", "gambler", "adaptive", "aggressive"]


static func choose_bid(personality: String, points: int, acid: int, capacity: int, penalty: int, rng: RandomNumberGenerator) -> int:
	if points <= 0:
		return 0
	var danger := float(acid) / float(maxi(capacity, 1))
	var broke := points < int(1.5 * penalty)
	var bid := 0
	match personality:
		"cautious":
			bid = int(points * rng.randf_range(0.05, 0.3))
		"gambler":
			bid = rng.randi_range(0, points)
		"aggressive":
			bid = int(points * rng.randf_range(0.35, 0.8))
		_:  # adaptive
			var high := 0.55 if (danger > 0.55 or broke) else 0.25
			bid = int(points * rng.randf_range(0.05, high))
			if danger > 0.55:
				bid += penalty
	return clampi(bid, 0, points)
