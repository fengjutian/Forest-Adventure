extends Node
## 临时探针：验证弓实际生成箭矢的位置是否正确。

var _main: Node


func _ready() -> void:
	await get_tree().process_frame
	_main = get_node_or_null("Main")
	if _main == null:
		print("PROBE_FAIL: 无 Main")
		get_tree().quit(1)
		return

	var player: Player = _main.get("player")
	player.capture_mouse()
	await get_tree().physics_frame
	await get_tree().physics_frame

	var camera: Camera3D = _main.get_node("Player/Head/Camera3D")
	print("PROBE camera_pos=", camera.global_position)

	Input.action_press("fire")
	for i in 40:
		await get_tree().process_frame
	Input.action_release("fire")
	for i in 6:
		await get_tree().physics_frame

	var found := 0
	for child in _main.get_children():
		if child is ArrowProjectile:
			found += 1
			print("PROBE arrow_pos=", (child as ArrowProjectile).global_position,
				" vel=", (child as ArrowProjectile).velocity)
	print("PROBE arrow_count=", found)
	get_tree().quit(0)
