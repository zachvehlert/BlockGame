extends CharacterBody3D

signal interact
signal rotate_pressed
signal jumped

@export_category("Controller Parameters")
@export var SPEED = 5.0
@export var AIR_SPEED = 1.0
@export var JUMP_VELOCITY = 6
@export var MOUSE_SENSITIVITY = 0.002

@export_category("Animation")
@export var BLEND_SPEED = 20 # effects the speed at which animations in my animation blend tree (inside my state machine) blend between eachother

# Camera Stuff
@onready var camera_origin: Node3D = $CameraOrigin
@onready var camera: Camera3D = $CameraOrigin/SpringArm3D/Camera3D

# Animation stuff
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var state_machine: AnimationNodeStateMachinePlayback = anim_tree["parameters/playback"]

# Particals
@onready var dust_scene: PackedScene = preload("res://Scenes/DustParticles.tscn")

# Player Sounds
@onready var jump_sounds: AudioStreamPlayer = $JumpSounds

var max_height := -INF
var _superjump_fov_active := false
var _default_fov: float

func emit_dust() -> void:
	var dust := dust_scene.instantiate()
	dust.position = Vector3(0, -0.7126223, 0)
	add_child(dust)
	dust.emitting = true
	dust.finished.connect(dust.queue_free)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	state_machine.travel("grounded")
	_default_fov = camera.fov

func _unhandled_input(event: InputEvent) -> void:
	# Camera stuff from claude. Don't reinvent the wheel here because who cares?
	if event is InputEventMouseMotion:
		camera_origin.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_origin.rotate_object_local(Vector3.RIGHT, -event.relative.y * MOUSE_SENSITIVITY)
		camera_origin.rotation.x = clampf(camera_origin.rotation.x, -PI / 3, PI / 3)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		interact.emit()
	if Input.is_action_just_pressed("rotate"):
		rotate_pressed.emit()

	# Variable Gravity because jumping up should feel nice and falling down should feel heavy
	if not is_on_floor():
		if velocity.y >= 0:
			velocity += get_gravity() * delta
		else:
			velocity += get_gravity() * 3 * delta

	# Variable jump height. Short inputs make short jumps and vice versa. Feels great
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
			jumped.emit()
			state_machine.travel("jump")
			emit_dust()
			jump_sounds.play()
	elif velocity.y > 0.0:
		if Input.is_action_just_released("jump"):
			velocity.y *= 0.5

	if is_on_floor() and state_machine.get_current_node() in ["airborne", "jump"]:
		state_machine.start("land")
		emit_dust()
		if _superjump_fov_active:
			_superjump_fov_active = false
			var tween := create_tween()
			tween.tween_property(camera, "fov", _default_fov, 0.3).set_ease(Tween.EASE_OUT)

	# Fell off an edge (not jumping) — go straight to airborne
	if not is_on_floor() and state_machine.get_current_node() == "grounded":
		state_machine.travel("airborne")

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

	if global_position.y > max_height:
		max_height = global_position.y
		print("New max height: ", max_height)

	# Blend toward walk (1) or idle (-1)
	var target_blend := 1.0 if direction else -1.0
	var current_blend: float = anim_tree["parameters/grounded/blend_position"]
	anim_tree["parameters/grounded/blend_position"] = move_toward(current_blend, target_blend, BLEND_SPEED * delta)

func start_superjump_fov() -> void:
	_superjump_fov_active = true
	var tween := create_tween()
	tween.tween_property(camera, "fov", 95.0, 0.15).set_ease(Tween.EASE_OUT)
