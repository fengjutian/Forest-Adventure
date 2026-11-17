extends Node
## 弓的第一人称表现预览：单独出「垂弓」和「举弓蓄力」两张图。
##
## 用法：godot --path game res://tests/capture_bow.tscn
##
## 迭代弓的构图时用这个，比跑整套战斗截图快得多：
## 弓的位置、比例、配色、箭的可见性，全在这两张图上一眼能看出来。
## 注意：必须使用带图形后端的 Godot（不能 --headless），否则拿到的是空帧。

const OUT_DIR := "res://../build/screenshots"


func _ready() -> void:
	var main := get_node_or_null("Main")
	if main == null:
		push_error("找不到 Main 场景")
		get_tree().quit(1)
		return

	for i in 4:
		await get_tree().process_frame

	# 按键提示会盖住画面右侧，预览时先收起
	var hud := main.get_node_or_null("UI") as HUD
	if hud != null:
		hud.close_controls_hint()

	var player: Player = main.get("player")
	var camera: Camera3D = main.get_node_or_null("Player/Head/Camera3D")
	if player == null or camera == null:
		push_error("找不到玩家或相机")
		get_tree().quit(1)
		return
	camera.current = true

	_place(player)

	# 1) 垂弓：没举弓时的日常姿势
	await _settle(20)
	await _shot(OUT_DIR + "/bow_hip.png")

	# 2) 举弓蓄力：拉满弦的样子
	player.capture_mouse()
	Input.action_press("aim")
	await _settle(14)
	Input.action_press("fire")
	await _settle(28)
	await _shot(OUT_DIR + "/bow_aim.png")
	Input.action_release("fire")
	Input.action_release("aim")
	player.release_mouse()

	get_tree().quit(0)


## 站到林狼侧前方，视线略微下压——和战斗截图同一机位，方便前后对比。
func _place(player: Player) -> void:
	var wolf := _find_wolf()
	if wolf == null:
		player.global_position = Vector3(0.0, 0.0, 0.0)
		return

	var angle := deg_to_rad(38.0)
	var offset := Vector3(sin(angle), 0.0, cos(angle)) * 5.5
	var spot := wolf.global_position + offset
	spot.y = _ground_at(spot)

	player.global_position = spot
	player.velocity = Vector3.ZERO

	var look := wolf.global_position + Vector3(0.0, 0.75, 0.0)
	if player.has_method("look_at"):
		player.look_at(look, Vector3.UP)
	var head := player.get_node_or_null("Head") as Node3D
	if head != null:
		head.rotation_degrees = Vector3(-5.0, 0.0, 0.0)


func _find_wolf() -> EnemyBase:
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as EnemyBase
		if enemy != null:
			return enemy
	return null


func _ground_at(point: Vector3) -> float:
	var terrain := get_tree().get_first_node_in_group(&"terrain") as Node3D
	if terrain == null or not terrain.has_method("height_at"):
		return point.y
	return float(terrain.call("height_at", point.x, point.z))


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("无法取得渲染结果")
		return
	var absolute := ProjectSettings.globalize_path(file_name)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var err := image.save_png(absolute)
	if err != OK:
		push_error("截图写入失败：%s（错误 %d）" % [absolute, err])
		return
	print("SCREENSHOT_SAVED:%s %dx%d" % [absolute, image.get_width(), image.get_height()])
