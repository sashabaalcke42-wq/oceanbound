extends CanvasLayer
## On-screen information: interaction prompts, notifications, and boat
## instruments while at the helm. Listens to EventBus only.

const NOTIFY_SECONDS := 5.0

var _prompt: Label
var _notice: Label
var _instruments: Label
var _activity: Label
var _money: Label
var _job: Label
var _water: Label
var _money_flash := 0.0
var _vessel: Node
var _notice_time := 0.0


func _ready() -> void:
	_prompt = _make_label(Control.PRESET_CENTER_BOTTOM, 22)
	_prompt.position.y -= 120
	_notice = _make_label(Control.PRESET_CENTER_BOTTOM, 20)
	_notice.position.y -= 190
	_instruments = _make_label(Control.PRESET_BOTTOM_LEFT, 20)
	_instruments.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_instruments.position += Vector2(24, -24)
	_activity = _make_label(Control.PRESET_CENTER_BOTTOM, 22)
	_activity.position.y -= 250
	_activity.modulate = Color(0.75, 0.95, 1.0)
	_money = _make_label(Control.PRESET_TOP_RIGHT, 26)
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money.position += Vector2(-24, 18)
	_water = _make_label(Control.PRESET_CENTER_BOTTOM, 22)
	_water.position.y -= 290
	_job = _make_label(Control.PRESET_TOP_RIGHT, 18)
	_job.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_job.position += Vector2(-24, 60)
	EventBus.activity_changed.connect(func(t: String): _activity.text = t)
	Economy.balance_changed.connect(func(_b): _update_money())
	Economy.transaction.connect(func(amount: int, _r: String): _flash_money(amount))
	_update_money()
	EventBus.interaction_prompt_changed.connect(func(t: String): _prompt.text = t)
	EventBus.notify.connect(_on_notify)
	EventBus.player_boarded.connect(func(v: Node): _vessel = v)
	EventBus.player_disembarked.connect(func(_v: Node): _vessel = null)


func _process(delta: float) -> void:
	_notice_time -= delta
	_notice.modulate.a = clampf(_notice_time, 0.0, 1.0)
	if is_instance_valid(_vessel):
		var knots: float = _vessel.get(&"speed_ms") * 1.944
		var throttle: float = _vessel.get(&"throttle")
		var fuel: float = _vessel.get(&"fuel_l")
		var running: bool = _vessel.get(&"engine_running")
		_instruments.text = "Engine  %s\nThrottle  %+d%%\nSpeed  %.1f kn\nFuel  %.1f L" % [
			"%d rpm" % roundi(_vessel.get(&"rpm")) if running else "off", roundi(throttle * 100.0), knots, fuel]
		var wind: Vector3 = Waves.wind
		_instruments.text += "\nWind  %d kn from %s" % [roundi(wind.length() * 1.944), _compass(-wind)]
	else:
		_instruments.text = ""
	_update_water_warning()
	_update_job()
	if _money_flash > 0.0:
		_money_flash -= delta
		if _money_flash <= 0.0:
			_update_money()


## Water aboard whichever boat we are on, as a warning line.
func _update_water_warning() -> void:
	var boat: Node = _vessel
	if not is_instance_valid(boat):
		var p := get_tree().get_first_node_in_group(&"player")
		boat = p.call(&"current_boat") if p else null
	if is_instance_valid(boat) and boat.get(&"water_l") > 2.0:
		var frac: float = boat.call(&"water_fraction")
		_water.text = "Water aboard  %d L%s  (B to bail)" % [roundi(boat.get(&"water_l")), "  SWAMPED" if frac > 0.9 else ""]
		_water.modulate = Color(1, 0.55, 0.4) if frac > 0.4 else Color(0.7, 0.9, 1)
	else:
		_water.text = ""


static func _compass(v: Vector3) -> String:
	# Godot's -Z is north and +X east.
	var deg := fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0)
	return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(roundf(deg / 45.0)) % 8]


func _update_money() -> void:
	_money.text = "$%d" % Economy.balance


func _flash_money(amount: int) -> void:
	_money.text = "$%d  (%s$%d)" % [Economy.balance, "+" if amount > 0 else "-", absi(amount)]
	_money_flash = 3.0


func _update_job() -> void:
	var job := Jobs.active
	if job == null:
		_job.text = ""
		return
	var obj := job.current_objective()
	var text := "%s\n%s" % [job.title, job.status_text()]
	if not obj.is_empty():
		var target := Locations.position_of(obj["location"])
		var here := get_viewport().get_camera_3d()
		if here:
			var d := Vector2(target.x - here.global_position.x, target.z - here.global_position.z).length()
			text += "\n%d m away" % roundi(d)
	if job.time_limit > 0.0:
		var s := maxi(ceili(job.time_left), 0)
		text += "\nTime left %d:%02d" % [s / 60, s % 60]
	_job.text = text


func _on_notify(text: String) -> void:
	_notice.text = text
	_notice_time = NOTIFY_SECONDS


func _make_label(preset: Control.LayoutPreset, font_size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override(&"outline_size", 6)
	l.custom_minimum_size = Vector2(900, 0) if preset == Control.PRESET_CENTER_BOTTOM else Vector2(420, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	if preset == Control.PRESET_BOTTOM_LEFT:
		l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	elif preset == Control.PRESET_TOP_RIGHT:
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	else:
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	return l
