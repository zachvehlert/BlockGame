@tool
class_name WearGenerator
extends CSGCombiner3D
## Generates random CSG subtraction chunks on child columns to create a
## worn-stone look. Attach this to a CSGCombiner3D that contains CSGBox3D
## column instances, then use the inspector buttons to generate or clear wear.

func _init() -> void:
	use_collision = true

## Chunks per unit of column height.
@export var chunks_per_unit: float = 2
## Minimum size of each wear chunk.
@export var chunk_size_min: Vector3 = Vector3(0.3, 0.3, 0.3)
## Maximum size of each wear chunk.
@export var chunk_size_max: Vector3 = Vector3(0.6, 0.8, 0.6)
## When true, no chunks are placed on the bottom (-Y) face.
@export var skip_bottom_face: bool = true
## When true, no chunks are placed on the top (+Y) face.
@export var skip_top_face: bool = true

@export_category("Actions")
@export_tool_button("Generate Wear", "Add") var generate_wear = _generate_wear
@export_tool_button("Clear Wear", "Remove") var clear_wear = _clear_wear
@export_tool_button("Export To Scene", "MoveUp") var export_columns = _export_to_scene
@export_tool_button("Import From Scene", "MoveDown") var import_columns = _import_from_scene


func _import_from_scene() -> void:
	var parent := get_parent()
	if not parent:
		push_warning("column_wear: No parent node to import columns from.")
		return
	var tree := get_tree()
	var scene_root: Node = tree.edited_scene_root if tree else null
	for child in parent.get_children().duplicate():
		if child is Column:
			var global_xform: Transform3D = child.global_transform
			parent.remove_child(child)
			add_child(child)
			child.global_transform = global_xform
			if scene_root:
				child.owner = scene_root
				for grandchild in child.get_children():
					grandchild.owner = scene_root


func _export_to_scene() -> void:
	var parent := get_parent()
	if not parent:
		push_warning("column_wear: No parent node to export columns to.")
		return
	var tree := get_tree()
	var scene_root: Node = tree.edited_scene_root if tree else null
	# Reparent each child column to become a sibling of the WearGenerator.
	for child in get_children().duplicate():
		var global_xform: Transform3D = child.global_transform
		remove_child(child)
		parent.add_child(child)
		child.global_transform = global_xform
		if scene_root:
			child.owner = scene_root
			# Re-own grandchildren (wear chunks, timers, etc.) so they persist.
			for grandchild in child.get_children():
				grandchild.owner = scene_root


func _clear_wear() -> void:
	for column in get_children():
		var to_remove: Array[Node] = []
		for child in column.get_children():
			if child.has_meta("wear_chunk"):
				to_remove.append(child)
		for child in to_remove:
			child.queue_free()


func _generate_wear() -> void:
	_clear_wear()

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Collect all CSGBox3D children (the columns).
	var columns: Array[CSGBox3D] = []
	for child in get_children():
		if child is CSGBox3D:
			columns.append(child as CSGBox3D)

	if columns.is_empty():
		push_warning("column_wear: No CSGBox3D children found to wear.")
		return

	var tree := get_tree()

	# Build the list of allowed faces based on skip settings.
	# Faces: +X(0) -X(1) +Y(2) -Y(3) +Z(4) -Z(5)
	var allowed_faces: Array[int] = [0, 1, 4, 5]
	if not skip_top_face:
		allowed_faces.append(2)
	if not skip_bottom_face:
		allowed_faces.append(3)

	for col_idx in columns.size():
		var column: CSGBox3D = columns[col_idx]
		var col_size: Vector3 = column.size
		var half := col_size * 0.5

		# Build edges as pairs of sign directions, e.g. (+X, +Z) means the
		# vertical edge where the +X and +Z faces meet. We only include
		# edges whose both faces are in the allowed set.
		var edges: Array = []
		# Vertical edges (run along Y): pairs of X and Z faces.
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				var face_x: int = 0 if sx == 1 else 1
				var face_z: int = 4 if sz == 1 else 5
				if face_x in allowed_faces and face_z in allowed_faces:
					edges.append({"x": sx, "z": sz, "axis": "y"})
		# Horizontal edges along X (top/bottom meeting Z faces).
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				var face_y: int = 2 if sy == 1 else 3
				var face_z: int = 4 if sz == 1 else 5
				if face_y in allowed_faces and face_z in allowed_faces:
					edges.append({"y": sy, "z": sz, "axis": "x"})
		# Horizontal edges along Z (top/bottom meeting X faces).
		for sy in [-1, 1]:
			for sx in [-1, 1]:
				var face_y: int = 2 if sy == 1 else 3
				var face_x: int = 0 if sx == 1 else 1
				if face_y in allowed_faces and face_x in allowed_faces:
					edges.append({"y": sy, "x": sx, "axis": "z"})

		if edges.is_empty():
			continue

		var chunk_count: int = maxi(1, roundi(col_size.y * chunks_per_unit))
		# Track placed chunks as {position, size} for overlap rejection.
		var placed: Array[Dictionary] = []
		var placed_count: int = 0

		for chunk_idx in chunk_count:
			var chunk_size := Vector3(
				rng.randf_range(chunk_size_min.x, chunk_size_max.x),
				rng.randf_range(chunk_size_min.y, chunk_size_max.y),
				rng.randf_range(chunk_size_min.z, chunk_size_max.z),
			)

			var local_pos := Vector3.ZERO
			var found_spot := false
			var max_attempts := 20

			for _attempt in max_attempts:
				# Pick a random edge and place the chunk along it.
				var edge: Dictionary = edges[rng.randi_range(0, edges.size() - 1)]
				local_pos = Vector3.ZERO

				match edge["axis"]:
					"y":
						local_pos.x = half.x * edge["x"]
						local_pos.z = half.z * edge["z"]
						local_pos.y = rng.randf_range(-half.y, half.y)
					"x":
						local_pos.y = half.y * edge["y"]
						local_pos.z = half.z * edge["z"]
						local_pos.x = rng.randf_range(-half.x, half.x)
					"z":
						local_pos.y = half.y * edge["y"]
						local_pos.x = half.x * edge["x"]
						local_pos.z = rng.randf_range(-half.z, half.z)

				# Check overlap with already-placed chunks using AABB intersection.
				var overlaps := false
				for p in placed:
					if _aabbs_overlap(local_pos, chunk_size, p["pos"], p["size"]):
						overlaps = true
						break

				if not overlaps:
					found_spot = true
					break

			if not found_spot:
				continue

			placed.append({"pos": local_pos, "size": chunk_size})

			# Random rotation for an organic look.
			var rot := Vector3(
				rng.randf_range(0.0, TAU),
				rng.randf_range(0.0, TAU),
				rng.randf_range(0.0, TAU),
			)

			var chunk := CSGBox3D.new()
			chunk.name = "WearChunk_%d_%d" % [col_idx, placed_count]
			chunk.operation = CSGShape3D.OPERATION_SUBTRACTION
			chunk.size = chunk_size
			chunk.position = local_pos
			chunk.rotation = rot

			chunk.set_meta("wear_chunk", true)
			column.add_child(chunk)
			if tree and tree.edited_scene_root:
				chunk.owner = tree.edited_scene_root
			placed_count += 1


## Returns true if two axis-aligned boxes overlap.
static func _aabbs_overlap(pos_a: Vector3, size_a: Vector3, pos_b: Vector3, size_b: Vector3) -> bool:
	var half_a := size_a * 0.5
	var half_b := size_b * 0.5
	return (absf(pos_a.x - pos_b.x) < half_a.x + half_b.x
		and absf(pos_a.y - pos_b.y) < half_a.y + half_b.y
		and absf(pos_a.z - pos_b.z) < half_a.z + half_b.z)
