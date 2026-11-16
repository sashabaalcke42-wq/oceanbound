class_name Interactable
extends Area3D
## Anything the player can use with the interact key: a boat, a shop counter,
## the job board. Add one as a child, give it a shape and a prompt, and
## connect `interacted`.

const LAYER := 1 << 3

signal interacted(by: Node)

@export var prompt := "Use"
@export var enabled := true


func _init() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true


func interact(by: Node) -> void:
	if enabled:
		interacted.emit(by)
