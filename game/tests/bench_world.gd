extends Node
## 分块世界流式加载压力测试（无头运行，测 CPU 侧帧时间）。
##
## 用法：godot --headless --path game res://tests/bench_world.tscn
## 让玩家沿对角线瞬移穿越整张 1 km 地图，每 8 帧挪 23 m，
## 每次都迫使流式系统重建脚下与前方区块，记录最差帧时间。

const STEPS := 40
const STEP_METERS := 23.0
const FRAMES_PER_STEP := 8

var _player: Player
var _world: ChunkedWorld


func _ready() -> void:
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group(&"player") as Player
	_world = get_tree().get_first_node_in_group(&"chunked_world") as ChunkedWorld
	if _player == null or _world == null:
		push_error("缺少玩家或分块世界")
		get_tree().quit(1)
		return

	_player.set_physics_process(false)

	var worst_usec := 0
	var total_usec := 0
	var frames := 0
	var worst_at := 0

	for step in STEPS:
		var offset := -470.0 + float(step) * STEP_METERS
		var position := Vector3(offset, 0.0, -offset * 0.85)
		_player.global_position = Vector3(
			position.x,
			_world.height_at(position.x, position.z) + 2.0,
			position.z
		)
		for i in FRAMES_PER_STEP:
			var start := Time.get_ticks_usec()
			await get_tree().process_frame
			var elapsed := Time.get_ticks_usec() - start
			total_usec += elapsed
			frames += 1
			if elapsed > worst_usec:
				worst_usec = elapsed
				worst_at = step

	print("BENCH frames=%d avg=%.2fms worst=%.2fms step=%d chunks=%d" % [
		frames,
		float(total_usec) / float(maxi(frames, 1)) / 1000.0,
		float(worst_usec) / 1000.0,
		worst_at,
		_world.loaded_chunk_count(),
	])
	get_tree().quit(0)
