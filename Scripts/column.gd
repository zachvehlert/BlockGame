extends CSGBox3D
## Interactive column that drops into the ground when the player interacts with it,
## waits at the bottom, then accelerates back up to launch the player into the air.
## Taller columns rise faster and launch higher. The scene root is a CSGBox3D so
## you can duplicate and resize columns freely without needing editable children.

# How fast the column moves downward when activated
@export var drop_speed: float = 5.0
# Controls how quickly the column accelerates on the way back up.
# Scaled by sqrt(size.y) so taller columns rise faster than shorter ones.
@export var rise_acceleration: float = 3.0
# Scales the velocity applied to the player when the column reaches the top.
# Higher = bigger launch.
@export var launch_multiplier: float = 1.0
# Delay between the player interacting and the drop starting
@export var drop_delay: float = 0.0
# How long the column stays at the bottom before rising
@export var bottom_time: float = 1.0

# IDLE -> DROP_DELAY -> DROPPING -> WAITING -> RISING -> IDLE
enum State { IDLE, DROP_DELAY, DROPPING, WAITING, RISING }

@onready var _drop_delay_timer: Timer = $DropDelay
@onready var _bottom_timer: Timer = $BottomTime
@onready var _audio: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var _snd_activate: AudioStream = _audio.stream.get_list_stream(0)
@onready var _snd_drop: AudioStream = _audio.stream.get_list_stream(1)
@onready var _snd_land: AudioStream = _audio.stream.get_list_stream(2)

var player: CharacterBody3D = null
var player_on_column: bool = false
var state: State = State.IDLE
var origin_y: float     # the column's starting Y, so it knows where to return to
var drop_target_y: float # how far down to drop (origin_y - size.y)
var rise_speed: float    # current upward speed, increases each frame during RISING
var _connector: Node = null # child connector that can hold the column down with power

func _ready() -> void:
	origin_y = position.y
	# Deferred so the CSGBox3D size is fully resolved before we read it
	_create_interact_area.call_deferred()
	_drop_delay_timer.one_shot = true
	_drop_delay_timer.wait_time = max(drop_delay, 0.001)
	_drop_delay_timer.timeout.connect(_on_drop_delay_timeout)
	_bottom_timer.one_shot = true
	_bottom_timer.wait_time = max(bottom_time, 0.001)
	_bottom_timer.timeout.connect(_on_bottom_timeout)
	# Find a child connector if one exists
	for child in get_children():
		if child.has_method("get_neighbors"):
			_connector = child
			break

## Spawns an Area3D with a collision shape sitting on top of the column.
## This detects when the player is standing on/near the column so we know
## whether to listen for their interact signal.
func _create_interact_area() -> void:
	var shape := BoxShape3D.new()
	# Match the column's footprint, fixed height of 2 units
	shape.size = Vector3(size.x, 2.0, size.z)

	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	# Place it on top of the box: half the box height gets us to the top,
	# plus half the shape height so it sits above rather than clipping in
	collision_shape.position.y = size.y / 2.0 + shape.size.y / 2.0
	

	var area := Area3D.new()
	area.add_child(collision_shape)
	area.body_entered.connect(_on_area_3d_body_entered)
	area.body_exited.connect(_on_area_3d_body_exited)
	add_child(area)

# When the player steps into the area, start listening for their interact signal
func _on_area_3d_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		player = body
		player.interact.connect(_on_player_interact)
		player_on_column = true

# When the player leaves, stop listening so other columns can respond instead
func _on_area_3d_body_exited(body: Node3D) -> void:
	if body == player:
		player.interact.disconnect(_on_player_interact)
		player_on_column = false
		player = null

# Player pressed interact while in our area — start the drop
func _play_sound(stream: AudioStream) -> void:
	_audio.stream = stream
	_audio.play()

func _on_player_interact() -> void:
	if state != State.IDLE:
		return
	_play_sound(_snd_activate)
	# Drop by the full height of the column so it sinks flush with the ground
	drop_target_y = origin_y - size.y + 0.1
	if drop_delay > 0.0:
		state = State.DROP_DELAY
		_drop_delay_timer.start()
	else:
		_play_sound(_snd_drop)
		state = State.DROPPING

func _process(delta: float) -> void:
	match state:
		State.DROPPING:
			# Move down at a constant speed
			position.y = move_toward(position.y, drop_target_y, drop_speed * delta)
			if is_equal_approx(position.y, drop_target_y):
				_play_sound(_snd_land)
				state = State.WAITING
				rise_speed = 0.0
				_bottom_timer.start()

		State.WAITING:
			# Stay down indefinitely while a child connector is powered
			if _connector and _connector.powered:
				_bottom_timer.start()

		State.RISING:
			# Accelerate upward — sqrt(size.y) makes taller columns rise
			# faster overall while keeping small columns from being too snappy
			rise_speed += rise_acceleration * sqrt(size.y) * delta

			# Move the column up and track how far it moved this frame
			var prev_y := position.y
			position.y = move_toward(position.y, origin_y, rise_speed * delta)
			var column_move := position.y - prev_y

			# Carry the player along so they don't clip through
			if player_on_column and player:
				player.global_position.y += column_move

			# Column reached the top — launch the player and go back to idle
			if is_equal_approx(position.y, origin_y):
				_audio.stop()
				if player_on_column and player:
					player.velocity.y = rise_speed * launch_multiplier
				state = State.IDLE

func _on_drop_delay_timeout() -> void:
	_play_sound(_snd_drop)
	state = State.DROPPING

func _on_bottom_timeout() -> void:
	if state == State.WAITING:
		_play_sound(_snd_drop)
		state = State.RISING
