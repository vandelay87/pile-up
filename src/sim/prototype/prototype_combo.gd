# PROTOTYPE, throwaway (Combo prototype #104): per-building combos on a chain timer, as decided
# in Combo rework #97. Each kill adds 1 and restarts the timer; a lapse breaks straight to x1.
# Numbers are placeholders for the look, not tuned. Gold still pays on v2's global combo.
class_name PrototypeCombo
extends RefCounted

const TIMER_SECONDS := 2.0
## Kills needed for each tier, from x2 up; the last tier is the cap.
const THRESHOLDS: Array[int] = [4, 10, 20]


static func timer_ticks() -> int:
	return roundi(TIMER_SECONDS * Simulation.TICKS_PER_SECOND)


static func tier(count: int) -> int:
	var reached := 1
	for i in THRESHOLDS.size():
		if count >= THRESHOLDS[i]:
			reached = i + 2
	return reached


static func cap() -> int:
	return THRESHOLDS.size() + 1


## Kills where this tier began (0 at x1).
static func floor_of(tier_now: int) -> int:
	return 0 if tier_now <= 1 else THRESHOLDS[tier_now - 2]


## Kills for the next tier, or -1 at the cap.
static func next_of(tier_now: int) -> int:
	return -1 if tier_now >= cap() else THRESHOLDS[tier_now - 1]


## 0..1 progress from this tier's start to the next; 1 at the cap.
static func progress(count: int) -> float:
	var t := tier(count)
	var next := next_of(t)
	if next < 0:
		return 1.0
	var start := floor_of(t)
	return float(count - start) / float(next - start)


static func on_kill(building: Buildings.Building) -> void:
	building.combo_count += 1
	building.combo_ticks = timer_ticks()
	if building.combo_count > building.combo_best:
		building.combo_best = building.combo_count


static func tick(building: Buildings.Building) -> void:
	if building.combo_ticks <= 0:
		return
	building.combo_ticks -= 1
	if building.combo_ticks == 0:
		building.combo_count = 0
