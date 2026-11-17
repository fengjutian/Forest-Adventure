extends Node
## 临时排查：窗口抢到焦点后，W 是否真的能驱动角色。

func _ready() -> void:
	await get_tree().process_frame
	var main := get_node_or_null("Main")
	var player: Player = main.get("player")
	var start := Time.get_ticks_msec()
	var last := player.global_position
	for i in 12:
		await get_tree().create_timer(0.5).timeout
		var now := player.global_position
		print("PROBE t=%.1f pos=(%.2f,%.2f,%.2f) delta=%.2f focused=%s vec=%s" % [
			(Time.get_ticks_msec() - start) / 1000.0,
			now.x, now.y, now.z,
			last.distance_to(now),
			str(DisplayServer.window_is_focused()),
			str(Input.get_vector("move_left", "move_right", "move_forward", "move_back")),
		])
		last = now
	get_tree().quit(0)
