extends Node
## 分块世界的多机位截图：营地 / 溪谷 / 高空俯瞰 / 林道北望。
##
## 用法：godot --path game res://tests/capture_world.tscn
## 输出：build/screenshots/world_*.png

const OUT_DIR := "res://../build/screenshots"

var _player: Player
var _world: ChunkedWorld
var _environment: Environment
var _shots: Array = [
	# 名称、玩家位置（y 为离地高度）、偏航、俯仰、等待帧数
	{"name": "world_camp", "position": Vector3(0.0, 0.0, 7.5), "yaw": 0.0, "pitch": -4.0, "frames": 200},
	{"name": "world_creek", "position": Vector3(14.0, 0.0, 40.0), "yaw": 180.0, "pitch": -6.0, "frames": 160},
	# 俯瞰关掉雾，才看得清地形接缝与区块边缘
	{"name": "world_aerial", "position": Vector3(0.0, 70.0, 110.0), "yaw": 0.0, "pitch": -18.0, "frames": 240, "no_fog": true},
	{"name": "world_path", "position": Vector3(1.5, 0.0, -24.0), "yaw": 0.0, "pitch": 0.0, "frames": 180},
	{"name": "world_ridge", "position": Vector3(1.5, 0.0, -26.0), "yaw": 0.0, "pitch": 5.0, "frames": 200},
]


func _ready() -> void:
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group(&"player") as Player
	_world = get_tree().get_first_node_in_group(&"chunked_world") as ChunkedWorld
	if _player == null or _world == null:
		push_error("缺少玩家或分块世界")
		get_tree().quit(1)
		return

	var world_environment := get_node_or_null("Main/WorldEnvironment") as WorldEnvironment
	if world_environment != null:
		_environment = world_environment.environment

	_player.set_physics_process(false)

	for shot in _shots:
		await _capture(shot)

	get_tree().quit(0)


func _capture(shot: Dictionary) -> void:
	var position: Vector3 = shot["position"]
	var ground := _world.height_at(position.x, position.z)
	# 位置参数的 y 是离地高度；贴地后再抬起相机
	_player.global_position = Vector3(position.x, ground + position.y, position.z)
	_player.rotation.y = deg_to_rad(float(shot["yaw"]))
	var head := _player.get_node_or_null("Head") as Node3D
	if head != null:
		head.rotation.x = deg_to_rad(float(shot["pitch"]))

	if _environment != null:
		_environment.fog_enabled = not bool(shot.get("no_fog", false))

	var frames := int(shot["frames"])
	for i in frames:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("无法取得渲染结果")
		return
	var path := ProjectSettings.globalize_path(OUT_DIR + "/%s.png" % shot["name"])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if image.save_png(path) != OK:
		push_error("截图写入失败：%s" % path)
		return

	print("SHOT %s fps=%d chunks=%d" % [
		shot["name"], Engine.get_frames_per_second(), _world.loaded_chunk_count(),
	])
