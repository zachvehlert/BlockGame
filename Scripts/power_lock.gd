extends Node3D

signal power_changed(is_powered: bool)

@onready var power_area: Area3D = $PowerArea
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var state_machine: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback")

var powered: bool = false
var _tracked_connectors: Array[Connector] = []

func _ready() -> void:
	power_area.area_entered.connect(_on_area_entered)
	power_area.area_exited.connect(_on_area_exited)

func _on_area_entered(area: Area3D) -> void:
	var connector := area.get_parent() as Connector
	if connector and connector not in _tracked_connectors:
		_tracked_connectors.append(connector)
		connector.power_changed.connect(_on_connector_power_changed)
	_check_power()

func _on_area_exited(area: Area3D) -> void:
	var connector := area.get_parent() as Connector
	if connector:
		_tracked_connectors.erase(connector)
		connector.power_changed.disconnect(_on_connector_power_changed)
	_check_power()

func _on_connector_power_changed(_is_powered: bool) -> void:
	_check_power()

func _check_power() -> void:
	var was_powered := powered
	powered = false
	for connector in _tracked_connectors:
		if connector.powered:
			powered = true
			break
	if powered != was_powered:
		if powered:
			state_machine.travel("power_on")
		else:
			state_machine.travel("power_off")
		power_changed.emit(powered)
