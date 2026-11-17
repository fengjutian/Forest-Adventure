extends Node
## 战斗画面截图：林狼、举弓瞄准、营地俯视。
##
## 用法：godot --path game res://tests/capture_combat.tscn
## 注意：必须使用带图形后端的 Godot（不能 --headless），否则拿到的是空帧。
##
## 截图期间会冻结敌人的 AI，让构图稳定可复现。

const OUT_DIR := "res://../build/screenshots"

## 站位与狼之间的距离（米）。
@export var wolf_distance: float = 5.5
## 与狼正前方的夹角（度），避免拍成正面照。
@export var wolf_angle_deg: float = 38.0


func _ready() -> void:
	var main := get_node_or_null("Main")
	if main == null:
		push_error("找不到 Main 场景")
		get_tree().quit(1)
		return

	for i in 4:
		await get_tree().process_frame

	# 按键提示会盖住画面右侧，战斗截图时先收起
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

	var wolf := _find_wolf()
	if wolf == null:
		push_error("场景里没有敌人")
		get_tree().quit(1)
		return

	# 冻结敌人 AI，保证构图稳定
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as EnemyBase
		if enemy != null:
			enemy.set_physics_process(false)

	_place_for_wolf(player, wolf)

	# 1) 林狼
	await _settle(20)
	await _shot(wolf_file())

	# 2) 举弓瞄准
	player.capture_mouse()
	Input.action_press("aim")
	await _settle(14)
	Input.action_press("fire")
	await _settle(24)
	await _shot(bow_file())
	Input.action_release("fire")
	Input.action_release("aim")
	player.release_mouse()

	# 3) 营地俯视
	await _shot_overhead(main)

	get_tree().quit(0)


func wolf_file() -> String:
	return OUT_DIR + "/combat_wolf.png"


func bow_file() -> String:
	return OUT_DIR + "/combat_bow.png"


func overhead_file() -> String:
	return OUT_DIR + "/combat_overhead.png"


func _find_wolf() -> EnemyBase:
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as EnemyBase
		if enemy != null:
			return enemy
	return null


## 把玩家放到狼的侧前方，并贴到地面。
func _place_for_wolf(player: Player, wolf: EnemyBase) -> void:
	var angle := deg_to_rad(wolf_angle_deg)
	var offset := Vector3(sin(angle), 0.0, cos(angle)) * wolf_distance
	var spot := wolf.global_position + offset
	spot.y = _ground_at(spot)

	player.global_position = spot
	player.velocity = Vector3.ZERO

	# 身体朝向狼，视线略微下压
	var look := wolf.global_position + Vector3(0.0, 0.75, 0.0)
	if player.has_method("look_at"):
		player.look_at(look, Vector3.UP)
	var head := player.get_node_or_null("Head") as Node3D
	if head != null:
		head.rotation_degrees = Vector3(-5.0, 0.0, 0.0)


func _ground_at(point: Vector3) -> float:
	var terrain := get_tree().get_first_node_in_group(&"terrain") as ProcTerrain
	if terrain == null:
		return point.y
	return terrain.height_at(point.x, point.z)


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


## 营地俯视：临时架一台俯视相机，隐藏 HUD。
func _shot_overhead(main: Node) -> void:
	var ui := main.get_node_or_null("UI") as CanvasLayer
	if ui != null:
		ui.visible = false

	var camera := Camera3D.new()
	camera.fov = 56.0
	camera.far = 500.0
	camera.position = Vector3(11.0, 31.0, 29.0)
	main.add_child(camera)
	camera.look_at(Vector3(0.0, 1.5, 1.0), Vector3.UP)
	camera.current = true

	await _settle(16)
	await _shot(overhead_file())

	# 把当前相机还给玩家，否则退出时视口没有相机
	var player_camera := main.get_node_or_null("Player/Head/Camera3D") as Camera3D
	if player_camera != null:
		player_camera.current = true
	camera.queue_free()
	if ui != null:
		ui.visible = true
