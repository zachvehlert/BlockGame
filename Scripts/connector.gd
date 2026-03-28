class_name Connector
extends Node3D

signal power_changed(is_powered: bool)

@export var is_power_source: bool = false

@onready var power_line: MeshInstance3D = $PowerLine
@onready var interact_area: Area3D = $InteractArea
@onready var power_col: Area3D = $PowerCol

var _powered_material: Material = preload("res://Resources/Materials/powerstrip.tres")
var _unpowered_material: Material = preload("res://Resources/Materials/powerstrip_unpowered.tres")

var powered: bool = false:
	set(value):
		if powered == value:
			return
		powered = value
		_update_visual()
		power_changed.emit(powered)
		if powered:
			_propagate_power()
		else:
			_propagate_depower()

var _is_rotating: bool = false

func _ready() -> void:
	power_col.area_entered.connect(_on_power_col_overlap)
	power_col.area_exited.connect(_on_power_col_disconnect)
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)
	powered = is_power_source
	_update_visual()

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		body.rotate_pressed.connect(_on_rotate)

func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		body.rotate_pressed.disconnect(_on_rotate)

func _on_rotate() -> void:
	if _is_rotating:
		return

	_is_rotating = true
	var was_powered := powered
	if was_powered and not is_power_source:
		powered = false

	# Animate rotation over 0.2 seconds
	var tween := create_tween()
	tween.tween_property(self, "rotation:y", rotation.y - deg_to_rad(90), 0.2)
	await tween.finished

	await get_tree().physics_frame
	if _can_reach_source():
		powered = true
	elif was_powered:
		_propagate_depower()

	_is_rotating = false

func _update_visual() -> void:
	if power_line:
		power_line.material_override = _powered_material if powered else _unpowered_material

func get_neighbors() -> Array[Node]:
	var neighbors: Array[Node] = []
	for area in power_col.get_overlapping_areas():
		var connector := _get_connector(area)
		if connector and connector != self and connector not in neighbors:
			neighbors.append(connector)
	return neighbors

func _get_connector(area: Area3D) -> Node:
	var parent := area.get_parent()
	if parent and parent.has_method("get_neighbors"):
		return parent
	return null

func _on_power_col_overlap(_area: Area3D) -> void:
	if powered:
		_propagate_power()
	else:
		for neighbor in get_neighbors():
			if neighbor.powered:
				powered = true
				return

func _on_power_col_disconnect(_area: Area3D) -> void:
	if not powered or is_power_source:
		return
	if not _can_reach_source():
		powered = false

func _propagate_power() -> void:
	for neighbor in get_neighbors():
		if not neighbor.powered:
			neighbor.powered = true

func _propagate_depower() -> void:
	for neighbor in get_neighbors():
		if neighbor.powered and not neighbor.is_power_source:
			if not neighbor._can_reach_source():
				neighbor.powered = false

func _can_reach_source() -> bool:
	var visited: Array[Node] = [self]
	var queue: Array[Node] = [self]
	while queue.size() > 0:
		var current: Node = queue.pop_front()
		if current.is_power_source:
			return true
		for neighbor in current.get_neighbors():
			if neighbor not in visited:
				visited.append(neighbor)
				queue.append(neighbor)
	return false
