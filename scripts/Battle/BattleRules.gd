extends RefCounted

const TURN_READY_DELAY := 3.0
const RECORD_DURATION := 3.0
const DEFENSE_PHRASE_DELAY := 1.0
const MAX_SEQUENCE_INPUTS := 6
const PERFECT_WINDOW := 0.05
const GOOD_WINDOW := 0.12
const MISS_WINDOW := 0.3
const DAMAGE_ON_MISS := 10
const STARTING_HEALTH := 100

const RESULT_COLORS := {
	"PERFECT": Color(0.42, 0.95, 0.82),
	"GOOD": Color(0.96, 0.82, 0.31),
	"MISS": Color(0.95, 0.36, 0.27),
	"WRONG": Color(0.95, 0.25, 0.2),
	"OMISSION": Color(0.65, 0.22, 0.24),
}


static func judge(delta: float) -> String:
	var absolute_delta := absf(delta)
	if absolute_delta <= PERFECT_WINDOW:
		return "PERFECT"
	if absolute_delta <= GOOD_WINDOW:
		return "GOOD"
	return "MISS"
