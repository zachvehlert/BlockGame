extends CharacterBody3D

signal interact
signal rotate_pressed

@export_category("Controller Parameters")
@export var SPEED = 5.0
@export var AIR_SPEED = 1.0
@export var JUMP_VELOCITY = 6
@export var MOUSE_SENSITIVITY = 0.002

@export_category("Restage")
@export var RESTAGE_DURATION: float = 1.0
@export var RESTAGE_SPEED: float = 2.0

@export_category("Animation")
@export var BLEND_SPEED = 20 # effects the speed at which animations in my animation blend tree (inside my state machine) blend between eachother

# Camera Stuff
@onready var camera_origin: Node3D = $CameraOrigin

# Animation stuff
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var state_machine: AnimationNodeStateMachinePlayback = anim_tree["parameters/playback"]

# Mesh (for restage animation snapshots)
@onready var mesh: MeshInstance3D = $MeshInstance3D

# Particals
@onready var dust_scene: PackedScene = preload("res://Scenes/DustParticles.tscn")

# Player Sounds
@onready var jump_sounds: AudioStreamPlayer = $JumpSounds

# Restage state
var frame_history: Array[Dictionary] = []
var is_restaging: bool = false
var restage_timer: float = 0.0
var is_restage_recording: bool = false
var _dust_emitted_this_frame: bool = false
var _restage_start_anim_state: StringName
var _restage_start_blend_position: float

func emit_dust() -> void:
	var dust := dust_scene.instantiate()
	dust.position = Vector3(0, -0.7126223, 0)
	add_child(dust)
	dust.emitting = true
	dust.finished.connect(dust.queue_free)
	_dust_emitted_this_frame = true

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	state_machine.travel("grounded")

func _unhandled_input(event: InputEvent) -> void:
	# Camera stuff from claude. Don't reinvent the wheel here because who cares?
	if event is InputEventMouseMotion:
		camera_origin.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_origin.rotate_object_local(Vector3.RIGHT, -event.relative.y * MOUSE_SENSITIVITY)
		camera_origin.rotation.x = clampf(camera_origin.rotation.x, -PI / 3, PI / 3)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _restage_activate() -> void:
	is_restage_recording = true
	restage_timer = RESTAGE_DURATION
	frame_history.clear()
	_restage_start_anim_state = state_machine.get_current_node()
	_restage_start_blend_position = anim_tree["parameters/grounded/blend_position"]

func _restage_record(delta: float) -> void:
	restage_timer -= delta
	frame_history.append({
		"position": global_position,
		"mesh_position": mesh.position,
		"mesh_scale": mesh.scale,
		"dust": _dust_emitted_this_frame,
	})
	_dust_emitted_this_frame = false
	if restage_timer <= 0.0:
		is_restage_recording = false
		is_restaging = true
		anim_tree.active = false

func _restage_playback() -> void:
	var pops_per_frame := int(RESTAGE_SPEED)
	var snapshot: Dictionary
	for i in pops_per_frame:
		if frame_history.size() > 0:
			snapshot = frame_history.pop_back()
			global_position = snapshot.position
	if snapshot:
		mesh.position = snapshot.mesh_position
		mesh.scale = snapshot.mesh_scale
		if snapshot.dust:
			emit_dust()
	if frame_history.size() == 0:
		is_restaging = false
		velocity = Vector3.ZERO
		anim_tree.active = true
		state_machine.start(_restage_start_anim_state, true)
		anim_tree["parameters/grounded/blend_position"] = _restage_start_blend_position

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		interact.emit()
	if Input.is_action_just_pressed("rotate"):
		rotate_pressed.emit()

	if Input.is_action_just_pressed("restage") and not is_restaging and not is_restage_recording:
		_restage_activate()

	if is_restaging:
		_restage_playback()
		return

	# Variable Gravity because jumping up should feel nice and falling down should feel heavy
	if not is_on_floor():
		if velocity.y >= 0:
			velocity += get_gravity() * delta
		else:
			velocity += get_gravity() * 2 * delta

	# Variable jump height. Short inputs make short jumps and vice versa. Feels great
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
			state_machine.travel("jump")
			emit_dust()
			jump_sounds.play()
	elif velocity.y > 0.0:
		if Input.is_action_just_released("jump"):
			velocity.y *= 0.5

	if is_on_floor() and state_machine.get_current_node() in ["airborne", "jump"]:
		state_machine.start("land")
		emit_dust()

	# More camera and direction stuff. I really don't understand this but who cares?
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var cam_basis := camera_origin.global_transform.basis
	var forward := -cam_basis.z
	forward.y = 0
	forward = forward.normalized()
	var right := cam_basis.x
	right.y = 0
	right = right.normalized()
	var direction := (forward * -input_dir.y + right * input_dir.x).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

	# Blend toward walk (1) or idle (-1)
	var target_blend := 1.0 if direction else -1.0
	var current_blend: float = anim_tree["parameters/grounded/blend_position"]
	anim_tree["parameters/grounded/blend_position"] = move_toward(current_blend, target_blend, BLEND_SPEED * delta)

	if is_restage_recording:
		_restage_record(delta)
