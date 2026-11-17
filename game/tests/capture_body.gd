extends Node
## 玩家本体网格的预览：出「低头看身体」和「蹲下」两张图。
##
## 用法：godot --path game res://tests/capture_body.tscn
##
## 检查点：
## 1) 平视时身体必须完全在画面外（躯干顶端要低于相机）；
## 2) 低头必须能看到躯干、腰和腿，而不是一片空洞；
## 3) 蹲下时相机不能钻进躯干里。
##
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

	# 1) 略微低头：胸口应该出现在画面下缘，上面还是世界
	await _settle(16)
	_set_pitch(player, -55.0)
	await _settle(10)
	await _shot(OUT_DIR + "/body_lookdown.png")

	# 2) 深度低头：应该能看到腿和靴子，而不是空洞
	await _set_pitch(player, -80.0)
	await _settle(10)
	await _shot(OUT_DIR + "/body_legs.png")

	# 3) 蹲下 + 低头：相机不能钻进躯干里
	await _set_pitch(player, -60.0)
	Input.action_press("crouch")
	await _settle(20)
	await _shot(OUT_DIR + "/body_crouch.png")
	Input.action_release("crouch")

	# 3) 平视：身体必须不在画面里
	await _set_pitch(player, 0.0)
	await _settle(16)
	await _shot(OUT_DIR + "/body_level.png")

	get_tree().quit(0)


## 站到营地空地，抬头平视。
func _place(player: Player) -> void:
	player.global_position = Vector3(0.0, 0.0, 7.5)
	player.velocity = Vector3.ZERO
	player.rotation.y = deg_to_rad(180.0)
	_set_pitch(player, 0.0)


func _set_pitch(player: Player, degrees: float) -> void:
	var head := player.get_node_or_null("Head") as Node3D
	if head != null:
		head.rotation_degrees = Vector3(degrees, 0.0, 0.0)


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
