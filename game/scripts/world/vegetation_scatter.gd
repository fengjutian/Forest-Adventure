class_name VegetationScatter
extends Node3D
## 程序化植被散布：松林、岩石、灌木，全部用 MultiMesh 实例化。
##
## 散布规则（docs/open-world-design.md §2 / §4）：
##  - 营地、溪流、主路径范围内不生成，保证可读性与可通行
##  - 陡坡不生长
##  - 密度由噪声调制，形成疏密变化而不是均匀网格
##  - 同 seed 同输入必得同一结果

signal scatter_complete(tree_count: int, rock_count: int, shrub_count: int)

@export var scatter_seed: int = 41721
@export var area_size: Vector2 = Vector2(140, 140)

@export_group("密度")
## 网格间距，越小候选点越多。
@export var cell_size: float = 4.2
@export var tree_density: float = 0.72
@export var rock_density: float = 0.16
@export var shrub_density: float = 0.3

@export_group("排除区")
## 营地周围的空地半径。
@export var camp_clear_radius: float = 13.0
@export var creek_center_x: float = 11.0
@export var creek_clear_width: float = 4.2
## 主路径：从营地通往松木深林入口的走廊。
@export var path_start: Vector2 = Vector2(0.0, 6.0)
@export var path_end: Vector2 = Vector2(1.5, -26.0)
@export var path_half_width: float = 3.6

@export_group("坡度")
## 坡度超过该值的地面不生长（1 表示垂直）。
@export var max_slope: float = 0.45

@export_group("地被")
## 地被层网格间距（比乔木密得多）。
@export var ground_cover_cell_size: float = 2.2
## 地被密度。
@export var ground_cover_density: float = 0.5
## 溪流两侧不长草的距离。
@export var creek_grass_clear_width: float = 3.0

var _rng := RandomNumberGenerator.new()
var _density_noise: FastNoiseLite
var _terrain: ProcTerrain


func scatter(terrain: ProcTerrain) -> void:
	_terrain = terrain
	_rng.seed = scatter_seed

	_density_noise = FastNoiseLite.new()
	_density_noise.seed = scatter_seed + 313
	_density_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_density_noise.frequency = 0.035
	_density_noise.fractal_octaves = 3

	var tree_placements: Array = []
	var rock_placements: Array = []
	var shrub_placements: Array = []

	var half := area_size * 0.5
	var steps := int(area_size.x / cell_size)

	for gz in steps:
		for gx in steps:
			var base := Vector2(
				-half.x + (float(gx) + 0.5) * cell_size,
				-half.y + (float(gz) + 0.5) * cell_size
			)
			var position := base + Vector2(
				_rng.randf_range(-cell_size * 0.48, cell_size * 0.48),
				_rng.randf_range(-cell_size * 0.48, cell_size * 0.48)
			)

			if _is_excluded(position):
				continue
			if _slope_at(position) > max_slope:
				continue

			var density := _density_at(position)
			if _rng.randf() <= density:
				tree_placements.append(_make_transform(position, 0.8, 1.35))
			elif _rng.randf() < rock_density:
				rock_placements.append(_make_transform(position, 0.55, 1.5))
			elif _rng.randf() < shrub_density:
				shrub_placements.append(_make_transform(position, 0.7, 1.4))

	_build_multimesh("Pines", PropKit.make_pine_tree(
		Color(0.27, 0.19, 0.14), Color(0.15, 0.29, 0.17)), tree_placements, 0.0)
	_build_multimesh("Rocks", PropKit.make_rock(scatter_seed + 5), rock_placements, 0.0)
	_build_multimesh("Shrubs", PropKit.make_shrub(Color(0.2, 0.32, 0.17)), shrub_placements, 0.0)

	_build_ground_cover(half)

	scatter_complete.emit(tree_placements.size(), rock_placements.size(), shrub_placements.size())
	GameLog.info("植被散布完成", {
		"trees": tree_placements.size(),
		"rocks": rock_placements.size(),
		"shrubs": shrub_placements.size(),
	})


## 地被层：草丛铺满空地，让地面不再光秃。
func _build_ground_cover(half: Vector2) -> void:
	var placements: Array = []
	var steps := int(area_size.x / ground_cover_cell_size)

	for gz in steps:
		for gx in steps:
			var base := Vector2(
				-half.x + (float(gx) + 0.5) * ground_cover_cell_size,
				-half.y + (float(gz) + 0.5) * ground_cover_cell_size
			)
			var position := base + Vector2(
				_rng.randf_range(-ground_cover_cell_size * 0.48, ground_cover_cell_size * 0.48),
				_rng.randf_range(-ground_cover_cell_size * 0.48, ground_cover_cell_size * 0.48)
			)

			if _is_grass_excluded(position):
				continue
			if _slope_at(position) > max_slope:
				continue
			if _rng.randf() > ground_cover_density:
				continue

			placements.append(_make_transform(position, 0.6, 1.15, 0.03))

	_build_multimesh("GrassTufts", PropKit.make_grass_tuft(Color(0.19, 0.28, 0.12)),
		placements, 0.0)
	GameLog.info("地被层完成", {"tufts": placements.size()})


## 地被只在溪流与主路径之外生长；营地内保留野草。
func _is_grass_excluded(position: Vector2) -> bool:
	if absf(position.x - creek_center_x) < creek_grass_clear_width:
		return true
	if _distance_to_path(position) < path_half_width * 0.8:
		return true
	return false


func _density_at(position: Vector2) -> float:
	var noise := _density_noise.get_noise_2d(position.x, position.y) * 0.5 + 0.5
	# 越靠近林缘越密，形成自然的疏密边界
	var edge := clampf(minf(
		absf(position.x) - area_size.x * 0.32,
		absf(position.y) - area_size.y * 0.32
	) / 18.0, 0.0, 1.0)
	return clampf(tree_density * noise * (0.45 + 0.55 * edge), 0.0, 1.0)


func _is_excluded(position: Vector2) -> bool:
	if position.distance_to(Vector2.ZERO) < camp_clear_radius:
		return true
	if absf(position.x - creek_center_x) < creek_clear_width:
		return true
	if _distance_to_path(position) < path_half_width:
		return true
	return false


func _distance_to_path(position: Vector2) -> float:
	var segment := path_end - path_start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return position.distance_to(path_start)
	var t := clampf((position - path_start).dot(segment) / length_squared, 0.0, 1.0)
	return position.distance_to(path_start + segment * t)


func _slope_at(position: Vector2) -> float:
	if _terrain == null:
		return 0.0
	var step := 1.2
	var h_left := _terrain.height_at(position.x - step, position.y)
	var h_right := _terrain.height_at(position.x + step, position.y)
	var h_down := _terrain.height_at(position.x, position.y - step)
	var h_up := _terrain.height_at(position.x, position.y + step)
	var normal := Vector3(h_left - h_right, 2.0 * step, h_down - h_up).normalized()
	return 1.0 - normal.y


func _make_transform(position: Vector2, min_scale: float, max_scale: float,
		sink: float = 0.15) -> Dictionary:
	var height := _terrain.height_at(position.x, position.y) if _terrain != null else 0.0
	var scale := _rng.randf_range(min_scale, max_scale)
	var rotation := _rng.randf_range(0.0, TAU)

	var basis := Basis.from_euler(Vector3(0.0, rotation, 0.0)).scaled(Vector3.ONE * scale)
	return {
		"transform": Transform3D(basis, Vector3(position.x, height - sink * scale, position.y)),
		"color": Color(1, 1, 1).lerp(Color(0.82, 0.88, 0.78), _rng.randf() * 0.5),
	}


func _build_multimesh(node_name: String, mesh: Mesh, placements: Array, y_offset: float) -> void:
	if placements.is_empty():
		return

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = placements.size()

	for i in placements.size():
		var placement: Dictionary = placements[i]
		multimesh.set_instance_transform(i, placement["transform"])
		multimesh.set_instance_color(i, placement["color"])

	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = PropKit.painted_material()
	add_child(instance)
