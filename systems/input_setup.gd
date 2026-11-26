extends Node
## Registers the game's input actions in code so they are easy to read and
## review in one place. Actions already defined in Project Settings are kept,
## which leaves room for a rebinding menu later.

const BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"interact": [KEY_E],
	"engine_toggle": [KEY_R],
	"throttle_zero": [KEY_X],
	"toggle_mouse": [KEY_ESCAPE],
	"fish": [KEY_F],
	"view_toggle": [KEY_V],
	"bail": [KEY_B],
	"map_toggle": [KEY_M],
}


func _enter_tree() -> void:
	for action: String in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: Key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
