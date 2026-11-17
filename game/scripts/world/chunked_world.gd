class_name ChunkedWorld
extends Node3D
## 1 km × 1 km 分块世界（docs/technical-design.md §5.1 / docs/open-world-design.md §1）。
##
## 职责：
##  - 持有全局高度场 TerrainField，作为 terrain 分组的高度提供者
##  - 以玩家所在区块为锚点，按距离流式加载 / 卸载地形区块
##  - 给近处区块加碰撞、给中距离区块加植被，远处只保留地形
##  - 把世界种子与「被改动过的区块」写进存档
##
## 内存与耗时都是有界的：同时存在的区块数只由半径决定，与玩家走多远无关。

signal chunk_loaded(coord: Vector2i)
signal chunk_unloaded(coord: Vector2i)
signal world_ready()

const TERRAIN_GROUP := &"terrain"
const WORLD_GROUP := &"chunked_world"

@export var world_seed: int = TerrainField.DEFAULT_SEED
@export var world_size: float = 1024.0
@export var chunk_size: float = 64.0
## 每个区块的网格分段数。32 段 / 64 m = 2 m 一格。
@export var terrain_resolution: int = 32
@export_range(0, 8) var terrain_radius_chunks: int = 7
@export_range(0, 8) var collision_radius_chunks: int = 2
@export_range(0, 8) var vegetation_radius_chunks: int = 2
@export_range(0, 8) var sparse_vegetation_radius_chunks: int = 5
## 每帧给区块生成的时间预算（毫秒），避免一次性加载时掉帧。
@export var build_budget_ms: float = 3.0
## 启动时同步生成几圈区块，保证出生点附近立刻可站。
@export var initial_radius_chunks: int = 3

var field: TerrainField

var _grid: int = 16
var _chunks: Dictionary = {}          # Vector2i -> WorldChunk
var _queue: Array[Vector2i] = []
var _veg_queue: Array = []
var _collision_queue: Array[Vector2i] = []
var _anchor_chunk: Vector2i = Vector2i(-9999, -9999)
var _refresh_timer: float = 0.0
var _player: Node3D

var _terrain_mat: StandardMaterial3D
var _painted_mat: StandardMaterial3D
var _sway_mat: ShaderMaterial
var _meshes: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(TERRAIN_GROUP)
	add_to_group(WORLD_GROUP)

	field = TerrainField.new(world_seed, world_size)
	# 读档前的默认种子就是场景里的种子；读档后由存档覆盖
	if GameState.world_seed > 0 and GameState.world_seed != field.world_seed:
		field.set_seed(int(GameState.world_seed))

	_grid = maxi(1, int(round(world_size / chunk_size)))


func _ready() -> void:
	_terrain_mat = StandardMaterial3D.new()
	_terrain_mat.vertex_color_use_as_albedo = true
	_terrain_mat.roughness = 0.95
	_terrain_mat.metallic = 0.0
	_terrain_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	_painted_mat = PropKit.painted_material()
	_sway_mat = PropKit.swaying_material()

	GameState.world_seed = field.world_seed

	_build_initial_chunks()
	EventBus.game_loaded.connect(_on_game_loaded)

	GameLog.info("分块世界就绪", {
		"size": world_size,
		"chunk_size": chunk_size,
		"grid": "%dx%d" % [_grid, _grid],
		"seed": field.world_seed,
	})

	world_ready.emit()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D

	var anchor := Vector3.ZERO
	if _player != null:
		anchor = _player.global_position

	_refresh_timer -= delta
	var anchor_chunk := world_to_chunk(anchor)
	if anchor_chunk != _anchor_chunk or _refresh_timer <= 0.0:
		_refresh_timer = 0.5
		_refresh(anchor_chunk)

	_pump()


# ------------------------------------------------------------------ 查询接口

## 全局地面高度。加入 terrain 分组后，出生点、敌人、营地都通过它贴地。
func height_at(x: float, z: float) -> float:
	return field.height_at(x, z)


func world_to_chunk(position: Vector3) -> Vector2i:
	var half := world_size * 0.5
	var cx := int(floor((position.x + half) / chunk_size))
	var cz := int(floor((position.z + half) / chunk_size))
	return Vector2i(clampi(cx, 0, _grid - 1), clampi(cz, 0, _grid - 1))


func chunk_origin(coord: Vector2i) -> Vector2:
	var half := world_size * 0.5
	return Vector2(coord.x * chunk_size - half, coord.y * chunk_size - half)


func in_bounds(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.y >= 0 and coord.x < _grid and coord.y < _grid


func get_chunk(coord: Vector2i) -> WorldChunk:
	return _chunks.get(coord, null)


func is_chunk_loaded(coord: Vector2i) -> bool:
	return _chunks.has(coord)


func loaded_chunk_count() -> int:
	return _chunks.size()


func get_loaded_chunk_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for coord in _chunks.keys():
		out.append(coord)
	return out


func get_player_chunk() -> Vector2i:
	var anchor := _player.global_position if _player != null else Vector3.ZERO
	return world_to_chunk(anchor)


# ------------------------------------------------------------------ 资源

func terrain_material() -> StandardMaterial3D:
	return _terrain_mat


func painted_material() -> StandardMaterial3D:
	return _painted_mat


func swaying_material() -> ShaderMaterial:
	return _sway_mat


## 树木网格全局缓存：1024 m 世界里同一种树被撒几万次，不能每块都重新拼网格。
func mesh_for(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]

	var mesh: Mesh = null
	if key.begins_with("pine_"):
		var index := int(key.substr(5))
		mesh = PropKit.make_pine_tree(
			Color(0.27, 0.19, 0.14), Color(0.15, 0.29, 0.17),
			field.world_seed + 131 * (index + 1))
	elif key.begins_with("birch_"):
		var index := int(key.substr(6))
		mesh = PropKit.make_birch_tree(
			Color(0.76, 0.73, 0.66), Color(0.21, 0.32, 0.15),
			field.world_seed + 977 * (index + 1))
	else:
		match key:
			"snag":
				mesh = PropKit.make_dead_tree(Color(0.34, 0.28, 0.22), field.world_seed + 613)
			"log":
				mesh = PropKit.make_fallen_log(field.world_seed + 71)
			"stump":
				mesh = PropKit.make_stump(field.world_seed + 89)
			"rock":
				mesh = PropKit.make_rock(field.world_seed + 5)
			"shrub":
				mesh = PropKit.make_shrub(Color(0.2, 0.32, 0.17))
			"grass":
				mesh = PropKit.make_grass_tuft(Color(0.19, 0.28, 0.12))
			_:
				GameLog.warn("未知的植被网格", {"key": key})

	_meshes[key] = mesh
	return mesh


func vegetation_seed(coord: Vector2i) -> int:
	var mixed := field.world_seed ^ (coord.x * 73856093) ^ (coord.y * 19349663)
	return int(abs(mixed) % 2147483647) + 1


# ------------------------------------------------------------------ 流式加载

func _refresh(anchor_chunk: Vector2i) -> void:
	_anchor_chunk = anchor_chunk
	_queue.clear()
	_veg_queue.clear()
	_collision_queue.clear()

	# 1. 卸载走远的区块
	var to_unload: Array[Vector2i] = []
	for key in _chunks.keys():
		var coord: Vector2i = key
		if _chebyshev(coord, anchor_chunk) > terrain_radius_chunks:
			to_unload.append(coord)
	for coord in to_unload:
		_unload_chunk(coord)

	# 2. 给已有区块更新碰撞与植被档位
	for key in _chunks.keys():
		var coord: Vector2i = key
		var chunk: WorldChunk = _chunks[coord]
		var distance := _chebyshev(coord, anchor_chunk)
		if distance <= collision_radius_chunks:
			if not chunk.has_collision() and not chunk.collision_pending:
				chunk.collision_pending = true
				_collision_queue.append(coord)
		elif chunk.has_collision():
			chunk.ensure_collision(false)

		var band := _band_for(distance)
		if chunk.vegetation_band != band:
			_veg_queue.append({"coord": coord, "band": band})

	# 3. 近处优先排队缺失的区块
	for ring in range(terrain_radius_chunks + 1):
		for coord in _ring_coords(anchor_chunk, ring):
			if not _chunks.has(coord):
				_queue.append(coord)


func _pump() -> void:
	# 碰撞优先：脚下这块地必须尽快能站人
	if not _collision_queue.is_empty():
		var collision_coord: Vector2i = _collision_queue.pop_front()
		if _chunks.has(collision_coord):
			var chunk: WorldChunk = _chunks[collision_coord]
			chunk.collision_pending = false
			if _chebyshev(collision_coord, _anchor_chunk) <= collision_radius_chunks:
				chunk.ensure_collision(true)

	if not _queue.is_empty():
		var start := Time.get_ticks_usec()
		var built := 0
		while not _queue.is_empty() and built < 2:
			var coord: Vector2i = _queue.pop_front()
			if _chunks.has(coord) or not in_bounds(coord):
				continue
			_build_chunk(coord)
			built += 1
			if (Time.get_ticks_usec() - start) > build_budget_ms * 1000.0:
				break

	if not _veg_queue.is_empty():
		var veg_start := Time.get_ticks_usec()
		var veg_built := 0
		while not _veg_queue.is_empty() and veg_built < 1:
			var job: Dictionary = _veg_queue.pop_front()
			var coord: Vector2i = job["coord"]
			if not _chunks.has(coord):
				continue
			_chunks[coord].build_vegetation(int(job["band"]))
			veg_built += 1
			if (Time.get_ticks_usec() - veg_start) > build_budget_ms * 1000.0:
				break


func _build_chunk(coord: Vector2i) -> WorldChunk:
	var chunk := WorldChunk.new()
	chunk.setup(self, coord, chunk_size, terrain_resolution)
	add_child(chunk)
	chunk.build_terrain()

	var override := GameState.get_chunk_modification(coord)
	if not override.is_empty():
		chunk.apply_override(override)

	_chunks[coord] = chunk
	chunk_loaded.emit(coord)
	return chunk


func _unload_chunk(coord: Vector2i) -> void:
	if not _chunks.has(coord):
		return
	var chunk: WorldChunk = _chunks[coord]
	_chunks.erase(coord)
	chunk.queue_free()
	chunk_unloaded.emit(coord)


func _build_initial_chunks() -> void:
	var center := world_to_chunk(Vector3.ZERO)
	_anchor_chunk = center
	var radius := clampi(initial_radius_chunks, 0, terrain_radius_chunks)
	for ring in range(radius + 1):
		for coord in _ring_coords(center, ring):
			if not _chunks.has(coord):
				_build_chunk(coord)

	# 出生点周围同步建碰撞：玩家在下一帧就会被放下来，不能等分帧队列
	for key in _chunks.keys():
		var coord: Vector2i = key
		if _chebyshev(coord, center) <= collision_radius_chunks:
			_chunks[coord].ensure_collision(true)
	# 出生点的植被先排上队（下一帧起按预算逐块生成）
	_refresh(center)


func _band_for(distance: int) -> int:
	if distance <= vegetation_radius_chunks:
		return WorldChunk.BAND_FULL
	if distance <= sparse_vegetation_radius_chunks:
		return WorldChunk.BAND_SPARSE
	return -1


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _ring_coords(center: Vector2i, ring: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dz in range(-ring, ring + 1):
		for dx in range(-ring, ring + 1):
			if maxi(absi(dx), absi(dz)) != ring:
				continue
			var coord := center + Vector2i(dx, dz)
			if in_bounds(coord):
				out.append(coord)
	return out


# ------------------------------------------------------------------ 存档

## 记录某区块被永久改动（例如整块植被被清空）。重建区块时自动应用。
func mark_chunk_modified(coord: Vector2i, state_data: Dictionary) -> void:
	if not in_bounds(coord):
		return
	GameState.mark_chunk_modified(coord, state_data)
	rebuild_chunk(coord)


## 强制重建某区块。用于应用存档改动，也用于确定性测试。
func rebuild_chunk(coord: Vector2i, immediate: bool = true) -> void:
	if _chunks.has(coord):
		var chunk: WorldChunk = _chunks[coord]
		_chunks.erase(coord)
		remove_child(chunk)
		chunk.queue_free()
	if not in_bounds(coord):
		return
	if immediate:
		var fresh := _build_chunk(coord)
		_refresh_vegetation_for(fresh)
		if _chebyshev(coord, _anchor_chunk) <= collision_radius_chunks:
			fresh.ensure_collision(true)
	else:
		_queue.append(coord)


func _refresh_vegetation_for(chunk: WorldChunk) -> void:
	var band := _band_for(_chebyshev(chunk.coord, _anchor_chunk))
	chunk.build_vegetation(band)


func _on_game_loaded(_slot: int) -> void:
	var saved_seed := int(GameState.world_seed)
	if saved_seed <= 0:
		# 旧存档没有种子：沿用当前世界，并把它写回存档
		GameState.world_seed = field.world_seed
	elif saved_seed != field.world_seed:
		# 存档来自另一张地图：换种子并整世界重建
		field.set_seed(saved_seed)
		world_seed = saved_seed
		_meshes.clear()
		_clear_chunks()
		_build_initial_chunks()
		GameLog.info("世界种子已按存档切换", {"seed": saved_seed})
		return

	# 同一种子：把存档里记录过改动的区块重建一遍
	for key in _chunks.keys():
		var coord: Vector2i = key
		var override := GameState.get_chunk_modification(coord)
		if not override.is_empty():
			rebuild_chunk(coord)


func _clear_chunks() -> void:
	for key in _chunks.keys():
		var chunk: WorldChunk = _chunks[key]
		remove_child(chunk)
		chunk.queue_free()
	_chunks.clear()
	_queue.clear()
	_veg_queue.clear()
	_collision_queue.clear()
