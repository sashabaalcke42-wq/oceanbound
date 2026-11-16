extends CanvasLayer
## On-screen information: interaction prompts, notifications, and boat
## instruments while at the helm. Listens to EventBus only.

const NOTIFY_SECONDS := 5.0

var _prompt: Label
var _notice: Label
var _instruments: Label
var _vessel: Node
var _notice_time := 0.0


func _ready() -> void:
	_prompt = _make_label(Control.PRESET_CENTER_BOTTOM, 22)
	_prompt.position.y -= 120
	_notice = _make_label(Control.PRESET_CENTER_TOP, 20)
	_notice.position.y += 40
	_instruments = _make_label(Control.PRESET_BOTTOM_LEFT, 20)
	_instruments.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_instruments.position += Vector2(24, -24)
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
			"running" if running else "off", roundi(throttle * 100.0), knots, fuel]
	else:
		_instruments.text = ""


func _on_notify(text: String) -> void:
	_notice.text = text
	_notice_time = NOTIFY_SECONDS


func _make_label(preset: Control.LayoutPreset, font_size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override(&"outline_size", 6)
	l.custom_minimum_size = Vector2(900, 0) if preset != Control.PRESET_BOTTOM_LEFT else Vector2(300, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	if preset == Control.PRESET_BOTTOM_LEFT:
		l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return l
