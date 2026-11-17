extends Node
## 临时探针：把持弓模型每个部件的世界坐标与屏幕坐标打印出来。
##
## 肉眼分不清「哪个色块是左手、哪个是尾羽」，靠坐标说话。
## 用完即删。

func _ready() -> void:
	var main := get_node_or_null("Main")
	if main == null:
		get_tree().quit(1)
		return
	for i in 4:
		await get_tree().process_frame

	var camera: Camera3D = main.get_node_or_null("Player/Head/Camera3D")
	var view := camera.get_node_or_null("BowViewModel") as Node3D
	if view == null:
		print("PROBE: 没有 BowViewModel")
		get_tree().quit(1)
		return

	print("PROBE: viewport=%s fov=%.1f" % [get_viewport().get_visible_rect().size, camera.fov])

	var player: Player = main.get("player")
	player.capture_mouse()
	Input.action_press("aim")
	await get_tree().process_frame
	Input.action_press("fire")
	for i in 24:
		await get_tree().process_frame
	print("PROBE: --- 举弓蓄力姿态 ---")

	for path in ["BowPivot/BowFrame", "BowPivot/LeftHand", "BowPivot/RightHand",
			"BowPivot/StringTop", "BowPivot/StringBottom", "NockedArrow"]:
		var node := view.get_node_or_null(path)
		if node == null:
			print("PROBE: %s 缺失" % path)
			continue
		var mi := node as MeshInstance3D
		var world := mi.global_position
		var screen := camera.unproject_position(world)
		var aabb := mi.get_aabb()
		print("PROBE: %-24s world=(%.3f,%.3f,%.3f) screen=(%.0f,%.0f) aabb_size=(%.3f,%.3f,%.3f)" % [
			path, world.x, world.y, world.z, screen.x, screen.y,
			aabb.size.x, aabb.size.y, aabb.size.z
		])

	# 顶点色是不是真的写进去了
	for path in ["BowPivot/LeftHand", "BowPivot/BowFrame"]:
		var mi := view.get_node_or_null(path) as MeshInstance3D
		if mi == null:
			continue
		var arrays := mi.mesh.surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var mat := mi.material_override as StandardMaterial3D
		print("PROBE: %s 顶点数=%d 顶点色[0]=%s 材质顶点色开关=%s albedo=%s" % [
			path, colors.size(),
			str(colors[0]) if colors.size() > 0 else "无",
			str(mat.vertex_color_use_as_albedo) if mat != null else "无材质",
			str(mat.albedo_color) if mat != null else "-"
		])

	# 直接在画面上按部件位置回采像素：颜色到底是多少，一目了然
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	for path in ["BowPivot/BowFrame", "BowPivot/LeftHand", "BowPivot/RightHand", "NockedArrow"]:
		var mi := view.get_node_or_null(path) as MeshInstance3D
		if mi == null:
			continue
		var screen := camera.unproject_position(mi.global_position)
		var px := int(screen.x)
		var py := int(screen.y)
		var c := image.get_pixel(px, py)
		print("PROBE: 采样 %-22s @(%d,%d) -> RGB(%.2f,%.2f,%.2f)" % [path, px, py, c.r, c.g, c.b])

	Input.action_release("fire")
	Input.action_release("aim")
	player.release_mouse()
	get_tree().quit(0)
