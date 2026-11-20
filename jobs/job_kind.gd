class_name JobKind
extends RefCounted
## Makes jobs of one kind. Add a kind by adding a script in jobs/kinds/ that
## extends this, and listing it in Jobs.KIND_SCRIPTS.

## Return a new Job, or null if this kind cannot make one right now (for
## example, not enough destinations exist yet).
func generate(_rng: RandomNumberGenerator) -> Job:
	return null


## Destinations a job may use: every registered location except the player's
## own dock.
static func destinations() -> Array:
	return Locations.ids().filter(func(id): return id != &"home_dock")
