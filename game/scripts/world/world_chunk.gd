class_name WorldChunk
extends Node3D
## 单个地形区块：地形网格 + 碰撞 + 植被（docs/technical-design.md §5.1）。
##
## 区块只负责「自己这一格」的几何。高度永远来自 TerrainField，
## 边界顶点与相邻区块取到同一坐标上的同一个值，所以接缝天然吻合。
##
## 植被用**全局格点**撒点：候选格（cell）按世界坐标编号，
## 一个格只归属一个区块；每块用 (世界种子, 区块坐标) 派生随机数，
## 于是同一块无论重建多少次、从哪个方向走进来，内容都完全一样。

## 满配植被的区块：树 + 枯木 + 岩石 + 灌木 + 地被。
const BAND_FULL := 0
## 远景区块：只保留乔木，省掉地面细节。
const BAND_SPARSE := 1

const TREE_CELL := 4.2
const GRASS_CELL := 2.2
const MAX_SLOPE := 0.45
const PINE_VARIANTS := 5
const BIRCH_VARIANTS := 2
const BIRCH_RATIO := 0.22
const SNAG_RATIO := 0.07
const DEADWOOD_RATIO := 0.012
const ROCK_DENSITY := 0.16
const SHRUB_DENSITY := 0.3
const GROUND_COVER_DENSITY := 0.5
const CAMP_CLEAR_RADIUS := 16.0
const PATH_START := Vector2(0.0, 6.0)
const PATH_END := Vector2(1.5, -26.0)
const PATH_HALF_WIDTH := 3.6

enum State { EMPTY, TERRAIN, READY }

var coord: Vector2i = Vector2i.ZERO
var chunk_size: float = 64.0
var resolution: int = 32
var state: State = State.EMPTY
var vegetation_band: int = -1
## 碰撞是分帧建的：排队标记，避免玩家跨区块时一帧内建好几块碰撞。
var collision_pending: bool = false

var _world: ChunkedWorld
var _field: TerrainField
var _padded: int = 0
var _heights: PackedFloat32Array
var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _vegetation: Node3D
var _no_vegetation: bool = false


func setup(world_ref: ChunkedWorld, chunk_coord: Vector2i, size: float, res: int) -> void:
	_world = world_ref
	_field = world_ref.field
	coord = chunk_coord
	chunk_size = size
	resolution = res
	name = "Chunk_%d_%d" % [coord.x, coord.y]
	position = Vector3(origin().x, 0.0, origin().y)


## 区块左下角的世界坐标（XZ）。
func origin() -> Vector2:
	var half := _world.world_size * 0.5
	return Vector2(coord.x * chunk_size - half, coord.y * chunk_size - half)


func center() -> Vector3:
	var org := origin()
	return Vector3(org.x + chunk_size * 0.5, 0.0, org.y + chunk_size * 0.5)


## 保存系统标记过的区块状态（例如整块清空植被）。
func apply_override(state_data: Dictionary) -> void:
	_no_vegetation = bool(state_data.get("no_vegetation", false))
	if _no_vegetation:
		clear_vegetation()
		vegetation_band = -1


# ------------------------------------------------------------------ 地形

## 采样并生成地形网格。重复调用无副作用。
func build_terrain() -> void:
	if state != State.EMPTY:
		return

	var n := resolution
	var cell := chunk_size / float(n)
	var org := origin()
	# 多采一圈边界顶点，用来算法线：边界法线由区块内外共同的采样点决定，
	# 相邻区块在同一世界坐标上算出同一个法线，光照接缝也不会露。
	_padded = n + 3
	_heights = PackedFloat32Array()
	_heights.resize(_padded * _padded)

	for pz in _padded:
		for px in _padded:
			var wx := org.x + (float(px) - 1.0) * cell
			var wz := org.y + (float(pz) - 1.0) * cell
			_heights[pz * _padded + px] = _field.height_at(wx, wz)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()

	vertices.resize((n + 1) * (n + 1))
	normals.resize((n + 1) * (n + 1))
	uvs.resize((n + 1) * (n + 1))
	colors.resize((n + 1) * (n + 1))

	for j in n + 1:
		for i in n + 1:
			var h := _height_at(i, j)
			var idx := j * (n + 1) + i
			vertices[idx] = Vector3(float(i) * cell, h, float(j) * cell)

			var hl := _height_at(i - 1, j)
			var hr := _height_at(i + 1, j)
			var hd := _height_at(i, j - 1)
			var hu := _height_at(i, j + 1)
			var normal := Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
			normals[idx] = normal

			uvs[idx] = Vector2(
				(org.x + float(i) * cell) / _field.world_size + 0.5,
				(org.y + float(j) * cell) / _field.world_size + 0.5
			)
			colors[idx] = _field.color_at(
				org.x + float(i) * cell,
				org.y + float(j) * cell,
				h,
				1.0 - normal.y
			)

	var indices := PackedInt32Array()
	indices.resize(n * n * 6)
	var write := 0
	for j in n:
		for i in n:
			var i0 := j * (n + 1) + i
			var i1 := i0 + 1
			var i2 := i0 + (n + 1)
			var i3 := i2 + 1
			# 绕向必须是 (v00, v10, v01) 这一侧朝上。写反了地形会被背面剔除。
			indices[write] = i0
			indices[write + 1] = i1
			indices[write + 2] = i2
			indices[write + 3] = i1
			indices[write + 4] = i3
			indices[write + 5] = i2
			write += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "TerrainMesh"
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _world.terrain_material()
	add_child(_mesh_instance)

	state = State.TERRAIN


func _height_at(i: int, j: int) -> float:
	var px := clampi(i + 1, 0, _padded - 1)
	var pz := clampi(j + 1, 0, _padded - 1)
	return _heights[pz * _padded + px]


## 碰撞只给玩家附近的区块建：远处的山只是背景，不需要参与物理。
func ensure_collision(enabled: bool) -> void:
	if enabled and _body == null:
		_build_collision()
	elif not enabled and _body != null:
		_body.queue_free()
		_body = null


func has_collision() -> bool:
	return _body != null


func _build_collision() -> void:
	var n := resolution
	var cell := chunk_size / float(n)
	var faces := PackedVector3Array()
	faces.resize(n * n * 6)
	var write := 0

	for j in n:
		for i in n:
			var v00 := Vector3(float(i) * cell, _height_at(i, j), float(j) * cell)
			var v10 := Vector3(float(i + 1) * cell, _height_at(i + 1, j), float(j) * cell)
			var v01 := Vector3(float(i) * cell, _height_at(i, j + 1), float(j + 1) * cell)
			var v11 := Vector3(float(i + 1) * cell, _height_at(i + 1, j + 1), float(j + 1) * cell)
			# 碰撞面的绕向必须与渲染网格相反，否则角色会从地面直接穿过去。
			faces[write] = v00
			faces[write + 1] = v10
			faces[write + 2] = v01
			faces[write + 3] = v10
			faces[write + 4] = v11
			faces[write + 5] = v01
			write += 6

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)

	_body = StaticBody3D.new()
	_body.name = "TerrainBody"
	_body.collision_layer = 1
	_body.collision_mask = 0

	var collision := CollisionShape3D.new()
	collision.shape = shape
	_body.add_child(collision)
	add_child(_body)


# ------------------------------------------------------------------ 植被

func clear_vegetation() -> void:
	if _vegetation != null:
		_vegetation.queue_free()
		_vegetation = null
	vegetation_band = -1


## 重建整块植被。band 只影响「摆出去多少」，不影响随机序列，
## 因此同一块在远景（BAND_SPARSE）和近景（BAND_FULL）看到的树是同一批。
func build_vegetation(band: int) -> void:
	clear_vegetation()
	if _no_vegetation:
		return
	vegetation_band = band

	_vegetation = Node3D.new()
	_vegetation.name = "Vegetation"
	add_child(_vegetation)

	var rng := RandomNumberGenerator.new()
	rng.seed = _world.vegetation_seed(coord)
	var org := origin()

	var pine_lists: Array = []
	for i in PINE_VARIANTS:
		pine_lists.append([])
	var birch_lists: Array = []
	for i in BIRCH_VARIANTS:
		birch_lists.append([])
	var snags: Array = []
	var logs: Array = []
	var stumps: Array = []
	var rocks: Array = []
	var shrubs: Array = []

	var x0 := int(floor(org.x / TREE_CELL))
	var z0 := int(floor(org.y / TREE_CELL))
	var x1 := int(floor((org.x + chunk_size) / TREE_CELL))
	var z1 := int(floor((org.y + chunk_size) / TREE_CELL))

	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var base := Vector2((float(ix) + 0.5) * TREE_CELL, (float(iz) + 0.5) * TREE_CELL)
			var pos := base + Vector2(
				rng.randf_range(-TREE_CELL * 0.48, TREE_CELL * 0.48),
				rng.randf_range(-TREE_CELL * 0.48, TREE_CELL * 0.48)
			)

			if not _field.is_inside(pos.x, pos.y):
				continue
			if _is_excluded(pos):
				continue
			if _field.slope_at(pos.x, pos.y) > MAX_SLOPE:
				continue

			var density := _field.vegetation_density(pos.x, pos.y, 0.72)
			if rng.randf() <= density:
				var roll := rng.randf()
				if roll < BIRCH_RATIO:
					var bv := rng.randi_range(0, birch_lists.size() - 1)
					birch_lists[bv].append(_make_transform(rng, pos, org, 0.8, 1.25))
				elif roll < BIRCH_RATIO + SNAG_RATIO:
					snags.append(_make_transform(rng, pos, org, 0.75, 1.1))
				else:
					var pv := rng.randi_range(0, pine_lists.size() - 1)
					pine_lists[pv].append(_make_transform(rng, pos, org, 0.8, 1.35))
			elif rng.randf() < DEADWOOD_RATIO:
				if rng.randf() < 0.6:
					logs.append(_make_transform(rng, pos, org, 0.75, 1.15))
				else:
					stumps.append(_make_transform(rng, pos, org, 0.8, 1.2))
			elif rng.randf() < ROCK_DENSITY:
				rocks.append(_make_transform(rng, pos, org, 0.55, 1.5))
			elif rng.randf() < SHRUB_DENSITY:
				shrubs.append(_make_transform(rng, pos, org, 0.7, 1.4))

	for i in pine_lists.size():
		_add_instances("Pines%02d" % (i + 1), _world.mesh_for("pine_%d" % i),
			pine_lists[i], band == BAND_FULL, true)
	for i in birch_lists.size():
		_add_instances("Birches%02d" % (i + 1), _world.mesh_for("birch_%d" % i),
			birch_lists[i], band == BAND_FULL, true)
	_add_instances("Snags", _world.mesh_for("snag"), snags, band == BAND_FULL, true)

	# 远景只保留乔木：地被与碎石在这个距离上本来就看不出来，却要多付绘制代价
	if band == BAND_FULL:
		_add_instances("FallenLogs", _world.mesh_for("log"), logs, false, false)
		_add_instances("Stumps", _world.mesh_for("stump"), stumps, false, false)
		_add_instances("Rocks", _world.mesh_for("rock"), rocks, false, false)
		_add_instances("Shrubs", _world.mesh_for("shrub"), shrubs, false, false)
		_build_ground_cover(rng, org)


func _build_ground_cover(rng: RandomNumberGenerator, org: Vector2) -> void:
	var placements: Array = []
	var x0 := int(floor(org.x / GRASS_CELL))
	var z0 := int(floor(org.y / GRASS_CELL))
	var x1 := int(floor((org.x + chunk_size) / GRASS_CELL))
	var z1 := int(floor((org.y + chunk_size) / GRASS_CELL))

	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var base := Vector2((float(ix) + 0.5) * GRASS_CELL, (float(iz) + 0.5) * GRASS_CELL)
			var pos := base + Vector2(
				rng.randf_range(-GRASS_CELL * 0.48, GRASS_CELL * 0.48),
				rng.randf_range(-GRASS_CELL * 0.48, GRASS_CELL * 0.48)
			)
			if not _field.is_inside(pos.x, pos.y):
				continue
			if _is_grass_excluded(pos):
				continue
			if _field.slope_at(pos.x, pos.y) > MAX_SLOPE:
				continue
			if rng.randf() > GROUND_COVER_DENSITY:
				continue
			placements.append(_make_transform(rng, pos, org, 0.6, 1.15, 0.03))

	_add_instances("GrassTufts", _world.mesh_for("grass"), placements, false, false)


func _add_instances(node_name: String, mesh: Mesh, placements: Array,
		cast_shadow: bool, sway: bool) -> void:
	if placements.is_empty() or mesh == null:
		return

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = placements.size()

	for i in placements.size():
		var placement: Dictionary = placements[i]
		multimesh.set_instance_transform(i, placement["transform"])
		multimesh.set_instance_color(i, placement["color"])
		# 红色分量是风摆相位（归一化到 0~1），让每棵树各摆各的
		multimesh.set_instance_custom_data(i, Color(placement["phase"], 0.0, 0.0, 1.0))

	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = _world.swaying_material() if sway else _world.painted_material()
	if not cast_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vegetation.add_child(instance)


func _make_transform(rng: RandomNumberGenerator, position: Vector2, org: Vector2,
		min_scale: float, max_scale: float, sink: float = 0.15) -> Dictionary:
	var height := _field.height_at(position.x, position.y)
	var s := rng.randf_range(min_scale, max_scale)
	var rotation := rng.randf_range(0.0, TAU)

	var basis := Basis.from_euler(Vector3(0.0, rotation, 0.0)).scaled(Vector3.ONE * s)
	return {
		"transform": Transform3D(basis, Vector3(position.x - org.x, height - sink * s, position.y - org.y)),
		"color": Color(1, 1, 1).lerp(Color(0.82, 0.88, 0.78), rng.randf() * 0.5),
		"phase": fposmod(position.x * 0.31 + position.y * 0.27, TAU),
	}


## 营地、溪流、主路径、世界边缘之外不种树。
func _is_excluded(position: Vector2) -> bool:
	if position.distance_to(Vector2.ZERO) < CAMP_CLEAR_RADIUS:
		return true
	if absf(position.x - _field.creek_center_x) < 4.2:
		return true
	if _distance_to_path(position) < PATH_HALF_WIDTH:
		return true
	return false


func _is_grass_excluded(position: Vector2) -> bool:
	if absf(position.x - _field.creek_center_x) < 3.0:
		return true
	if _distance_to_path(position) < PATH_HALF_WIDTH * 0.8:
		return true
	# 营地内保留野草：被踩实的空地边缘反而需要草来过渡
	return false


func _distance_to_path(position: Vector2) -> float:
	var segment := PATH_END - PATH_START
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return position.distance_to(PATH_START)
	var t := clampf((position - PATH_START).dot(segment) / length_squared, 0.0, 1.0)
	return position.distance_to(PATH_START + segment * t)


## 供测试与调试：把这块的内容压成一个字符串，用来比较两次生成是否一致。
func signature() -> String:
	if _vegetation == null:
		return "empty"
	var parts: Array[String] = []
	for child in _vegetation.get_children():
		var instance := child as MultiMeshInstance3D
		if instance == null or instance.multimesh == null:
			continue
		var count := instance.multimesh.instance_count
		if count <= 0:
			continue
		var first := instance.multimesh.get_instance_transform(0).origin
		parts.append("%s:%d:%.3f,%.3f,%.3f" % [
			instance.name, count, first.x, first.y, first.z,
		])
	return "|".join(parts)


func instance_count() -> int:
	if _vegetation == null:
		return 0
	var total := 0
	for child in _vegetation.get_children():
		var instance := child as MultiMeshInstance3D
		if instance != null and instance.multimesh != null:
			total += instance.multimesh.instance_count
	return total
