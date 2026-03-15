extends Node3D

@export var power_locks: Array[NodePath] = []

@onready var anim_tree: AnimationTree = $AnimationTree
@onready var state_machine: AnimationNodeStateMachinePlayback = anim_tree["parameters/playback"]
@onready var door_collision: CollisionShape3D = $Door/StaticBody3D/CollisionShape3D

var _locks: Array[Node] = []
var is_open: bool = false

func _ready() -> void:
	for path in power_locks:
		var lock := get_node(path)
		_locks.append(lock)
		lock.power_changed.connect(_on_lock_power_changed)

func _on_lock_power_changed(_is_powered: bool) -> void:
	var all_powered := true
	for lock in _locks:
		if not lock.powered:
			all_powered = false
			break
	if all_powered and not is_open:
		is_open = true
		state_machine.travel("door_open")
		door_collision.disabled = true
	elif not all_powered and is_open:
		is_open = false
		state_machine.travel("door_close")
		door_collision.disabled = false
