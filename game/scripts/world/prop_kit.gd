class_name PropKit
extends RefCounted
## 程序化网格与材质工具库。
##
## 灰盒阶段的视觉资产全部用基础几何体 + 顶点色拼装：
## 合并后的网格共用一张「顶点色即反照率」的材质，避免材质数量膨胀。
##
## 正式美术资产到位后，替换本文件中的构造函数即可，调用方无需改动。

# ------------------------------------------------------------------ 材质

## 顶点色即反照率的通用材质。
static func painted_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.88
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


## 自发光材质，用于窗内暖光、发电机指示灯、营火。
static func glow_material(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.35
	return mat


## 水面材质：半透明 + 高光。
static func water_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.34, 0.42, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.35
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


# ------------------------------------------------------------------ 网格工具

## 把若干 (网格, 变换, 颜色) 合并成一张带顶点色的网格。
##
## 直接搬运 surface 数组而不是用 SurfaceTool.append_from——后者的通道格式
## 必须与来源网格完全一致，基础图元之间很容易对不上。
static func merge(parts: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for part in parts:
		var source: Mesh = part[0]
		var xform: Transform3D = part[1]
		var color: Color = part[2]
		var normal_basis := xform.basis.inverse().transposed()

		for surface_index in source.get_surface_count():
			var arrays: Array = source.surface_get_arrays(surface_index)
			var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var source_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var offset := vertices.size()

			for i in source_vertices.size():
				vertices.append(xform * source_vertices[i])
				if i < source_normals.size():
					normals.append((normal_basis * source_normals[i]).normalized())
				else:
					normals.append(Vector3.UP)
				if i < source_uvs.size():
					uvs.append(source_uvs[i])
				else:
					uvs.append(Vector2.ZERO)
				colors.append(color)

			if source_indices.size() > 0:
				for index in source_indices:
					indices.append(index + offset)
			else:
				for i in source_vertices.size():
					indices.append(i + offset)

	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = vertices
	result[Mesh.ARRAY_NORMAL] = normals
	result[Mesh.ARRAY_TEX_UV] = uvs
	result[Mesh.ARRAY_COLOR] = colors
	result[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result)
	return mesh


static func _box(size: Vector3, xform: Transform3D, color: Color) -> Array:
	var mesh := BoxMesh.new()
	mesh.size = size
	return [mesh, xform, color]


static func _cylinder(radius: float, height: float, xform: Transform3D, color: Color, segments: int = 10) -> Array:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return [mesh, xform, color]


static func _cone(radius: float, height: float, xform: Transform3D, color: Color, segments: int = 9) -> Array:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return [mesh, xform, color]


static func _sphere(radius: float, xform: Transform3D, color: Color, segments: int = 8) -> Array:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = int(max(4, segments / 2))
	return [mesh, xform, color]


static func _prism(size: Vector3, xform: Transform3D, color: Color) -> Array:
	var mesh := PrismMesh.new()
	mesh.size = size
	return [mesh, xform, color]


static func _xform(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> Transform3D:
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)
	))
	return Transform3D(basis.scaled(scale), pos)


# ------------------------------------------------------------------ 植被

## 松树：树干 + 三层针叶冠。合并成一张网格供 MultiMesh 使用。
static func make_pine_tree(trunk_color: Color, foliage_color: Color) -> ArrayMesh:
	var parts: Array = []
	parts.append(_cylinder(0.28, 7.0, _xform(Vector3(0, 3.5, 0)), trunk_color, 6))

	parts.append(_cone(2.1, 3.4, _xform(Vector3(0, 5.2, 0)), foliage_color))
	parts.append(_cone(1.7, 3.0, _xform(Vector3(0, 7.1, 0)), foliage_color.lightened(0.06)))
	parts.append(_cone(1.2, 2.6, _xform(Vector3(0, 8.9, 0)), foliage_color.lightened(0.12)))
	return merge(parts)


## 草丛：几片细长锥形叶片，低多边形风格，用作地被层。
static func make_grass_tuft(tint: Color) -> ArrayMesh:
	var parts: Array = []
	for i in 4:
		var angle := float(i) * 79.0 + 23.0
		var tilt := 9.0 + float(i % 3) * 8.0
		var height := 0.34 + float(i % 2) * 0.16
		var offset := Vector3(cos(deg_to_rad(angle)), 0.0, sin(deg_to_rad(angle))) * 0.09
		var rot := Vector3(tilt * sin(deg_to_rad(angle)), 0.0, -tilt * cos(deg_to_rad(angle)))
		parts.append(_cone(0.075, height,
			_xform(offset + Vector3(0, height * 0.5, 0), rot),
			tint.lightened(float(i % 3) * 0.05), 4))
	return merge(parts)


## 阔叶灌木 / 蕨丛：几团压扁的球体。
static func make_shrub(color: Color) -> ArrayMesh:
	var parts: Array = []
	parts.append(_sphere(0.55, _xform(Vector3(0, 0.32, 0), Vector3(0, 0, 0), Vector3(1, 0.62, 1)), color))
	parts.append(_sphere(0.4, _xform(Vector3(0.32, 0.24, 0.18), Vector3(0, 0, 0), Vector3(1, 0.6, 1)), color.lightened(0.08)))
	parts.append(_sphere(0.36, _xform(Vector3(-0.28, 0.22, -0.2), Vector3(0, 0, 0), Vector3(1, 0.6, 1)), color.darkened(0.05)))
	return merge(parts)


## 岩石：低面数球体加不规则缩放。
static func make_rock(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var parts: Array = []
	var lumps := rng.randi_range(2, 3)
	for i in lumps:
		var radius := rng.randf_range(0.35, 0.75)
		var offset := Vector3(
			rng.randf_range(-0.35, 0.35),
			rng.randf_range(-0.1, 0.18),
			rng.randf_range(-0.35, 0.35)
		)
		var scale := Vector3(1.0, rng.randf_range(0.55, 0.85), 1.0)
		var tint := Color(0.42, 0.41, 0.39).lerp(Color(0.5, 0.47, 0.42), rng.randf())
		parts.append(_sphere(radius, _xform(offset, Vector3(0, rng.randf_range(0, 360), 0), scale), tint, 6))
	return merge(parts)


# ------------------------------------------------------------------ 营地建筑

## 主木屋：墙板 + 人字屋顶 + 门 + 亮着暖光的窗 + 角柱 + 门廊 + 石基。
static func make_cabin() -> ArrayMesh:
	var wall := Color(0.44, 0.32, 0.22)
	var wall_dark := Color(0.34, 0.24, 0.17)
	var roof := Color(0.24, 0.20, 0.18)
	var trim := Color(0.28, 0.20, 0.14)
	var stone := Color(0.36, 0.35, 0.33)

	var parts: Array = []
	var w := 6.0
	var d := 5.0
	var h := 3.2

	# 石基与地板
	parts.append(_box(Vector3(w + 0.24, 0.26, d + 0.24), _xform(Vector3(0, 0.13, 0)), stone))
	parts.append(_box(Vector3(w, 0.18, d), _xform(Vector3(0, 0.09, 0)), wall_dark))

	# 墙体
	parts.append(_box(Vector3(w, h, 0.2), _xform(Vector3(0, h * 0.5, d * 0.5)), wall))
	parts.append(_box(Vector3(w, h, 0.2), _xform(Vector3(0, h * 0.5, -d * 0.5)), wall))
	parts.append(_box(Vector3(0.2, h, d), _xform(Vector3(w * 0.5, h * 0.5, 0)), wall))
	parts.append(_box(Vector3(0.2, h, d), _xform(Vector3(-w * 0.5, h * 0.5, 0)), wall))

	# 四角立柱
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			parts.append(_box(Vector3(0.26, h, 0.26),
				_xform(Vector3(sx * (w * 0.5 - 0.06), h * 0.5, sz * (d * 0.5 - 0.06))), trim))

	# 横向加固梁
	for level in [1.0, 2.1]:
		parts.append(_box(Vector3(w + 0.08, 0.12, 0.08),
			_xform(Vector3(0, level, d * 0.5 + 0.08)), trim))
		parts.append(_box(Vector3(w + 0.08, 0.12, 0.08),
			_xform(Vector3(0, level, -d * 0.5 - 0.08)), trim))

	# 人字屋顶（两片斜板）
	var roof_len := 3.6
	var slope := 32.0
	parts.append(_box(Vector3(w + 0.8, 0.18, roof_len),
		_xform(Vector3(0, h + 0.75, roof_len * 0.32), Vector3(-slope, 0, 0)), roof))
	parts.append(_box(Vector3(w + 0.8, 0.18, roof_len),
		_xform(Vector3(0, h + 0.75, -roof_len * 0.32), Vector3(slope, 0, 0)), roof))

	# 门（正面 +Z）
	parts.append(_box(Vector3(1.1, 2.1, 0.1), _xform(Vector3(-1.4, 1.05, d * 0.5 + 0.06)), trim))

	# 门廊：两根柱 + 一片顶棚
	parts.append(_box(Vector3(2.6, 0.12, 1.3),
		_xform(Vector3(-1.4, 2.4, d * 0.5 + 0.65), Vector3(-10, 0, 0)), roof))
	parts.append(_cylinder(0.07, 2.3, _xform(Vector3(-2.45, 1.15, d * 0.5 + 1.1)), trim, 6))
	parts.append(_cylinder(0.07, 2.3, _xform(Vector3(-0.35, 1.15, d * 0.5 + 1.1)), trim, 6))

	# 窗框与窗台
	parts.append(_box(Vector3(1.2, 0.12, 0.3), _xform(Vector3(1.4, 1.55, d * 0.5 + 0.1)), trim))
	parts.append(_box(Vector3(1.2, 0.12, 0.3), _xform(Vector3(-1.4, 1.55, -d * 0.5 - 0.1)), trim))

	# 烟囱
	parts.append(_box(Vector3(0.55, 1.5, 0.55), _xform(Vector3(w * 0.28, h + 1.4, -0.8)), roof))

	return merge(parts)


## 窗玻璃（自发光暖光），单独一张网格便于用不同材质。
static func make_cabin_windows() -> ArrayMesh:
	var glass := Color(1.0, 0.72, 0.38)
	var parts: Array = []
	# 玻璃要贴在墙体外面（墙厚 0.2，外表面在 ±2.6），否则会被墙挡住
	parts.append(_box(Vector3(1.0, 0.9, 0.06), _xform(Vector3(1.4, 1.62, 2.63)), glass))
	parts.append(_box(Vector3(1.0, 0.9, 0.06), _xform(Vector3(-1.4, 1.62, -2.63)), glass))
	return merge(parts)


## 物资棚：更小的木屋，单坡屋顶。
static func make_supply_shed() -> ArrayMesh:
	var wood := Color(0.38, 0.3, 0.22)
	var roof := Color(0.22, 0.2, 0.19)
	var parts: Array = []
	parts.append(_box(Vector3(3.0, 2.4, 2.4), _xform(Vector3(0, 1.2, 0)), wood))
	parts.append(_box(Vector3(3.4, 0.14, 2.9), _xform(Vector3(0, 2.55, 0.1), Vector3(-12, 0, 0)), roof))
	# 损坏的门锁
	parts.append(_box(Vector3(0.12, 0.34, 0.12), _xform(Vector3(0.9, 1.3, 1.24)), Color(0.5, 0.44, 0.28)))
	return merge(parts)


## 发电机：机体 + 排气管 + 散热片。
static func make_generator() -> ArrayMesh:
	var body := Color(0.32, 0.34, 0.36)
	var dark := Color(0.2, 0.21, 0.23)
	var parts: Array = []
	parts.append(_box(Vector3(1.5, 0.9, 1.0), _xform(Vector3(0, 0.45, 0)), body))
	parts.append(_cylinder(0.34, 1.0, _xform(Vector3(0.45, 0.9, 0), Vector3(0, 0, 90)), dark, 10))
	parts.append(_cylinder(0.11, 0.8, _xform(Vector3(-0.5, 1.25, -0.3)), Color(0.3, 0.3, 0.31), 8))
	# 散热片
	for i in 5:
		parts.append(_box(Vector3(0.06, 0.6, 1.02), _xform(Vector3(-0.6 + i * 0.14, 0.5, 0)), dark))
	# 底座
	parts.append(_box(Vector3(1.7, 0.12, 1.2), _xform(Vector3(0, 0.06, 0)), dark))
	return merge(parts)


## 训练靶：木桩 + 圆靶。
static func make_target() -> ArrayMesh:
	var post := Color(0.4, 0.3, 0.2)
	var ring := Color(0.55, 0.2, 0.18)
	var parts: Array = []
	parts.append(_cylinder(0.07, 1.5, _xform(Vector3(0, 0.75, 0)), post, 6))
	parts.append(_cylinder(0.42, 0.08, _xform(Vector3(0, 1.35, 0), Vector3(90, 0, 0)), ring, 12))
	parts.append(_cylinder(0.22, 0.09, _xform(Vector3(0, 1.35, 0.03), Vector3(90, 0, 0)), Color(0.82, 0.78, 0.7), 12))
	return merge(parts)


## 木柴堆：交叉码放的圆木。
static func make_woodpile() -> ArrayMesh:
	var wood := Color(0.43, 0.32, 0.21)
	var parts: Array = []
	for row in 3:
		for i in 4 - row:
			var x := (float(i) - float(3 - row) * 0.5) * 0.36
			var y := 0.17 + float(row) * 0.3
			parts.append(_cylinder(0.16, 1.2, _xform(Vector3(x, y, 0), Vector3(0, 0, 90)), wood, 8))
	return merge(parts)


## 帐篷：三棱柱帆布 + 前方支柱。
static func make_tent() -> ArrayMesh:
	var canvas := Color(0.34, 0.36, 0.28)
	var pole := Color(0.36, 0.27, 0.19)
	var parts: Array = []
	parts.append(_prism(Vector3(2.8, 1.8, 2.4), _xform(Vector3(0, 0.9, 0), Vector3(0, 90, 0)), canvas))
	parts.append(_cylinder(0.05, 2.4, _xform(Vector3(0, 1.2, 1.05)), pole, 5))
	parts.append(_box(Vector3(1.0, 0.06, 1.1), _xform(Vector3(0, 0.05, 1.5)), pole.darkened(0.1)))
	return merge(parts)


## 灯柱：木杆 + 提灯外壳（灯罩单独用自发光材质）。
static func make_lantern_post() -> ArrayMesh:
	var wood := Color(0.34, 0.26, 0.18)
	var metal := Color(0.22, 0.2, 0.17)
	var parts: Array = []
	parts.append(_cylinder(0.07, 2.3, _xform(Vector3(0, 1.15, 0)), wood, 6))
	parts.append(_box(Vector3(0.3, 0.34, 0.3), _xform(Vector3(0.2, 2.2, 0)), metal))
	parts.append(_cone(0.26, 0.2, _xform(Vector3(0.2, 2.45, 0)), metal.lightened(0.05), 6))
	parts.append(_box(Vector3(0.34, 0.05, 0.05), _xform(Vector3(0.09, 2.4, 0)), metal))
	return merge(parts)


## 提灯灯罩（单独一张网格，用自发光材质渲染）。
static func make_lantern_glass() -> ArrayMesh:
	return merge([_box(Vector3(0.24, 0.26, 0.24), _xform(Vector3(0.2, 2.2, 0)), Color(1, 1, 1))])


## 木桶：桶身 + 两道铁箍。
static func make_barrel() -> ArrayMesh:
	var wood := Color(0.4, 0.3, 0.2)
	var band := Color(0.24, 0.23, 0.21)
	var parts: Array = []
	parts.append(_cylinder(0.34, 0.88, _xform(Vector3(0, 0.44, 0)), wood, 10))
	parts.append(_cylinder(0.36, 0.07, _xform(Vector3(0, 0.2, 0)), band, 10))
	parts.append(_cylinder(0.36, 0.07, _xform(Vector3(0, 0.68, 0)), band, 10))
	return merge(parts)


## 营火：石圈 + 交叠的柴火。
static func make_campfire_stones() -> ArrayMesh:
	var parts: Array = []
	for i in 9:
		var angle := TAU * float(i) / 9.0
		var pos := Vector3(cos(angle) * 0.78, 0.1, sin(angle) * 0.78)
		var tint := Color(0.4, 0.4, 0.38).lerp(Color(0.48, 0.46, 0.43), float(i % 3) / 3.0)
		parts.append(_sphere(0.22, _xform(pos, Vector3(0, i * 40.0, 0), Vector3(1.0, 0.75, 1.0)), tint, 6))
	return merge(parts)


static func make_campfire_logs() -> ArrayMesh:
	var wood := Color(0.32, 0.24, 0.17)
	var parts: Array = []
	parts.append(_cylinder(0.11, 1.1, _xform(Vector3(0, 0.18, 0), Vector3(0, 0, 90)), wood, 6))
	parts.append(_cylinder(0.11, 1.1, _xform(Vector3(0, 0.2, 0), Vector3(0, 70, 78)), wood, 6))
	parts.append(_cylinder(0.1, 1.0, _xform(Vector3(0.04, 0.16, -0.06), Vector3(0, 140, 96)), wood.darkened(0.1), 6))
	return merge(parts)


## 倒木：横卧在松林入口。
static func make_fallen_log() -> ArrayMesh:
	var bark := Color(0.29, 0.21, 0.15)
	var parts: Array = []
	parts.append(_cylinder(0.62, 6.5, _xform(Vector3(0, 0.6, 0), Vector3(0, 0, 90)), bark, 10))
	parts.append(_cylinder(0.5, 0.12, _xform(Vector3(3.2, 0.6, 0), Vector3(0, 0, 90)), Color(0.55, 0.46, 0.33), 10))
	# 断枝
	parts.append(_cylinder(0.1, 1.1, _xform(Vector3(1.4, 1.0, 0.4), Vector3(60, 0, 0)), bark.darkened(0.12), 6))
	return merge(parts)


## 路牌：立柱 + 指向木牌。
static func make_signpost() -> ArrayMesh:
	var wood := Color(0.42, 0.33, 0.23)
	var parts: Array = []
	parts.append(_cylinder(0.09, 1.9, _xform(Vector3(0, 0.95, 0)), wood, 6))
	parts.append(_box(Vector3(1.5, 0.34, 0.08), _xform(Vector3(0.55, 1.65, 0)), wood.lightened(0.1)))
	parts.append(_box(Vector3(1.1, 0.22, 0.07), _xform(Vector3(-0.4, 1.3, 0.02), Vector3(0, 0, -6)), wood.lightened(0.16)))
	return merge(parts)


## 物资箱（木条拼接），用于溪边箱子。
static func make_supply_crate() -> ArrayMesh:
	var wood := Color(0.45, 0.34, 0.22)
	var edge := Color(0.33, 0.24, 0.16)
	var parts: Array = []
	parts.append(_box(Vector3(0.78, 0.62, 0.78), _xform(Vector3(0, 0.31, 0)), wood))
	# 四条竖向加固条
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			parts.append(_box(Vector3(0.1, 0.66, 0.1), _xform(Vector3(sx * 0.36, 0.31, sz * 0.36)), edge))
	parts.append(_box(Vector3(0.84, 0.08, 0.84), _xform(Vector3(0, 0.63, 0)), edge))
	return merge(parts)


## 营地无线电：机体 + 天线 + 旋钮。
static func make_radio() -> ArrayMesh:
	var shell := Color(0.3, 0.28, 0.24)
	var metal := Color(0.5, 0.48, 0.42)
	var parts: Array = []
	parts.append(_box(Vector3(0.58, 0.38, 0.4), _xform(Vector3(0, 0.19, 0)), shell))
	parts.append(_cylinder(0.015, 0.8, _xform(Vector3(0.24, 0.74, -0.1), Vector3(0, 0, 14)), metal, 5))
	parts.append(_cylinder(0.07, 0.04, _xform(Vector3(-0.16, 0.2, 0.21), Vector3(90, 0, 0)), Color(0.6, 0.5, 0.3), 10))
	parts.append(_box(Vector3(0.3, 0.16, 0.03), _xform(Vector3(0.08, 0.24, 0.21)), Color(0.14, 0.16, 0.15)))
	return merge(parts)


## 远处远景剪影用的低面数山体。
static func make_backdrop_hills(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var parts: Array = []
	for i in 7:
		var angle := TAU * float(i) / 7.0 + rng.randf_range(-0.2, 0.2)
		var dist := rng.randf_range(95.0, 130.0)
		var height := rng.randf_range(14.0, 30.0)
		var radius := rng.randf_range(22.0, 38.0)
		var tint := Color(0.16, 0.22, 0.24).lerp(Color(0.24, 0.3, 0.3), rng.randf())
		parts.append(_cone(radius, height,
			_xform(Vector3(cos(angle) * dist, height * 0.5 - 6.0, sin(angle) * dist)), tint, 7))
	return merge(parts)


## 按名称取道具网格，供可交互物脚本使用。
static func make_prop(prop_name: StringName) -> Mesh:
	match prop_name:
		&"crate":
			return make_supply_crate()
		&"radio":
			return make_radio()
		&"campfire_stones":
			return make_campfire_stones()
		&"campfire_logs":
			return make_campfire_logs()
		&"generator":
			return make_generator()
		&"signpost":
			return make_signpost()
		&"woodpile":
			return make_woodpile()
		&"tent":
			return make_tent()
		&"lantern_post":
			return make_lantern_post()
		&"barrel":
			return make_barrel()
		&"grass_tuft":
			return make_grass_tuft(Color(0.26, 0.36, 0.16))
	return null
