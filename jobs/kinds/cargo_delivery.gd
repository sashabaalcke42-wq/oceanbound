extends JobKind
## Pick up a parcel at one place and drop it at another before the deadline.
## Pays by distance, plus a little for urgency.

const CARGO := &"cargo_parcel"

const SENDERS := ["The bakery", "A fisherman", "The harbourmaster", "Mrs Achterberg", "The post office", "A holiday maker"]
const GOODS := ["a box of spare parts", "the mail bag", "a crate of tomatoes", "a cooler of bait", "a toolbox", "a parcel of books"]


func generate(rng: RandomNumberGenerator) -> Job:
	var places := destinations()
	if places.size() < 2:
		return null
	places.shuffle()
	var from: StringName = places[0]
	var to: StringName = places[1]
	var dist := Locations.position_of(from).distance_to(Locations.position_of(to))
	var j := Job.new()
	j.kind = &"cargo_delivery"
	var goods: String = GOODS[rng.randi() % GOODS.size()]
	j.title = "Deliver %s" % goods
	j.description = "%s needs %s taken from %s to %s." % [
		SENDERS[rng.randi() % SENDERS.size()], goods, Locations.name_of(from), Locations.name_of(to)]
	j.time_limit = roundf(dist / 4.0 + 150.0)
	j.reward = int(snappedf(35.0 + dist * 0.11, 5.0))
	j.requirements = "Any boat"
	j.objectives = [
		{"text": "Collect the cargo at %s" % Locations.name_of(from), "location": from,
			"give": {"id": CARGO, "count": 1}},
		{"text": "Deliver it to %s" % Locations.name_of(to), "location": to,
			"take": {"id": CARGO, "count": 1}},
	]
	return j
