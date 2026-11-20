extends JobKind
## A restaurant or shop wants a number of one kind of fish, brought to the
## town quay. Pays better than the market, but you have to catch the right fish.

const BUYERS := ["The Anchor Inn", "Harbour Fish and Chips", "The Lighthouse Cafe", "A private chef"]


func generate(rng: RandomNumberGenerator) -> Job:
	if not Locations.has(&"town_quay"):
		return null
	var fish := ItemLibrary.items_in(ItemDef.Category.FISH)
	if fish.is_empty():
		return null
	# Favour common fish, so most orders are doable with a basic boat.
	var def: ItemDef = fish[rng.randi() % fish.size()]
	if def.min_depth > 20.0 and rng.randf() < 0.6:
		def = fish[rng.randi() % fish.size()]
	var count := clampi(roundi(60.0 / def.base_price) + rng.randi_range(0, 2), 1, 12)
	var buyer: String = BUYERS[rng.randi() % BUYERS.size()]
	var j := Job.new()
	j.kind = &"fish_order"
	j.title = "%s for %s" % [def.count_text(count), buyer]
	j.description = "%s wants %s, brought to the town quay. %s" % [buyer, def.count_text(count), def.description]
	j.reward = int(snappedf(def.base_price * count * 1.5 + 15.0, 5.0))
	j.time_limit = 0.0
	j.requirements = "Fishing rod. %s live in water %d to %d m deep." % [
		def.display_name, roundi(def.min_depth), roundi(minf(def.max_depth, 99.0))]
	j.objectives = [
		{"text": "Bring %s to the town quay" % def.count_text(count),
			"location": &"town_quay", "take": {"id": def.id, "count": count}},
	]
	return j
