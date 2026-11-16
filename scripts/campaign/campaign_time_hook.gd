extends RefCounted
## Registerable time-system hook. A system that changes state over time registers one
## hook with the campaign facade. The defaults are deliberately conservative: a hook
## that does not override `aggregate_interval` forces detailed one-second stepping.
##
## Context dictionary passed to the queries (read-only):
##   state    committed OutpostGameState at the current whole-tick boundary
##   content  hash-verified definitions
##   accounts replay plan from the reference detailed tick:
##            [{path, kind ("base"|"battery"), key, ops PackedFloat64Array [debit, credit, ...]}]
##   deltas   {path: net change per tick} for those accounts
const NO_LIMIT := 9007199254740991

func id() -> String:
	return "unnamed"

func integration() -> String:
	## Reported in capabilities.time_integration: "aggregate" or "detailed_fallback".
	return "detailed_fallback"

func next_transition(_context: Dictionary) -> Dictionary:
	## Upper bound on whole ticks for which this system's behaviour cannot change.
	## Return NO_LIMIT when nothing is pending. Underestimate when unsure.
	return {"ticks": NO_LIMIT, "reason": ""}

func detailed_interval(_candidate: RefCounted, _ledger: RefCounted) -> Dictionary:
	## Runs inside every detailed tick, after crew progress and before diagnostics.
	## All balance changes must go through `_ledger`. The oracle always uses this path.
	return {"ok": true, "code": "ok", "reason": ""}

func aggregate_interval(_context: Dictionary) -> Dictionary:
	## Certify that this system's detailed effect over a stable interval is fully
	## described by the replay plan (or is nothing). Anything else must refuse.
	return {"ok": false, "reason": id() + ":no_aggregate_model"}

static func ticks_until_cross(value: float, delta: float, threshold: float) -> int:
	## Whole ticks before a linear quantity reaches `threshold` from its current side.
	var gap := value - threshold
	if delta == 0.0 or gap == 0.0: return NO_LIMIT if delta == 0.0 else 0
	if (gap > 0.0) == (delta > 0.0): return NO_LIMIT
	var ticks := floorf(absf(gap) / absf(delta))
	return NO_LIMIT if ticks >= float(NO_LIMIT) else int(ticks)
