class_name IdleRules
extends RefCounted
## Idle (AFK) reward rules. Pure functions on ints; numbers from data/economy.json ("idle")
## via EconomyData. Golden fixture: data/fixtures/idle.json.
##
## Income per hour grows with stages cleared. Rewards accrue per currency with a sub-unit
## carry (remainder in "currency-ms") so claiming often loses nothing; gear drops once per
## gear_every_ms of idle time, tracked by a separate gear timer.

const HOUR_MS := 3600000


## Income per hour after `cleared` stages: base + per_10_stages * cleared / 10 (integer division),
## for each currency in base_per_hour (in that order).
static func per_hour(cleared: int) -> Dictionary:
	var out := {}
	var c := maxi(cleared, 0)
	for k in EconomyData.IDLE_BASE:
		out[k] = int(EconomyData.IDLE_BASE[k]) + int(EconomyData.IDLE_PER_10_STAGES.get(k, 0)) * c / 10
	return out


## Idle time that counts: now - last_claim_at, capped at cap_ms. 0 if the clock went backwards
## (the caller then restarts the timer at `now`).
static func elapsed(now_ms: int, last_claim_at: int) -> int:
	if now_ms < last_claim_at:
		return 0
	return mini(now_ms - last_claim_at, EconomyData.IDLE_CAP_MS)


## Rewards for `elapsed_ms` of idle time:
##   total_k = per_hour_k * elapsed_ms + carry_k;  amount_k = total_k / 3600000;  carry_k' = total_k % 3600000
##   gear: g = gear_ms + elapsed_ms;  gear_count = g / gear_every_ms;  gear_ms' = g - gear_count * gear_every_ms
## Returns {reward: {currency: amount > 0..., gear_count?}, carry: {currency: n}, gear_ms}.
static func accrue(elapsed_ms: int, rates: Dictionary, carry: Dictionary, gear_ms: int) -> Dictionary:
	var new_carry := {}
	var reward := {}
	for k in rates:
		var total: int = int(rates[k]) * elapsed_ms + int(carry.get(k, 0))
		var n: int = total / HOUR_MS
		new_carry[k] = total % HOUR_MS
		if n > 0:
			reward[k] = n
	var g: int = gear_ms + elapsed_ms
	var gear_count: int = g / EconomyData.IDLE_GEAR_EVERY_MS
	g -= gear_count * EconomyData.IDLE_GEAR_EVERY_MS
	if gear_count > 0:
		reward["gear_count"] = gear_count
	return {"reward": reward, "carry": new_carry, "gear_ms": g}


## Price in gems of the next quick claim after `used` today, or -1 when none are left.
static func quick_claim_cost(used: int) -> int:
	var costs := EconomyData.QUICK_CLAIM_COSTS
	return costs[used] if used >= 0 and used < costs.size() else -1


## Quick claims left today after `used`.
static func quick_claims_left(used: int) -> int:
	return maxi(0, EconomyData.QUICK_CLAIM_COSTS.size() - used)


## A quick claim's currencies: per_hour_k * quick_claim_ms / 3600000 (no carry), plus gear from
## the gear timer advanced by quick_claim_ms. Returns {reward, gear_count, gear_ms}.
static func quick_reward(rates: Dictionary, gear_ms: int) -> Dictionary:
	var reward := {}
	for k in rates:
		var n: int = int(rates[k]) * EconomyData.QUICK_CLAIM_MS / HOUR_MS
		if n > 0:
			reward[k] = n
	var g: int = gear_ms + EconomyData.QUICK_CLAIM_MS
	var count := 0
	while g >= EconomyData.IDLE_GEAR_EVERY_MS:
		g -= EconomyData.IDLE_GEAR_EVERY_MS
		count += 1
	return {"reward": reward, "gear_count": count, "gear_ms": g}
