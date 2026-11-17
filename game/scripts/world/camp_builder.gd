class_name CampBuilder
extends Node3D
## 营地的人工地标：木屋、物资棚、发电机、训练靶场、倒木、路牌、远景山体。
##
## 与 VegetationScatter 的分工（docs/content-pipeline.md §2）：
## 自然环境可重新生成，人工地标不自动覆盖。

signal props_built()

@export var camp_seed: int = 90210

var _height_provider: Node = null


func build(height_provider: Node) -> void:
	_height_provider = height_provider

	_place_cabin()
	_place_supply_shed()
	_place_generator()
	_place_training_range()
	_place_fallen_log()
	_place_signpost()
	_place_camp_details()
	_place_creek()
	_place_backdrop()
	_place_camp_glow()

	props_built.emit()
	GameLog.info("营地步道完成")


# ------------------------------------------------------------------ 道具

func _add_prop(node_name: String, mesh: Mesh, position: Vector2, rotation_y: float,
		solid_size: Vector3 = Vector3.ZERO) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.rotation.y = deg_to_rad(rotation_y)
	add_child(root)

	if mesh != null:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.material_override = PropKit.painted_material()
		root.add_child(mesh_instance)

	if solid_size != Vector3.ZERO:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0

		var shape := BoxShape3D.new()
		shape.size = solid_size

		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		root.add_child(body)

	root.position = Vector3(position.x, _ground(position.x, position.y), position.y)
	return root


func _ground(x: float, z: float) -> float:
	if _height_provider == null or not _height_provider.has_method("height_at"):
		return 0.0
	return float(_height_provider.call("height_at", x, z))


# ------------------------------------------------------------------ 各建筑

func _place_cabin() -> void:
	var position := Vector2(-8.0, -7.0)
	var cabin := _add_prop("Cabin", PropKit.make_cabin(), position, 12.0, Vector3(6.0, 3.4, 5.0))

	# 窗玻璃单独一层，用自发光材质
	var windows := MeshInstance3D.new()
	windows.name = "Windows"
	windows.mesh = PropKit.make_cabin_windows()
	windows.material_override = PropKit.glow_material(Color(1.0, 0.72, 0.38), 2.4)
	cabin.add_child(windows)

	# 屋内暖光，从门口漏出来
	var interior := OmniLight3D.new()
	interior.name = "InteriorLight"
	interior.light_color = Color(1.0, 0.74, 0.44)
	interior.light_energy = 2.6
	interior.omni_range = 11.0
	interior.shadow_enabled = false
	interior.position = Vector3(0.0, 2.0, 0.4)
	cabin.add_child(interior)

	# 门前一小片踏实的地面
	var doorstep := _add_prop("Doorstep", null, position + Vector2(0.0, 3.2), 12.0)
	var pad := MeshInstance3D.new()
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(2.4, 0.08, 1.6)
	pad.mesh = pad_mesh
	pad.material_override = PropKit.painted_material()
	doorstep.add_child(pad)


func _place_supply_shed() -> void:
	_add_prop("SupplyShed", PropKit.make_supply_shed(), Vector2(-13.5, -1.5), -22.0, Vector3(3.0, 2.5, 2.4))


func _place_generator() -> void:
	var position := Vector2(-4.2, -2.6)
	var generator := _add_prop("Generator", PropKit.make_generator(), position, 24.0, Vector3(1.7, 1.1, 1.2))

	# 指示灯
	var indicator := MeshInstance3D.new()
	indicator.name = "Indicator"
	var bulb := SphereMesh.new()
	bulb.radius = 0.06
	bulb.height = 0.12
	bulb.radial_segments = 6
	bulb.rings = 3
	indicator.mesh = bulb
	indicator.material_override = PropKit.glow_material(Color(0.4, 1.0, 0.5), 4.0)
	indicator.position = Vector3(-0.3, 0.62, 0.42)
	generator.add_child(indicator)

	var glow := OmniLight3D.new()
	glow.name = "IndicatorLight"
	glow.light_color = Color(0.45, 1.0, 0.6)
	glow.light_energy = 0.9
	glow.omni_range = 3.2
	glow.position = Vector3(-0.3, 0.7, 0.5)
	generator.add_child(glow)


func _place_training_range() -> void:
	# 三个靶子排成一线
	for i in 3:
		var offset := Vector2(8.5 + float(i) * 1.6, -9.5)
		_add_prop("Target%02d" % (i + 1), PropKit.make_target(), offset, 165.0, Vector3(0.2, 1.6, 0.2))

	# 一道矮木栅栏，界定靶场
	for i in 6:
		var offset := Vector2(7.4 + float(i) * 1.55, -6.6)
		_add_prop("Fence%02d" % (i + 1), null, offset, 0.0, Vector3(0.16, 0.9, 0.16))


func _place_fallen_log() -> void:
	# 松木深林入口的倒木，作为天然入口标记
	_add_prop("FallenLog", PropKit.make_fallen_log(), Vector2(1.5, -24.0), 28.0, Vector3(6.5, 1.3, 1.3))


func _place_signpost() -> void:
	_add_prop("Signpost", PropKit.make_signpost(), Vector2(4.2, 3.4), -35.0, Vector3(0.22, 1.9, 0.22))


## 营地生活痕迹：帐篷、灯柱、柴堆、木桶。
func _place_camp_details() -> void:
	_place_tent()
	_place_lantern_post()
	_place_woodpile()
	_place_barrels()


## 帐篷：有人驻扎过的痕迹。放在木屋一侧，不挡出生点视线。
func _place_tent() -> void:
	_add_prop("Tent", PropKit.make_tent(), Vector2(-10.5, 4.5), 24.0, Vector3(2.4, 1.6, 2.2))


## 灯柱：天黑后给营地补一点暖光。
func _place_lantern_post() -> void:
	var post := _add_prop("LanternPost", PropKit.make_lantern_post(),
		Vector2(3.4, 4.6), -24.0, Vector3(0.3, 2.4, 0.3))

	var glass := MeshInstance3D.new()
	glass.name = "LanternGlass"
	glass.mesh = PropKit.make_lantern_glass()
	glass.material_override = PropKit.glow_material(Color(1.0, 0.78, 0.45), 3.0)
	post.add_child(glass)

	var light := OmniLight3D.new()
	light.name = "LanternLight"
	light.light_color = Color(1.0, 0.78, 0.45)
	light.light_energy = 1.5
	light.omni_range = 8.0
	light.shadow_enabled = false
	light.position = Vector3(0.2, 2.2, 0.0)
	post.add_child(light)


## 柴堆：木屋旁的备用燃料。
func _place_woodpile() -> void:
	_add_prop("Woodpile", PropKit.make_woodpile(), Vector2(-10.8, -4.6), 24.0, Vector3(1.6, 0.9, 0.7))


## 木桶：分布在木屋旁与溪边。
func _place_barrels() -> void:
	_add_prop("Barrel01", PropKit.make_barrel(), Vector2(-6.2, -9.8), 12.0, Vector3(0.7, 0.9, 0.7))
	_add_prop("Barrel02", PropKit.make_barrel(), Vector2(10.6, 1.8), -30.0, Vector3(0.7, 0.9, 0.7))


## 溪流水面：地形已挖出固定河床，这里铺一层半透明水面。
func _place_creek() -> void:
	var water := MeshInstance3D.new()
	water.name = "CreekWater"

	var mesh := BoxMesh.new()
	mesh.size = Vector3(5.2, 0.12, 62.0)
	water.mesh = mesh
	water.material_override = PropKit.water_material()
	water.position = Vector3(11.0, -1.0, 0.0)
	add_child(water)

	# 河床两侧的碎石
	var rng := RandomNumberGenerator.new()
	rng.seed = camp_seed + 41
	for i in 18:
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var position := Vector2(11.0 + side * rng.randf_range(2.6, 4.4), rng.randf_range(-28.0, 28.0))
		_add_prop("CreekRock%02d" % i, PropKit.make_rock(camp_seed + 100 + i),
			position, rng.randf_range(0.0, 360.0), Vector3(0.6, 0.5, 0.6))


func _place_backdrop() -> void:
	var hills := MeshInstance3D.new()
	hills.name = "BackdropHills"
	hills.mesh = PropKit.make_backdrop_hills(camp_seed)
	hills.material_override = PropKit.painted_material()
	hills.position = Vector3(0.0, -4.0, 0.0)
	add_child(hills)


func _place_camp_glow() -> void:
	# 营地的整体暖光，保证夜里安全区与其他区域有冷暖对比
	var glow := OmniLight3D.new()
	glow.name = "CampGlow"
	glow.light_color = Color(1.0, 0.76, 0.48)
	glow.light_energy = 1.1
	glow.omni_range = 26.0
	glow.omni_attenuation = 1.6
	glow.shadow_enabled = false
	glow.position = Vector3(0.0, 4.0, 0.0)
	add_child(glow)
