extends Node
## 临时诊断：战斗相关截图。

func _ready() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	var main := packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var player: Player = main.get("player")
	var cam: Camera3D = main.get_node("Player/Head/Camera3D")
	cam.current = true

	# 找一只狼
	var wolf: EnemyBase = null
	for node in get_tree().get_nodes_in_group(&"enemy"):
		wolf = node as EnemyBase
		if wolf != null:
			break

	if wolf != null:
		# 站到狼前方，近距离观察
		player.global_position = wolf.global_position + Vector3(0.0, 0.0, 4.5)
		player.velocity = Vector3.ZERO
		var head: Node3D = main.get_node("Player/Head")
		head.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
		player.look_at(Vector3(wolf.global_position.x, player.global_position.y + 1.0, wolf.global_position.z), Vector3.UP)

		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_save("res://../build/screenshots/wolf.png")

		# 举起弓：模拟瞄准
		var bow: Bow = main.get_node("Player/Bow")
		var view_model := bow.get_node_or_null("BowViewModel")
		if view_model != null:
			view_model.visible = true
		cam.fov = 55.0
		EventBus.bow_charge_changed.emit(0.72)
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_save("res://../build/screenshots/bow.png")

	get_tree().quit(0)


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(path)
	image.save_png(absolute)
	print("DIAG_SAVED:", absolute)
