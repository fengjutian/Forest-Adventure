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


## 全场共用的顶点色材质。
##
## 材质参数完全一致，没必要每个物件建一份：
## 共用一份能让渲染器按材质归并状态，也省掉每个物件的材质对象。
static var _shared_painted: StandardMaterial3D = null

static func shared_painted_material() -> StandardMaterial3D:
	if _shared_painted == null:
		_shared_painted = painted_material()
	return _shared_painted


## 全场共用的箭矢网格。
##
## 箭每射一支就是一个新节点；每支都重新拼一遍网格，实测在带渲染后端时
## 单支要 **1.38 ms**（无头 0.05 ms——差的是 GPU 网格资源的创建）。
## 40 支插住的箭就是 88 ms 的主线程卡顿。
## 网格一旦建好就不再变，缓存一份给所有箭用即可。
static var _shared_arrow_mesh: ArrayMesh = null

static func shared_arrow_mesh() -> ArrayMesh:
	if _shared_arrow_mesh == null:
		_shared_arrow_mesh = make_arrow()
	return _shared_arrow_mesh


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


## 随风摆动的材质：顶点色即反照率，树越高摆得越多。
##
## 每棵树用世界坐标错开相位，整片林子不会齐刷刷一起晃。
## 只给树木用；MultiMesh 的 INSTANCE_TRANSFORM 提供每棵树的个体变换。
static func swaying_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform float sway_amount : hint_range(0.0, 0.3) = 0.055;
uniform float sway_speed : hint_range(0.0, 4.0) = 1.15;
uniform float sway_height = 9.0;
uniform float sway_falloff : hint_range(1.0, 4.0) = 2.2;

void vertex() {
	float h = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	float weight = pow(h, sway_falloff);
	// 每棵树的相位：散落时写进实例自定义数据，保证整片林子不会齐刷刷一起晃
	float phase = INSTANCE_CUSTOM.r * 6.2831853;
	if (phase == 0.0) {
		vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		phase = world_pos.x * 0.31 + world_pos.z * 0.27;
	}
	float t = TIME * sway_speed + phase;
	VERTEX.x += sin(t) * sway_amount * weight;
	VERTEX.z += cos(t * 0.83) * sway_amount * 0.7 * weight;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.88;
	SPECULAR = 0.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
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

## 松树：带随机形态的针叶树。
##
## 层数、每层半径/高度、层间偏移都随 seed 变化，配合多个变体网格，
## 森林里每棵树的轮廓都不一样，不会变成一排复制品。
static func make_pine_tree(trunk_color: Color, foliage_color: Color, seed_value: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else 20261117

	var parts: Array = []

	# 树干：下粗上细
	var trunk_height := rng.randf_range(6.2, 7.4)
	var trunk_bottom := rng.randf_range(0.3, 0.42)
	var trunk := CylinderMesh.new()
	trunk.top_radius = trunk_bottom * 0.45
	trunk.bottom_radius = trunk_bottom
	trunk.height = trunk_height
	trunk.radial_segments = 7
	trunk.rings = 1
	parts.append([trunk, _xform(Vector3(0, trunk_height * 0.5, 0)), trunk_color])

	# 针叶冠：4~6 层，越往上越窄越小，彼此交叠
	var layers := rng.randi_range(4, 6)
	var base_y := trunk_height * 0.36
	var base_radius := rng.randf_range(1.9, 2.4)
	var layer_height := rng.randf_range(2.0, 2.5)
	# 层间距要小于层高，否则每层底盘会露出来，像叠盘子
	var step := layer_height * 0.44

	for i in layers:
		var t := float(i) / float(layers)
		var radius := lerpf(base_radius, 0.42, pow(t, 0.85))
		var height := lerpf(layer_height, 1.6, t)
		var y := base_y + float(i) * step
		# 每层轻微错位，轮廓不再是一圈圈同心圆锥；上层收拢避免尖头脱节
		var spread := 0.18 * (1.0 - t)
		var offset := Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread))
		# 树冠下部偏暗、顶部偏亮
		var tint := foliage_color.lightened(0.05 * float(i))
		parts.append(_cone(radius, height, _xform(offset + Vector3(0, y, 0)), tint, 8))

	# 收尖
	parts.append(_cone(0.34, 1.3,
		_xform(Vector3(0, base_y + float(layers) * step, 0)), foliage_color.lightened(0.16), 6))

	# 枯枝：下段伸出两根
	for i in 2:
		var angle := rng.randf_range(0.0, TAU)
		var y := rng.randf_range(trunk_height * 0.42, trunk_height * 0.66)
		var length := rng.randf_range(0.9, 1.6)
		var dir := Vector3(cos(angle), -0.3, sin(angle)).normalized()
		var rot := Vector3(rad_to_deg(dir.y), rad_to_deg(atan2(dir.z, dir.x)), 0.0)
		parts.append(_cylinder(0.05, length,
			_xform(dir * length * 0.5 + Vector3(0, y, 0), rot), trunk_color.darkened(0.12), 5))

	return merge(parts)


## 白桦：浅色树干 + 几团圆润树冠。与松林混交能拉开树种层次。
static func make_birch_tree(bark_color: Color, leaf_color: Color, seed_value: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else 777

	var parts: Array = []
	var trunk_height := rng.randf_range(5.0, 6.2)

	# 树干
	parts.append(_cylinder(0.19, trunk_height, _xform(Vector3(0, trunk_height * 0.5, 0)), bark_color, 6))

	# 树皮斑纹
	for i in 3:
		var y := trunk_height * (0.22 + 0.24 * float(i))
		parts.append(_box(Vector3(0.4, 0.1, 0.4),
			_xform(Vector3(0, y, 0), Vector3(0, rng.randf_range(0.0, 180.0), 0)), bark_color.darkened(0.3)))

	# 树冠：几团压扁的球
	var crown_y := trunk_height * 0.84
	parts.append(_sphere(1.45, _xform(Vector3(0, crown_y, 0), Vector3.ZERO, Vector3(1.0, 0.8, 1.0)), leaf_color, 7))
	parts.append(_sphere(1.0, _xform(Vector3(0.78, crown_y - 0.38, 0.26), Vector3.ZERO, Vector3(1.0, 0.74, 1.0)),
		leaf_color.lightened(0.07), 7))
	parts.append(_sphere(0.9, _xform(Vector3(-0.72, crown_y - 0.22, -0.32), Vector3.ZERO, Vector3(1.0, 0.74, 1.0)),
		leaf_color.darkened(0.06), 7))
	parts.append(_sphere(0.8, _xform(Vector3(0.1, crown_y + 0.52, -0.4), Vector3.ZERO, Vector3(1.0, 0.8, 1.0)),
		leaf_color.lightened(0.03), 6))

	return merge(parts)


## 枯立木：只剩树干和光秃的枝条，森林里的死亡气息。
static func make_dead_tree(trunk_color: Color, seed_value: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else 4242

	var parts: Array = []
	var trunk_height := rng.randf_range(5.4, 7.2)
	var trunk_bottom := rng.randf_range(0.26, 0.38)
	var trunk := CylinderMesh.new()
	trunk.top_radius = trunk_bottom * 0.4
	trunk.bottom_radius = trunk_bottom
	trunk.height = trunk_height
	trunk.radial_segments = 6
	trunk.rings = 1
	parts.append([trunk, _xform(Vector3(0, trunk_height * 0.5, 0)), trunk_color])

	# 向上伸的枯枝
	var branches := rng.randi_range(3, 5)
	for i in branches:
		var angle := TAU * float(i) / float(branches) + rng.randf_range(-0.5, 0.5)
		var y := trunk_height * rng.randf_range(0.5, 0.92)
		var length := rng.randf_range(1.1, 2.1)
		var dir := Vector3(cos(angle), rng.randf_range(0.35, 0.8), sin(angle)).normalized()
		var rot := Vector3(rad_to_deg(dir.y), rad_to_deg(atan2(dir.z, dir.x)), 0.0)
		parts.append(_cylinder(0.06, length,
			_xform(dir * length * 0.5 + Vector3(0, y, 0), rot), trunk_color.lightened(0.08), 5))

	return merge(parts)


## 树桩：被砍断留下的断面与根部。
static func make_stump(seed_value: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else 3131

	var bark := Color(0.31, 0.23, 0.16)
	var parts: Array = []
	var radius := rng.randf_range(0.34, 0.48)
	var height := rng.randf_range(0.4, 0.68)

	parts.append(_cylinder(radius, height, _xform(Vector3(0, height * 0.5, 0)), bark, 8))
	# 浅色断面
	parts.append(_cylinder(radius * 0.92, 0.06, _xform(Vector3(0, height - 0.01, 0)), Color(0.55, 0.45, 0.32), 8))
	# 根部隆起
	for i in 3:
		var angle := TAU * float(i) / 3.0 + rng.randf_range(-0.4, 0.4)
		parts.append(_cone(radius * 0.45, radius * 0.9,
			_xform(Vector3(cos(angle) * radius * 0.8, 0.05, sin(angle) * radius * 0.8),
				Vector3(0, 0, 0)), bark.darkened(0.08), 5))

	return merge(parts)


## 一捆箭：掉落物外观。
static func make_arrow_bundle() -> ArrayMesh:
	var shaft := Color(0.45, 0.35, 0.22)
	var feather := Color(0.72, 0.68, 0.6)
	var parts: Array = []
	for i in 4:
		var offset := Vector3((float(i) - 1.5) * 0.05, 0.02, (float(i % 2) - 0.5) * 0.07)
		parts.append(_cylinder(0.011, 0.6, _xform(offset + Vector3(0, 0.02, 0), Vector3(90, 0, 0)), shaft, 5))
		parts.append(_box(Vector3(0.01, 0.1, 0.045), _xform(offset + Vector3(0, 0.06, 0.27)), feather))
	return merge(parts)


## 猎弓：握把 + 上下弓臂 + 弓弦 + 搭在弦上的箭。
##
## 造型按「从弓手视角看过去」设计：弓臂在 XY 平面内弯成一条弧，
## 弓弦是一条竖直线并落在弦心 x=0，举弓瞄准时弦正好压在屏幕中心，
## 弓身向左侧张开。弓臂上下各四段，倾角沿曲线切线递增。
static func make_bow() -> ArrayMesh:
	var parts: Array = _bow_frame_parts()
	parts.append(_box(Vector3(0.009, 1.32, 0.009), _xform(Vector3.ZERO), Color(0.8, 0.78, 0.72)))
	parts.append_array(_bow_arrow_parts())
	return merge(parts)


## 第一人称弓：弓身（弓把 + 上下弓臂），不含弓弦和箭。
##
## 第一人称持弓时，弓弦和箭要随蓄力单独移动，
## 所以把「静态的弓」拆成一张网格，弦和箭各自成节点。
##
## 尺寸刻意做得比现实中的长弓小：视图模型挂在相机前方约 0.9 m，
## 1.4 m 的真长弓在那个距离会占满整屏高度，读起来就是一根黑棍。
## 0.58 m 的短弓加上左手真人尺寸的手，比例才对得上。
static func make_bow_frame() -> ArrayMesh:
	return merge(_bow_frame_parts())


## 弓弦：一段沿 +Y 的细方柱，运行时按「弓梢 → 弦心」摆位。
##
## 上下两段各自摆位，拉弦时折成 V 形，静止时接成一条直线。
static func make_bow_string() -> ArrayMesh:
	return make_limb_mesh(Color(0.38, 0.355, 0.29))


## 搭在弦上的箭：箭尾在原点，沿 -Z 伸出。
##
## 单独成件，箭尾始终贴在弦上，箭尖指向视线前方。
static func make_bow_nocked_arrow() -> ArrayMesh:
	return merge(_bow_arrow_parts())


## 上半支弓臂的折线（弓把 → 弓梢）。
##
## 弓臂先向外弯，到最宽处再向内回勾出一个弓梢——
## 没有回勾的话，弓在屏幕上就是一根直棍，完全看不出是弓。
const BOW_LIMB_UPPER: Array[Vector2] = [
	Vector2(-0.115, 0.082),
	Vector2(-0.100, 0.124),
	Vector2(-0.074, 0.164),
	Vector2(-0.042, 0.198),
	Vector2(-0.006, 0.228),
	Vector2(0.012, 0.256),
	Vector2(-0.004, 0.280),
	Vector2(-0.030, 0.296),
]


static func _bow_frame_parts() -> Array:
	# 配色跟着场景走：森林是明亮的薄荷绿与雪白，
	# 深棕色的弓落在这套画面里就是一根黑棍，
	# 太浅又会被光照顶成奶白。
	#
	# 这几个值是「按实机渲染反推」出来的，不是拍脑袋：
	# 视图模型自带一盏主光 + 一盏轮廓光，再加上天空环境光，
	# 总照度比纯反射率高一大截，albedo 必须压得比肉眼想的更暗更艳，
	# 落到屏幕上才是暖木色而不是灰白塑料。
	var wood := Color(0.26, 0.125, 0.052)
	var wood_light := Color(0.35, 0.185, 0.082)
	var grip := Color(0.115, 0.075, 0.048)

	var parts: Array = []

	# 弓把：竖直的一段，外面缠一圈皮条
	parts.append(_box(Vector3(0.038, 0.15, 0.05), _xform(Vector3(-0.115, 0.0, 0.0)), wood))
	parts.append(_box(Vector3(0.05, 0.10, 0.062), _xform(Vector3(-0.115, 0.0, 0.0)), grip))
	# 弓把上下的「肩」：弓臂从这里长出去
	parts.append(_box(Vector3(0.052, 0.03, 0.066), _xform(Vector3(-0.108, 0.078, 0.0)), wood_light))
	parts.append(_box(Vector3(0.052, 0.03, 0.066), _xform(Vector3(-0.108, -0.078, 0.0)), wood_light))

	# 上下弓臂：同一组折线，镜像一份
	for i in BOW_LIMB_UPPER.size() - 1:
		var a := BOW_LIMB_UPPER[i]
		var b := BOW_LIMB_UPPER[i + 1]
		parts.append(_bow_limb_piece(a, b, wood))
		parts.append(_bow_limb_piece(Vector2(a.x, -a.y), Vector2(b.x, -b.y), wood))

	# 弓梢上的弦扣
	parts.append(_box(Vector3(0.022, 0.016, 0.032), _xform(Vector3(-0.030, 0.292, 0.0)), wood_light))
	parts.append(_box(Vector3(0.022, 0.016, 0.032), _xform(Vector3(-0.030, -0.292, 0.0)), wood_light))

	return parts


## 弓臂的一段：从 a 连到 b 的方柱，靠绕 Z 的旋转贴合曲线。
##
## 方柱的 +Y 要指向 b - a，所以角度是 atan2(-dx, dy)。
static func _bow_limb_piece(a: Vector2, b: Vector2, color: Color) -> Array:
	var delta := b - a
	var length := maxf(delta.length(), 0.001)
	var angle := rad_to_deg(atan2(-delta.x, delta.y))
	var mid := (a + b) * 0.5
	return _box(
		Vector3(0.032, length + 0.005, 0.034),
		_xform(Vector3(mid.x, mid.y, 0.0), Vector3(0.0, 0.0, angle)),
		color
	)


static func _bow_arrow_parts() -> Array:
	var shaft := Color(0.26, 0.13, 0.055)
	var head := Color(0.42, 0.45, 0.50)
	var feather := Color(0.66, 0.145, 0.075)
	var feather_alt := Color(0.55, 0.52, 0.44)

	var parts: Array = []
	# 箭杆：箭尾在原点，沿 -Z 伸出
	parts.append(_cylinder(0.013, 0.52, _xform(Vector3(0.0, 0.0, -0.26), Vector3(90, 0, 0)), shaft, 6))
	# 箭头
	parts.append(_cone(0.024, 0.07, _xform(Vector3(0.0, 0.0, -0.555), Vector3(-90, 0, 0)), head, 6))
	# 尾羽：三片扇形排开，颜色比箭杆亮
	#
	# 第一人称里箭是朝前指着的，正对镜头时几乎只剩一个点；
	# 全靠这圈又宽又亮的尾羽才认得出「这是一支箭」。
	for i in 3:
		parts.append(_box(
			Vector3(0.013, 0.078, 0.115),
			_xform(Vector3(0.0, 0.0, -0.06), Vector3(0.0, float(i) * 60.0, 0.0)),
			feather if i != 1 else feather_alt
		))
	return parts


## 肢体段：沿 +Y 从 0 长到 1 的方柱。
##
## 运行时用两点摆位：原点放在起点、+Y 对准终点、Y 轴缩放到两点距离，
## 手指、手臂、弓弦这类需要随姿势变形的部件都用它。
static func make_limb_mesh(color: Color) -> ArrayMesh:
	return merge([_box(Vector3(1, 1, 1), _xform(Vector3(0, 0.5, 0)), color)])


## 手臂：沿 +Y 从 0 长到 1 的八棱柱，肩端粗、腕端细。
##
## 用逐渐收细的八棱柱而不是方柱，第一人称里才像一条手臂，
## 而不是一块斜着插进画面的木板。
static func make_arm_mesh(color: Color) -> ArrayMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.36
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 1
	return merge([[mesh, _xform(Vector3(0, 0.5, 0)), color]])


## 第一人称手部：握拳，约 0.09 m 宽（视图模型里的真人手尺寸）。
##
## 原点是「被握住的那根杆的轴心」——杆沿网格的 X 轴穿过原点。
## 四根手指沿 X 并排，在 YZ 平面里绕着原点卷过去；
## 手背与手腕在 +Z，小臂接着往 +Z 伸出去。
##
## 这样「手和杆的关系」是几何上确定的：
## 把手按「X 对齐杆的轴向、Z 对齐小臂方向」摆好，
## 手指自然就包住了杆，不需要再单独调「手往哪儿放」。
##
## 不做手指分节——低多边形下细长的指节会变成一叠纸片，
## 比不画手指更怪。每根手指只留三段粗块，读起来是拳头就够了。
##
## 配色一律用「乘系数」而不是 Color.lightened()：
## lightened() 是往白色混，混完之后饱和度被冲掉，
## 深棕手套立刻变成一块灰砖——这正是第一版弓手看起来像贴图的原因。
static func make_player_hand(skin: Color) -> ArrayMesh:
	var parts: Array = []
	# 手背与掌根：贴在杆的 +Z 一侧
	parts.append(_box(Vector3(0.062, 0.058, 0.030), _xform(Vector3(0.0, 0.002, 0.036)), skin))
	# 指关节：让手背不是一块死方块
	parts.append(_box(Vector3(0.058, 0.014, 0.030), _xform(Vector3(0.0, 0.026, 0.020)), skin * 1.26))
	# 四根手指：从掌根的边缘绕到杆的另一侧
	#
	# 弧线半径 0.033 m：手指的内表面刚好贴住半径 0.022 m 的握把。
	for i in 4:
		var x := -0.0235 + float(i) * 0.0157
		for s in 3:
			var a := deg_to_rad(28.0 - float(s) * 58.0)
			parts.append(_box(
				Vector3(0.0145, 0.034, 0.017),
				_xform(
					Vector3(x, 0.033 * cos(a), 0.033 * sin(a)),
					Vector3(rad_to_deg(a) + 90.0, 0.0, 0.0)
				),
				skin * 1.12
			))
	# 拇指：横在手指外侧
	parts.append(_box(
		Vector3(0.024, 0.030, 0.026),
		_xform(Vector3(-0.029, 0.012, 0.026), Vector3(0.0, 0.0, 22.0)),
		skin * 0.90
	))
	parts.append(_box(
		Vector3(0.021, 0.026, 0.022),
		_xform(Vector3(-0.036, -0.010, 0.004), Vector3(0.0, 0.0, -34.0)),
		skin * 0.86
	))
	return merge(parts)


## 第一人称小臂：手腕在原点，沿 -Y 伸出去的一截袖子。
##
## 单独成件，不塞进手模——手臂要能单独摆方向。
## 现实里手离眼睛 1 m 以上就够不到肩膀了（弓挂在视线前方 1.15 m），
## 第一人称游戏都是这么「作弊」的：小臂从画面底边斜插进来，
## 让手有个锚点，看起来才像「人举着弓」而不是「弓浮在半空」。
##
## 形状刻意做成「两头细、中间粗」而不是一根等粗圆柱：
## 等粗圆柱在低多边形下只会读成一根管子，
## 有肌肉隆起和收窄的肘弯才像手臂。
##
## 长度（0.88 m）远超真人小臂，这是故意的：
## 弓挂在视线前 1.15 m 处，按比例伸到肩膀会超出臂长，
## 所以袖子必须一直延伸到画面外才不会被看到断口——
## 半空中断掉的管子比没有手臂更假。
static func make_player_forearm(sleeve_color: Color, cuff_color: Color) -> ArrayMesh:
	var parts: Array = []

	# 靠手腕的一小段：细
	parts.append(_taper(0.0135, 0.021, 0.22, _xform(Vector3(0.0, -0.11, 0.0)), sleeve_color))
	# 肘部一段：最粗，然后一路收细伸向画面外
	parts.append(_taper(0.021, 0.015, 0.66, _xform(Vector3(0.0, -0.55, 0.0)), sleeve_color))

	# 皮护腕：手腕处一圈，把手和袖子连成一件
	parts.append(_box(Vector3(0.046, 0.038, 0.046), _xform(Vector3(0.0, -0.020, 0.0)), cuff_color))
	parts.append(_box(Vector3(0.040, 0.011, 0.040), _xform(Vector3(0.0, -0.045, 0.0)), cuff_color * 0.80))
	# 袖口的第二道绑带：给手臂一个「这是布」而不是「这是管子」的读感
	parts.append(_box(Vector3(0.036, 0.010, 0.036), _xform(Vector3(0.0, -0.105, 0.0)), cuff_color * 0.62))

	return merge(parts)


## 两端半径不同的圆柱段：上端（+Y）在 top_radius，下端（-Y）在 bottom_radius。
static func _taper(top_radius: float, bottom_radius: float, height: float, xform: Transform3D, color: Color, segments: int = 8) -> Array:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return [mesh, xform, color]


## 玩家本体：躯干 + 腰 + 双腿 + 靴子。原点在脚下（与 Player 节点一致）。
##
## 第一人称游戏里低头看到的是自己的胸口和腿，
## 没有身体模型的话低头就是一片空洞——脚下的地面直接穿过去，
## 「我在哪」的空间感也就没了。
##
## 这里只做躯干和腿：手臂由弓的视图模型负责，
## 实体手臂在第一人称下永远看不见，加进来只会多一层穿插和阴影瑕疵。
##
## 尺寸约定：肩线落在 1.44 m，低于站立时的相机高度 1.62 m——
## 平视时身体完全在画面外，只有低头才会露出来。
##
## 刻意不画脖子：脖子就在下巴底下 6 cm 处，
## 低头时那一小块顶面会占满整个屏幕（实测是一整片肉色），
## 比没有身体更糟。肩膀做成两块略高于胸口的小方块，
## 低头看到的是「有起伏的肩膀 + 胸口」，而不是一块平板。
## 蹲下时整个身体按 Y 压缩（见 player.gd）。
static func make_player_body() -> ArrayMesh:
	var coat := Color(0.185, 0.205, 0.135)
	var coat_dark := Color(0.135, 0.15, 0.095)
	var trouser := Color(0.145, 0.145, 0.115)
	var leather := Color(0.115, 0.082, 0.055)

	var parts: Array = []

	# 胯 + 腰
	parts.append(_box(Vector3(0.32, 0.16, 0.22), _xform(Vector3(0.0, 0.97, 0.0)), coat_dark))
	parts.append(_box(Vector3(0.29, 0.12, 0.20), _xform(Vector3(0.0, 1.10, 0.0)), trouser))
	# 腰带
	parts.append(_box(Vector3(0.315, 0.05, 0.215), _xform(Vector3(0.0, 1.035, 0.0)), leather))

	# 胸：由下往上三段收窄。
	# 做成阶梯而不是一整块：低头时看到的是一个有起伏的胸口，
	# 而不是一块铺满屏幕的平板（实测一整块时画面像贴了张墙）。
	parts.append(_box(Vector3(0.36, 0.13, 0.23), _xform(Vector3(0.0, 1.195, 0.0)), coat))
	parts.append(_box(Vector3(0.32, 0.10, 0.215), _xform(Vector3(0.0, 1.31, 0.0)), coat))
	parts.append(_box(Vector3(0.26, 0.08, 0.19), _xform(Vector3(0.0, 1.40, 0.0)), coat))
	# 肩：略低于胸口正中，两侧各一块
	parts.append(_box(Vector3(0.09, 0.11, 0.18), _xform(Vector3(-0.165, 1.375, 0.0)), coat))
	parts.append(_box(Vector3(0.09, 0.11, 0.18), _xform(Vector3(0.165, 1.375, 0.0)), coat))

	# 斜挎的背带：给胸口一个非对称的细节，避免纯色方块。
	# 上沿必须低于胸口顶面，否则会变成一块悬在肩膀上方的浮板。
	parts.append(_box(Vector3(0.06, 0.35, 0.02), _xform(Vector3(-0.05, 1.205, 0.116), Vector3(0, 0, 13)), leather))

	# 双腿：大腿 + 小腿 + 靴子。
	# 小腿和脚掌比胯往前探一截：胸口比眼睛只低十几厘米，
	# 不往前探的话小腿整段被胸口挡住，低头只看得见两只悬空的靴子。
	for i in 2:
		var x := -0.085 if i == 0 else 0.085
		parts.append(_taper(0.082, 0.068, 0.42, _xform(Vector3(x, 0.68, -0.02)), trouser, 6))
		parts.append(_taper(0.068, 0.052, 0.36, _xform(Vector3(x, 0.31, -0.095)), trouser, 6))
		parts.append(_box(Vector3(0.112, 0.14, 0.235), _xform(Vector3(x, 0.07, -0.135)), leather))

	return merge(parts)


## 箭矢：细杆 + 箭头 + 尾羽。
##
## 和搭在弦上的箭共用同一份零件（_bow_arrow_parts）：
## 玩家看到的那支箭和射出去的那支必须是同一个东西，
## 两套各画各的，射击瞬间就会「换了一支箭」。
##
## 箭尾在原点、箭头朝 -Z（Godot 的「前方」），投射物可以直接用 look_at 对齐飞行方向。
static func make_arrow() -> ArrayMesh:
	return merge(_bow_arrow_parts())


## 林狼的躯干（不含四肢，便于单独摆动）。
##
## 配色刻意压深并加背部深色鞍纹：浅灰狼落在浅色地面上会糊成一团，
## 玩家分不清那是什么，也就没有威胁感。
static func make_wolf_body(fur: Color, belly: Color) -> ArrayMesh:
	var parts: Array = []
	# 躯干
	parts.append(_box(Vector3(0.42, 0.42, 1.05), _xform(Vector3(0, 0.62, 0)), fur))
	# 背部深色鞍纹
	parts.append(_box(Vector3(0.38, 0.1, 0.92), _xform(Vector3(0, 0.81, 0.02)), fur.darkened(0.3)))
	# 胸腹略浅
	parts.append(_box(Vector3(0.36, 0.18, 0.9), _xform(Vector3(0, 0.5, 0)), belly))
	# 颈与头
	parts.append(_box(Vector3(0.26, 0.26, 0.34), _xform(Vector3(0, 0.7, -0.6)), fur))
	parts.append(_box(Vector3(0.28, 0.26, 0.4), _xform(Vector3(0, 0.74, -0.86)), fur))
	# 吻部
	parts.append(_box(Vector3(0.16, 0.14, 0.26), _xform(Vector3(0, 0.68, -1.12)), fur.lightened(0.06)))
	# 耳
	parts.append(_cone(0.08, 0.16, _xform(Vector3(0.1, 0.92, -0.76)), fur.darkened(0.2), 4))
	parts.append(_cone(0.08, 0.16, _xform(Vector3(-0.1, 0.92, -0.76)), fur.darkened(0.2), 4))
	# 尾
	parts.append(_box(Vector3(0.12, 0.12, 0.45), _xform(Vector3(0, 0.66, 0.66), Vector3(-18, 0, 0)), fur.darkened(0.12)))
	# 眼睛：近黑的小方块，凑近能分辨朝向
	parts.append(_box(Vector3(0.05, 0.045, 0.03), _xform(Vector3(0.085, 0.79, -1.05)), Color(0.06, 0.05, 0.05)))
	parts.append(_box(Vector3(0.05, 0.045, 0.03), _xform(Vector3(-0.085, 0.79, -1.05)), Color(0.06, 0.05, 0.05)))
	return merge(parts)


## 狼的腿（单独一件，便于运行时摆动）。
static func make_wolf_leg(fur: Color) -> ArrayMesh:
	var parts: Array = []
	parts.append(_box(Vector3(0.11, 0.52, 0.11), _xform(Vector3(0, 0.26, 0)), fur))
	parts.append(_box(Vector3(0.13, 0.08, 0.16), _xform(Vector3(0, 0.04, -0.02)), fur.darkened(0.12)))
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


## 帐篷：三棱柱帆布 + 门帘 + 脊杆 + 前方支柱。
static func make_tent() -> ArrayMesh:
	var canvas := Color(0.3, 0.33, 0.25)
	var pole := Color(0.36, 0.27, 0.19)
	var parts: Array = []
	parts.append(_prism(Vector3(2.4, 1.55, 2.2), _xform(Vector3(0, 0.78, 0), Vector3(0, 90, 0)), canvas))
	# 门帘：深色三角面，贴在入口一侧
	parts.append(_prism(Vector3(1.0, 1.2, 0.06), _xform(Vector3(0, 0.6, 1.22), Vector3(0, 90, 0)), Color(0.15, 0.15, 0.12)))
	# 脊杆
	parts.append(_cylinder(0.05, 2.3, _xform(Vector3(0, 1.53, 0), Vector3(0, 0, 90)), pole, 5))
	# 前方支柱与地布
	parts.append(_cylinder(0.05, 1.95, _xform(Vector3(0, 0.98, 1.16)), pole, 5))
	parts.append(_box(Vector3(0.9, 0.05, 1.0), _xform(Vector3(0, 0.04, 1.45)), pole.darkened(0.12)))
	# 两端的捆绳桩
	parts.append(_cylinder(0.04, 0.5, _xform(Vector3(-1.15, 0.25, 1.3)), pole.darkened(0.05), 5))
	parts.append(_cylinder(0.04, 0.5, _xform(Vector3(1.15, 0.25, 1.3)), pole.darkened(0.05), 5))
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


## 倒木：横卧在林地里的枯木。seed 变化时长度、断面与断枝位置随之变化。
static func make_fallen_log(seed_value: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else 6060

	var bark := Color(0.29, 0.21, 0.15)
	var parts: Array = []
	var length := rng.randf_range(4.6, 7.2)
	var radius := rng.randf_range(0.46, 0.66)

	parts.append(_cylinder(radius, length, _xform(Vector3(0, radius, 0), Vector3(0, 0, 90)), bark, 10))
	# 断面
	parts.append(_cylinder(radius * 0.82, 0.12,
		_xform(Vector3(length * 0.5, radius, 0), Vector3(0, 0, 90)), Color(0.55, 0.46, 0.33), 10))
	# 断枝
	for i in 2:
		var offset := rng.randf_range(-length * 0.3, length * 0.3)
		parts.append(_cylinder(0.09, rng.randf_range(0.8, 1.3),
			_xform(Vector3(offset, radius + 0.3, 0.2), Vector3(rng.randf_range(40.0, 75.0), 0, 0)),
			bark.darkened(0.12), 6))
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


## 按名称取道具网格，供可交互物脚本使用。
##
## 这是 §4.1 里 `make_prop` 接缝的**唯一真相源**：16 个道具键都在这里注册。
## 营地装配处原本直接调 `make_cabin()` 这类函数（`direct` 接缝），
## 那样运行时没有字符串键可查，管线产的 GLB 接不上——补齐注册表就是为了消掉这个缺口。
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
		&"cabin":
			return make_cabin()
		&"cabin_windows":
			return make_cabin_windows()
		&"supply_shed":
			return make_supply_shed()
		&"target":
			return make_target()
		&"lantern_glass":
			return make_lantern_glass()
	return null


# ------------------------------------------------------------------ 异常守护者

## 异常守护者的躯干：高瘦的人形，轮廓与林狼完全不同。
##
## 配色一律用乘系数，不用 Color.lightened()：lightened() 是往白色混，
## 混完饱和度被冲掉，深灰绿立刻变成一块灰砖。
static func make_guardian_body(body_color: Color) -> ArrayMesh:
	var parts: Array = []
	var dark := body_color * 0.85
	var limb := body_color * 0.92

	# 躯干：上窄下宽的反锥
	parts.append(_taper(0.30, 0.44, 1.45, _xform(Vector3(0.0, 1.42, 0.0)), body_color, 8))
	# 肩
	parts.append(_box(Vector3(0.94, 0.20, 0.32), _xform(Vector3(0.0, 2.04, 0.0)), limb))
	# 头：略微前倾，像在盯着什么东西
	parts.append(_box(Vector3(0.34, 0.40, 0.32),
		_xform(Vector3(0.0, 2.38, -0.04), Vector3(8, 0, 0)), body_color * 0.88))
	# 手臂：贴身下垂
	parts.append(_cylinder(0.085, 1.20, _xform(Vector3(-0.52, 1.44, 0.0)), limb, 6))
	parts.append(_cylinder(0.085, 1.20, _xform(Vector3(0.52, 1.44, 0.0)), limb, 6))
	# 腿
	parts.append(_cylinder(0.125, 1.18, _xform(Vector3(-0.19, 0.59, 0.0)), dark, 6))
	parts.append(_cylinder(0.125, 1.18, _xform(Vector3(0.19, 0.59, 0.0)), dark, 6))
	return merge(parts)


## 异常守护者背上的结晶簇。弱点就在这里，用自发光材质单独渲染。
##
## Godot 的前方是 -Z，背面是 +Z，所以结晶挂在 +Z 一侧。
## 结晶根部在 y ≈ 1.62，高于 weak_point_height，保证弱点判定落在它身上。
static func make_guardian_crystal() -> ArrayMesh:
	var parts: Array = []
	var c := Color(0.40, 0.76, 0.82)
	var c_dark := c * 0.72

	# 三根长短不一的棱柱，斜插在背上
	parts.append(_prism(Vector3(0.13, 0.52, 0.11),
		_xform(Vector3(-0.13, 1.82, 0.30), Vector3(-16, 0, 10)), c))
	parts.append(_prism(Vector3(0.15, 0.70, 0.12),
		_xform(Vector3(0.02, 1.88, 0.33), Vector3(-12, 0, -3)), c))
	parts.append(_prism(Vector3(0.10, 0.38, 0.09),
		_xform(Vector3(0.15, 1.72, 0.28), Vector3(-20, 0, 14)), c_dark))
	# 根部一圈暗色结晶座，把棱柱和躯干连起来
	parts.append(_sphere(0.19, _xform(Vector3(0.0, 1.62, 0.26)), c_dark, 6))
	return merge(parts)


# ------------------------------------------------------------------ 猎人营地遗址

## 倒塌的帐篷骨架。只剩下两根撑杆和一块塌在地上的布。
static func make_collapsed_tent() -> ArrayMesh:
	var parts: Array = []
	var pole := Color(0.32, 0.26, 0.18)
	var canvas := Color(0.26, 0.24, 0.19)

	# 两根斜撑的主杆
	parts.append(_cylinder(0.045, 1.9, _xform(Vector3(-0.5, 0.42, 0.0), Vector3(0, 0, 62)), pole, 5))
	parts.append(_cylinder(0.045, 1.9, _xform(Vector3(0.5, 0.42, 0.0), Vector3(0, 0, -58)), pole, 5))
	# 掉在地上的断杆
	parts.append(_cylinder(0.04, 1.5, _xform(Vector3(0.15, 0.05, 0.35), Vector3(90, 20, 0)), pole, 5))
	# 塌下来的布幔
	parts.append(_box(Vector3(1.25, 0.05, 0.95),
		_xform(Vector3(0.1, 0.12, 0.1), Vector3(-18, 12, 0)), canvas))
	return merge(parts)


## 翻倒的捕兽夹。爪子还张着，弹簧已经锈了。
static func make_trap() -> ArrayMesh:
	var parts: Array = []
	var iron := Color(0.26, 0.25, 0.23)
	var rust := Color(0.34, 0.22, 0.14)

	parts.append(_box(Vector3(0.42, 0.04, 0.42), _xform(Vector3(0.0, 0.02, 0.0)), rust))
	parts.append(_prism(Vector3(0.06, 0.34, 0.30),
		_xform(Vector3(-0.13, 0.16, 0.0), Vector3(0, 0, 26)), iron))
	parts.append(_prism(Vector3(0.06, 0.34, 0.30),
		_xform(Vector3(0.13, 0.16, 0.0), Vector3(0, 0, -26)), iron))
	parts.append(_cylinder(0.035, 0.22,
		_xform(Vector3(0.0, 0.10, -0.12), Vector3(90, 0, 0)), iron, 6))
	return merge(parts)


## 熄灭已久的火塘。石圈还在，中间只剩一层灰。
static func make_dead_campfire() -> ArrayMesh:
	var parts: Array = []
	var stone := Color(0.34, 0.32, 0.29)
	var ash := Color(0.24, 0.22, 0.21)
	var charred := Color(0.16, 0.13, 0.12)

	for i in 7:
		var angle := TAU * float(i) / 7.0
		parts.append(_sphere(0.14,
			_xform(Vector3(cos(angle) * 0.42, 0.06, sin(angle) * 0.42), Vector3.ZERO,
				Vector3(1.0, 0.75, 1.0)), stone, 6))
	parts.append(_sphere(0.30,
		_xform(Vector3(0.0, 0.03, 0.0), Vector3.ZERO, Vector3(1.0, 0.22, 1.0)), ash, 7))
	parts.append(_cylinder(0.045, 0.5,
		_xform(Vector3(0.05, 0.06, 0.02), Vector3(0, 24, 86)), charred, 5))
	parts.append(_cylinder(0.04, 0.42,
		_xform(Vector3(-0.06, 0.05, -0.04), Vector3(0, -40, 78)), charred, 5))
	return merge(parts)


## 丢下的背包。盖子没扣严。
static func make_backpack() -> ArrayMesh:
	var parts: Array = []
	var leather := Color(0.30, 0.21, 0.14)
	var strap := Color(0.20, 0.15, 0.10)

	parts.append(_box(Vector3(0.34, 0.42, 0.24), _xform(Vector3(0.0, 0.21, 0.0)), leather))
	parts.append(_box(Vector3(0.35, 0.10, 0.26),
		_xform(Vector3(0.0, 0.44, 0.01), Vector3(-8, 0, 0)), leather * 1.15))
	parts.append(_box(Vector3(0.05, 0.34, 0.03), _xform(Vector3(-0.09, 0.24, -0.13)), strap))
	parts.append(_box(Vector3(0.05, 0.34, 0.03), _xform(Vector3(0.09, 0.24, -0.13)), strap))
	return merge(parts)


## 插在地上的标箭。猎人用它标记走过的路。
static func make_marker_arrow() -> ArrayMesh:
	var parts: Array = []
	var shaft := Color(0.28, 0.19, 0.11)
	var feather := Color(0.52, 0.22, 0.14)

	parts.append(_cylinder(0.018, 0.72, _xform(Vector3(0.0, 0.36, 0.0)), shaft, 5))
	parts.append(_box(Vector3(0.09, 0.14, 0.02), _xform(Vector3(0.0, 0.62, 0.0)), feather))
	return merge(parts)


# ------------------------------------------------------------------ 溪流

## 溪流里的踩石。猎人铺的过河通路，涨水时会没顶。
##
## 是一块齐平的石板：底面坐在河床 -1.15，顶面在 -0.42，
## 平常水面 -0.94 时露出 0.52 m，涨水到 +0.15 时整个没顶。
static func make_stepping_stone(seed_value: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else 3311

	var parts: Array = []
	var stone := Color(0.33, 0.31, 0.28)
	var wet := stone * 0.78

	parts.append(_box(Vector3(0.62, 0.72, 0.54),
		_xform(Vector3(0.0, 0.0, 0.0), Vector3(0.0, rng.randf_range(-18.0, 18.0), 0.0)), stone))
	# 泡在水里的那一截，颜色更深
	parts.append(_box(Vector3(0.58, 0.30, 0.50),
		_xform(Vector3(0.0, -0.21, 0.0)), wet))
	return merge(parts)


## 夜间发光植物：顶端结着发光花苞的一丛芽。
##
## 整个网格都是自发光材质，茎和花苞一起亮。
## 这只在夜里出现，白天事件根本不触发，所以不用区分茎与苞。
static func make_glow_sprout() -> ArrayMesh:
	var parts: Array = []
	var bud := Color(0.50, 0.84, 0.88)

	parts.append(_sphere(0.050, _xform(Vector3(0.0, 0.18, 0.0)), bud, 6))
	parts.append(_sphere(0.035, _xform(Vector3(-0.05, 0.12, 0.01)), bud * 0.85, 5))
	parts.append(_sphere(0.032, _xform(Vector3(0.05, 0.11, -0.02)), bud * 0.85, 5))
	parts.append(_cylinder(0.010, 0.16, _xform(Vector3(0.0, 0.06, 0.0)), bud * 0.45, 4))
	return merge(parts)
