extends Node3D
## 生成资产的对比截图：管线产的 pine_0 与 PropKit 程序化的 pine_1 并排。
##
## 用法：godot --path game res://tests/capture_asset.tscn
## 输出：build/screenshots/asset_compare.png
##
## 存在的理由：GLB 的结构可以靠数字验证（COLOR_0、Y-up、min.y=0、三角面数），
## 但「看起来像不像树」「和现有林子搭不搭」只能靠眼睛。
##
## 这个场景**不挂 Main**：独立布光与地面，避免营地植被挡住视线。

const OUT_DIR := "res://../build/screenshots"

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	# 地面：只为了看出树根落在哪里
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	ground.mesh = plane
	ground.position = Vector3(0.0, 0.0, 0.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.16, 0.24, 0.13)
	ground_material.roughness = 0.95
	ground.material_override = ground_material
	add_child(ground)

	var generated := AssetLibrary.mesh_for("pine_0")
	var procedural := PropKit.make_pine_tree(
		Color(0.27, 0.19, 0.14), Color(0.15, 0.29, 0.17), 20261117 + 131 * 2)
	if generated == null:
		push_error("AssetLibrary 取不到 pine_0——先跑 tools/forest_generator/main.py --build")
		get_tree().quit(1)
		return

	var pairs := [
		{"mesh": generated, "x": -2.8, "tag": "pipeline"},
		{"mesh": procedural, "x": 2.8, "tag": "propkit"},
	]
	for pair in pairs:
		var instance := MeshInstance3D.new()
		instance.mesh = pair["mesh"]
		instance.material_override = PropKit.swaying_material()
		instance.position = Vector3(float(pair["x"]), 0.0, 0.0)
		add_child(instance)
		var aabb: AABB = (pair["mesh"] as Mesh).get_aabb()
		print("SHOWCASE %s height=%.2f width=%.2f min_y=%.3f" % [
			pair["tag"], aabb.size.y, aabb.size.x, aabb.position.y,
		])

	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("无法取得渲染结果")
		get_tree().quit(1)
		return
	var path := ProjectSettings.globalize_path(OUT_DIR + "/asset_compare.png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if image.save_png(path) != OK:
		push_error("截图写入失败：%s" % path)
		get_tree().quit(1)
		return
	print("SHOT asset_compare %s" % path)
	get_tree().quit(0)
