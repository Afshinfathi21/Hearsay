class_name BalanceScaleConfig
extends Resource
## Every number that shapes a Balance Scale match, in one place so it can be tuned
## after playtests (see docs/balance_scale_design.md, decision D4).

@export var start_points := 100
@export var capacity := 100
## Points every loser pays in round 1; grows by `penalty_step` each round.
@export var penalty_start := 10
@export var penalty_step := 3
## Acid removed from every living pot at the end of each round (0 = acid never drains).
@export var acid_drain_per_round := 0
@export var bid_seconds := 20.0

@export_group("Pacing (seconds)")
@export var intro_seconds := 2.5
@export var penalty_seconds := 2.5
@export var reveal_seconds := 4.0
@export var winner_seconds := 3.0
@export var acid_seconds := 3.5
@export var elimination_seconds := 3.0
@export var next_round_seconds := 1.5


## Penalty paid by losers in round `round_number` (round 1 is the first round).
func penalty_for_round(round_number: int) -> int:
	return penalty_start + penalty_step * maxi(round_number - 1, 0)
