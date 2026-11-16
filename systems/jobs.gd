extends Node
## The job board and the player's active job.
##
## Job kinds live in jobs/kinds/ and only make Job objects; this service
## keeps the board stocked, tracks the one active job, hands over and takes
## items as objectives are reached, and pays out. The world tells it where the
## player is each frame with `check_arrival()`, so it never reaches into scenes.

signal board_changed
signal active_changed(job: Job)  # null when there is no active job
signal objective_advanced(job: Job)
signal job_finished(job: Job, success: bool)

const KIND_SCRIPTS: Array[Script] = [
	preload("res://jobs/kinds/cargo_delivery.gd"),
	preload("res://jobs/kinds/fish_order.gd"),
]
const BOARD_SIZE := 4
## A new job replaces the oldest one on the board this often (seconds).
const ROTATE_SECONDS := 180.0

var available: Array[Job] = []
var active: Job

var _kinds: Array[JobKind] = []
var _rng := RandomNumberGenerator.new()
var _next_id := 1
var _rotate_timer := 0.0
## Set once we have told the player they are short, until they leave.
var _nagged := false


func _ready() -> void:
	_rng.randomize()
	for s in KIND_SCRIPTS:
		_kinds.append(s.new())


func reset() -> void:
	if active:
		_drop_given_items(active)
	active = null
	available.clear()
	active_changed.emit(null)
	board_changed.emit()


## The board, topped up to BOARD_SIZE if the world has enough places for it.
func board() -> Array[Job]:
	_top_up()
	return available


func accept(job: Job) -> bool:
	if active != null or job.state != Job.State.AVAILABLE or not available.has(job):
		return false
	available.erase(job)
	job.state = Job.State.ACTIVE
	job.current = 0
	job.time_left = job.time_limit
	active = job
	_top_up()
	board_changed.emit()
	active_changed.emit(job)
	EventBus.notify.emit("Job accepted: %s. %s." % [job.title, job.status_text()])
	return true


func abandon() -> void:
	if active == null:
		return
	_fail("You gave up on the job.")


## Called by the world every physics frame. `settled` means the player is on
## foot or their boat is nearly stopped, so drive-bys do not count.
func check_arrival(where: Vector3, settled: bool) -> void:
	if active == null or not settled:
		return
	var obj := active.current_objective()
	if obj.is_empty() or not Locations.is_at(obj["location"], where):
		_nagged = false
		return
	var take: Dictionary = obj.get("take", {})
	if not take.is_empty():
		var have := Inventory.count(take["id"])
		if have < take["count"]:
			if not _nagged:
				_nagged = true
				var def := ItemLibrary.get_item(take["id"])
				var need: String = def.count_text(take["count"]) if def else "%d" % take["count"]
				EventBus.notify.emit("You need %s here, and have %d." % [need, have])
			return
		Inventory.remove(take["id"], take["count"])
	var give: Dictionary = obj.get("give", {})
	if not give.is_empty():
		Inventory.add(give["id"], give["count"])
	active.current += 1
	if active.current >= active.objectives.size():
		_complete()
	else:
		objective_advanced.emit(active)
		EventBus.notify.emit(active.status_text() + ".")


func _physics_process(delta: float) -> void:
	if active and active.time_limit > 0.0:
		active.time_left -= delta
		if active.time_left <= 0.0:
			_fail("Too late. The job was given to someone else.")
	_rotate_timer += delta
	if _rotate_timer >= ROTATE_SECONDS:
		_rotate_timer = 0.0
		if not available.is_empty():
			available.pop_front()
			_top_up()
			board_changed.emit()


func _complete() -> void:
	var job := active
	job.state = Job.State.DONE
	active = null
	Economy.earn(job.reward, "Job: %s" % job.title)
	EventBus.notify.emit("Job done: %s. You earned $%d." % [job.title, job.reward])
	job_finished.emit(job, true)
	active_changed.emit(null)


func _fail(reason: String) -> void:
	var job := active
	job.state = Job.State.FAILED
	_drop_given_items(job)
	active = null
	EventBus.notify.emit(reason)
	job_finished.emit(job, false)
	active_changed.emit(null)


## Items a job handed over (such as a parcel) go back when it ends unfinished.
func _drop_given_items(job: Job) -> void:
	for i in mini(job.current, job.objectives.size()):
		var give: Dictionary = job.objectives[i].get("give", {})
		if not give.is_empty():
			Inventory.remove(give["id"], mini(give["count"], Inventory.count(give["id"])))


func _top_up() -> void:
	var tries := 0
	while available.size() < BOARD_SIZE and tries < BOARD_SIZE * 4:
		tries += 1
		var job := _kinds[_rng.randi() % _kinds.size()].generate(_rng)
		if job == null:
			continue
		job.id = _next_id
		_next_id += 1
		available.append(job)


