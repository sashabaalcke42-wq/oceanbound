extends Node3D
## A fuel pump on a dock. Fills the player's boat if it is moored nearby,
## as far as their money allows.

const PRICE_PER_LITRE := 2
const REACH := 18.0


func _ready() -> void:
	BuildKit.box(self, null, Vector3(0, 0.6, 0), Vector3(0.45, 1.2, 0.35), Color(0.75, 0.15, 0.12))
	BuildKit.box(self, null, Vector3(0, 1.3, 0), Vector3(0.5, 0.2, 0.4), Color(0.9, 0.9, 0.85))
	BuildKit.sign_text(self, "FUEL  $%d/L" % PRICE_PER_LITRE, Vector3(0, 1.75, 0), 40)
	var i := BuildKit.interaction(self, "Pump", "Fill up your boat", Vector3(0, 0.8, 0), Vector3(1.6, 2.0, 1.6))
	i.interacted.connect(func(_by): refuel())


## Returns the litres added.
func refuel() -> float:
	var boat = _nearby_boat()
	if boat == null:
		EventBus.notify.emit("Bring your boat alongside to fill it up.")
		return 0.0
	var room: float = boat.stats["fuel_capacity"] - boat.fuel_l
	if room < 0.1:
		EventBus.notify.emit("The tank is already full.")
		return 0.0
	var litres := minf(room, floorf(float(Economy.balance) / PRICE_PER_LITRE))
	if litres < 1.0:
		EventBus.notify.emit("You can't afford any fuel.")
		return 0.0
	var cost := ceili(litres * PRICE_PER_LITRE)
	Economy.spend(cost, "Fuel")
	boat.fuel_l += litres
	EventBus.notify.emit("Added %.1f L of fuel for $%d." % [litres, cost])
	return litres


func _nearby_boat() -> Node:
	for b in get_tree().get_nodes_in_group(&"player_boat"):
		if (b as Node3D).global_position.distance_to(global_position) <= REACH:
			return b
	return null
