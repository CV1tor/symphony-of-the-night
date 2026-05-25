extends RefCounted
class_name BattleRules

const TURN_READY_DELAY := 2.0
const RECORD_DURATION := 3.0
const MAX_SEQUENCE_INPUTS := 6
const PERFECT_WINDOW := 0.05
const GOOD_WINDOW := 0.12
const MISS_WINDOW := 0.15
const DAMAGE_ON_MISS := 10
const STARTING_HEALTH := 100


static func judge(delta: float) -> String:
	var absolute_delta := absf(delta)
	if absolute_delta <= PERFECT_WINDOW:
		return "PERFECT"
	if absolute_delta <= GOOD_WINDOW:
		return "GOOD"
	return "MISS"
