class_name ProcTerrain
extends Node3D
## 程序化地形：高度图网格 + 坡度着色 + 凹多边形碰撞。
##
## 使用带种子的 FastNoiseLite，同一 seed 必得同一地形（docs/technical-design.md §6.2）。
## 溪谷与营地平地由显式剖面控制，保证关键路径与建筑可用。

signal terrain_built()

@export var area_size: Vector2 = Vector2(140, 140)
@export var resolution: int = 112
@export var terrain_seed: int = 20261117
@export var amplitude: float = 7.0
@export var detail_amplitude: float = 1.4

## 溪谷：沿 Z 方向延伸的一条低洼带。
@export var creek_center_x: float = 11.0
@export var creek_half_width: float = 2.4
@export var creek_depth: float = -1.15

## 营地平整区：以原点为中心的圆形平台。
@export var camp_center: Vector3 = Vector3.ZERO
@export var camp_flat_radius: float = 15.0
@export var camp_blend_radius: float = 24.0
@export var camp_height: float = 0.0

var _base_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _cell: float = 1.0
var _heights: PackedFloat32Array
var _material: StandardMaterial3D


func _ready() -> void:
	# 地形节点加入 terrain 分组，便于出生点等系统查询地面高度
	add_to_group(&"terrain")


func build() -> void:
	_base_noise = FastNoiseLite.new()
	_base_noise.seed = terrain_seed
	_base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_base_noise.frequency = 0.012
	_base_noise.fractal_octaves = 4
	_base_noise.fractal_lacunarity = 2.0

	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = terrain_seed + 977
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail_noise.frequency = 0.055
	_detail_noise.fractal_octaves = 3

	_cell = area_size.x / float(resolution)
	_sample_heights()
	_build_mesh()
	_build_collision()
	terrain_built.emit()
	GameLog.info("地形生成完成", {
		"size": area_size,
		"resolution": resolution,
		"seed": terrain_seed,
	})


func _sample_heights() -> void:
	var count := (resolution + 1) * (resolution + 1)
	_heights = PackedFloat32Array()
	_heights.resize(count)

	for z in resolution + 1:
		for x in resolution + 1:
			var world := _grid_to_world(x, z)
			_heights[z * (resolution + 1) + x] = _sample_height(world.x, world.y)


func _grid_to_world(x: int, z: int) -> Vector2:
	var u := float(x) / float(resolution) - 0.5
	var v := float(z) / float(resolution) - 0.5
	return Vector2(u * area_size.x, v * area_size.y)


## 高度剖面：基础噪声 + 细节 + 溪谷下切 + 营地平整。
func _sample_height(x: float, z: float) -> float:
	var h := _base_noise.get_noise_2d(x, z) * amplitude
	h += _detail_noise.get_noise_2d(x, z) * detail_amplitude

	# 溪谷：横向按距离衰减，纵向保持连续；河床取固定高度，水面才平
	var creek_distance := absf(x - creek_center_x)
	if creek_distance < creek_half_width * 2.2:
		var t := 1.0 - clampf(creek_distance / (creek_half_width * 2.2), 0.0, 1.0)
		h = lerpf(h, creek_depth, t * t * (3.0 - 2.0 * t))

	# 营地平整：中心完全水平，向外平滑过渡
	var distance := Vector2(x - camp_center.x, z - camp_center.z).length()
	if distance < camp_blend_radius:
		var t := 1.0 - clampf(
			(distance - camp_flat_radius) / maxf(camp_blend_radius - camp_flat_radius, 0.001),
			0.0, 1.0
		)
		h = lerpf(h, camp_height, t * t * (3.0 - 2.0 * t))

	return h


func _build_mesh() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()

	for z in resolution + 1:
		for x in resolution + 1:
			var world := _grid_to_world(x, z)
			var h := _heights[z * (resolution + 1) + x]
			vertices.append(Vector3(world.x, h, world.y))

			var normal := _normal_at(x, z)
			normals.append(normal)
			uvs.append(Vector2(float(x) / float(resolution), float(z) / float(resolution)))
			colors.append(_color_at(world.x, world.y, h, 1.0 - normal.y))

	var indices := PackedInt32Array()
	for z in resolution:
		for x in resolution:
			var i0 := z * (resolution + 1) + x
			var i1 := i0 + 1
			var i2 := i0 + (resolution + 1)
			var i3 := i2 + 1
			# 绕向必须是 (v00, v10, v01) 这一侧朝上。
			# Godot 的正面与物理背面判定用同一套顺时针规则：
			# 写反了地形既看不见（被背面剔除），角色也会直接穿过去。
			indices.append(i0)
			indices.append(i1)
			indices.append(i2)
			indices.append(i1)
			indices.append(i3)
			indices.append(i2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.95
	_material.metallic = 0.0
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material
	add_child(mesh_instance)


func _normal_at(x: int, z: int) -> Vector3:
	var h_left := _height_index(maxi(x - 1, 0), z)
	var h_right := _height_index(mini(x + 1, resolution), z)
	var h_down := _height_index(x, maxi(z - 1, 0))
	var h_up := _height_index(x, mini(z + 1, resolution))
	return Vector3(h_left - h_right, 2.0 * _cell, h_down - h_up).normalized()


func _height_index(x: int, z: int) -> float:
	return _heights[z * (resolution + 1) + x]


## 按高度、坡度和所处区域着色：溪谷露土、营地是被踩实的空地、陡坡露岩。
func _color_at(x: float, z: float, height: float, slope: float) -> Color:
	var grass := Color(0.19, 0.29, 0.15)
	var deep_grass := Color(0.12, 0.2, 0.11)
	var dirt := Color(0.34, 0.27, 0.18)
	var gravel := Color(0.4, 0.38, 0.34)
	var rock := Color(0.38, 0.38, 0.36)

	# 高处林线更深沉
	var color := grass.lerp(deep_grass, clampf(height / (amplitude * 0.8), 0.0, 1.0))

	# 溪谷河床常年被水冲刷，露土露砂
	if height < -0.35:
		color = color.lerp(gravel, clampf((-height - 0.35) / 0.8, 0.0, 1.0))

	# 营地是被踩实的空地
	var camp_distance := Vector2(x - camp_center.x, z - camp_center.z).length()
	if camp_distance < camp_flat_radius:
		var wear := 1.0 - camp_distance / camp_flat_radius
		color = color.lerp(dirt, 0.55 * wear * wear)

	# 陡坡露岩
	if slope > 0.35:
		color = color.lerp(rock, clampf((slope - 0.35) / 0.45, 0.0, 1.0))

	return color


func _build_collision() -> void:
	var faces := PackedVector3Array()
	for z in resolution:
		for x in resolution:
			var v00 := _vertex(x, z)
			var v10 := _vertex(x + 1, z)
			var v01 := _vertex(x, z + 1)
			var v11 := _vertex(x + 1, z + 1)
			# 碰撞面的绕向必须与渲染网格相反。
			# Godot 物理的凹多边形按 (c-a)×(b-a) 判背面，与渲染的正面绕向相反；
			# 绕反了角色会从地面直接穿过去（is_on_floor 永远为 false）。
			faces.append(v00)
			faces.append(v10)
			faces.append(v01)
			faces.append(v10)
			faces.append(v11)
			faces.append(v01)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0

	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _vertex(x: int, z: int) -> Vector3:
	var world := _grid_to_world(x, z)
	return Vector3(world.x, _height_index(x, z), world.y)


## 查询世界坐标处的地面高度，供道具贴地摆放。
func height_at(x: float, z: float) -> float:
	return _sample_height(x, z)


## 把一个节点贴到地面（保留自身 XZ）。
func place_on_ground(node: Node3D, offset_y: float = 0.0) -> void:
	var position := node.global_position
	node.global_position = Vector3(position.x, height_at(position.x, position.z) + offset_y, position.z)
