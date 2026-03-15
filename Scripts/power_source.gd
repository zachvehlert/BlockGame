extends Node3D

@onready var anim_tree: AnimationTree = $AnimationTree
@onready var state_machine: AnimationNodeStateMachinePlayback = anim_tree["parameters/playback"]
@onready var area: Area3D = $Area3D

var is_power_source: bool = false
var _endpoints: Array[Area3D] = []

var powered: bool = false:
	set(value):
		if powered == value:
			return
		powered = value
		is_power_source = powered
		if powered:
			state_machine.travel("power_on")
			_propagate_power()
		else:
			state_machine.travel("power_off")
			_propagate_depower()

func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	for child in get_children():
		if child is Area3D and child != area:
			_endpoints.append(child)
			child.area_entered.connect(_on_endpoint_overlap)
			child.area_exited.connect(_on_endpoint_disconnect)

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		body.interact.connect(_on_interact)

func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		body.interact.disconnect(_on_interact)

func _on_interact() -> void:
	powered = !powered

func get_neighbors() -> Array[Node]:
	var neighbors: Array[Node] = []
	for endpoint in _endpoints:
		for a in endpoint.get_overlapping_areas():
			var connector := _get_connector(a)
			if connector and connector != self and connector not in neighbors:
				neighbors.append(connector)
	return neighbors

func _get_connector(a: Area3D) -> Node:
	var parent := a.get_parent()
	if parent and parent.has_method("get_neighbors"):
		return parent
	return null

func _on_endpoint_overlap(_area: Area3D) -> void:
	if powered:
		_propagate_power()

func _on_endpoint_disconnect(_area: Area3D) -> void:
	pass

func _propagate_power() -> void:
	for neighbor in get_neighbors():
		if not neighbor.powered:
			neighbor.powered = true

func _propagate_depower() -> void:
	for neighbor in get_neighbors():
		if neighbor.powered and not neighbor.is_power_source:
			if not neighbor._can_reach_source():
				neighbor.powered = false
