extends Node
## The player's money and the fish market.
##
## Every change to the balance goes through earn() or spend() with a reason,
## so a ledger, taxes or a bank can hook in later without touching callers.
## Fish prices drift over time and fall when the player floods the market,
## then recover.

signal balance_changed(balance: int)
signal transaction(amount: int, reason: String)
signal fish_prices_changed

const STARTING_BALANCE := 250
## How far fish prices can drift from their base price, either way.
const PRICE_DRIFT := 0.25
## Each fish sold knocks this fraction off that species' price...
const SALE_IMPACT := 0.03
## ...and prices recover this fraction of the way back each minute.
const RECOVERY_PER_MIN := 0.2

var balance := 0
## Fish id -> price multiplier (1.0 = base price).
var _fish_factor: Dictionary = {}
var _drift_target: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for def in ItemLibrary.items_in(ItemDef.Category.FISH):
		_fish_factor[def.id] = 1.0
		_drift_target[def.id] = 1.0
	var timer := Timer.new()
	timer.wait_time = 60.0
	timer.autostart = true
	timer.timeout.connect(_tick_market)
	add_child(timer)


func reset(amount := STARTING_BALANCE) -> void:
	balance = amount
	balance_changed.emit(balance)


func can_afford(amount: int) -> bool:
	return balance >= amount


func earn(amount: int, reason: String) -> void:
	if amount <= 0:
		return
	balance += amount
	transaction.emit(amount, reason)
	balance_changed.emit(balance)


## Takes money if the player has it. Returns false (and changes nothing) if not.
func spend(amount: int, reason: String) -> bool:
	if amount < 0 or balance < amount:
		return false
	balance -= amount
	transaction.emit(-amount, reason)
	balance_changed.emit(balance)
	return true


## What the market pays for one of this fish right now.
func fish_price(id: StringName) -> int:
	return maxi(1, roundi(ItemLibrary.base_price(id) * _fish_factor.get(id, 1.0)))


## How the price compares with normal: -1 low, 0 normal, 1 high.
func fish_trend(id: StringName) -> int:
	var f: float = _fish_factor.get(id, 1.0)
	return -1 if f < 0.92 else (1 if f > 1.08 else 0)


## Sells `count` of a fish from the inventory. Returns the money earned.
func sell_fish(id: StringName, count: int) -> int:
	var total := 0
	for i in count:
		if not Inventory.remove(id):
			break
		total += fish_price(id)
		_fish_factor[id] = maxf(_fish_factor.get(id, 1.0) - SALE_IMPACT, 1.0 - PRICE_DRIFT * 2.0)
	if total > 0:
		earn(total, "Sold %s" % ItemLibrary.name_of(id))
		fish_prices_changed.emit()
	return total


func to_dict() -> Dictionary:
	return {"balance": balance, "fish_factor": _fish_factor.duplicate()}


func from_dict(d: Dictionary) -> void:
	reset(int(d.get("balance", STARTING_BALANCE)))
	for id in d.get("fish_factor", {}):
		_fish_factor[StringName(id)] = float(d["fish_factor"][id])


func _tick_market() -> void:
	for id in _fish_factor:
		if _rng.randf() < 0.25:
			_drift_target[id] = 1.0 + _rng.randf_range(-PRICE_DRIFT, PRICE_DRIFT)
		_fish_factor[id] = lerpf(_fish_factor[id], _drift_target[id], RECOVERY_PER_MIN)
	fish_prices_changed.emit()
