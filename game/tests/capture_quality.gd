extends Node
## 画质档位对比截图 + 帧时间测量。
##
## 用法：godot --disable-vsync --path game res://tests/capture_quality.tscn
## 输出：build/screenshots/quality/<档位>_<机位>.png
##
## 每个档位都从同一机位、同一时间点取景，档位之间只有渲染参数不同，
## 于是可以直接把两张图叠在一起看差异。测量帧时间时关掉垂直同步，
## 否则所有档位都会被 60 FPS 的刷新率压平，看不出真实开销。

const OUT_DIR := "res://../build/screenshots/quality"

## 取样用的两个机位：营地（建筑 + 阴影 + 近景）与林道（大量树冠边缘，最吃抗锯齿）。
const VIEWS := [
	{"name": "camp", "position": Vector3(0.0, 0.0, 7.5), "yaw": 0.0, "pitch": -4.0},
	{"name": "path", "position": Vector3(1.5, 0.0, -24.0), "yaw": 0.0, "pitch": 0.0},
]

## 档位：名称 + 渲染参数。terrain_resolution 为 0 表示不改地形网格密度。
##
## 阴影距离固定 60 m：把它拉远会让同样的阴影贴图摊到更大范围，
## 近处阴影反而变糊，那不是「提高精度」。
const TIERS := [
	{"name": "q0_baseline", "msaa": 2, "ssao": false, "shadow_distance": 60.0,
		"render_scale": 1.0, "terrain_resolution": 0},
	{"name": "q1_msaa4", "msaa": 3, "ssao": false, "shadow_distance": 60.0,
		"render_scale": 1.0, "terrain_resolution": 0},
	{"name": "q2_ssao", "msaa": 3, "ssao": true, "shadow_distance": 60.0,
		"render_scale": 1.0, "terrain_resolution": 0},
	{"name": "q3_terrain40", "msaa": 3, "ssao": true, "shadow_distance": 60.0,
		"render_scale": 1.0, "terrain_resolution": 40},
	{"name": "q4_terrain48", "msaa": 3, "ssao": true, "shadow_distance": 60.0,
		"render_scale": 1.0, "terrain_resolution": 48},
]

const WARMUP_FRAMES := 40
const MEASURE_FRAMES := 120

var _player: Player
var _world: ChunkedWorld
var _environment: Environment
var _sun: DirectionalLight3D
var _current_tier: String = ""


func _ready() -> void:
	for i in 3:
		await get_tree().process_frame

	_player = get_tree().get_first_node_in_group(&"player") as Player
	_world = get_tree().get_first_node_in_group(&"chunked_world") as ChunkedWorld
	var world_environment := get_node_or_null("Main/WorldEnvironment") as WorldEnvironment
	_sun = get_node_or_null("Main/Sun") as DirectionalLight3D
	if _player == null or _world == null or world_environment == null:
		push_error("缺少玩家、分块世界或 WorldEnvironment")
		get_tree().quit(1)
		return
	_environment = world_environment.environment
	_player.set_physics_process(false)
	# 关掉玩家的每帧逻辑（持弓呼吸/惯性），否则同一机位每张图的弓都在动
	_player.set_process(false)

	# 锁死时间与天气：档位之间唯一的变量必须是渲染参数，
	# 否则太阳角度一变，阴影和色温的差异会盖过画质本身的差异。
	var time_of_day := get_node_or_null("Main/WorldManager/TimeOfDay") as TimeOfDay
	if time_of_day != null:
		time_of_day.time_locked = true
		time_of_day.set_minutes(510.0)
	var weather := get_node_or_null("Main/WorldManager/WeatherController") as WeatherController
	if weather != null:
		weather.weather_locked = true

	var hud := get_node_or_null("Main/UI") as HUD
	if hud != null:
		hud.close_controls_hint()

	# 第一档总要替所有档位付一次着色器编译的钱，先空跑几帧把它摊掉，
	# 否则测出来的「基线最慢」其实是编译开销，不是渲染开销。
	await _apply_tier(TIERS[0])
	for i in 30:
		await get_tree().process_frame

	# 敌人会自己走动：不冻住的话，两档之间狼的位置就不一样，像素差异没法比
	for node in get_tree().get_nodes_in_group(&"enemy"):
		node.set_physics_process(false)
		node.set_process(false)

	for tier in TIERS:
		await _run_tier(tier)

	get_tree().quit(0)


func _run_tier(tier: Dictionary) -> void:
	_current_tier = String(tier["name"])
	await _apply_tier(tier)

	# 地形网格换了密度要等重建完，其他参数立刻生效
	for i in WARMUP_FRAMES:
		await get_tree().process_frame

	var frame_ms := await _measure_frames(MEASURE_FRAMES)

	for view in VIEWS:
		await _capture(view)

	print("TIER %s avg_ms=%.2f fps=%.1f" % [tier["name"], frame_ms, 1000.0 / maxf(frame_ms, 0.001)])


func _apply_tier(tier: Dictionary) -> void:
	get_viewport().msaa_3d = int(tier["msaa"])
	get_viewport().scaling_3d_scale = float(tier["render_scale"])

	_environment.ssao_enabled = bool(tier["ssao"])
	_environment.ssao_radius = 2.4
	_environment.ssao_intensity = 1.8
	_environment.ssao_power = 1.6

	if _sun != null:
		_sun.directional_shadow_max_distance = float(tier["shadow_distance"])

	var resolution := int(tier["terrain_resolution"])
	if resolution > 0 and resolution != _world.terrain_resolution:
		_world.set_terrain_resolution(resolution)
		await get_tree().process_frame


func _measure_frames(frames: int) -> float:
	var start := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
	var elapsed := Time.get_ticks_usec() - start
	return float(elapsed) / float(frames) / 1000.0


func _capture(view: Dictionary) -> void:
	var position: Vector3 = view["position"]
	var ground := _world.height_at(position.x, position.z)
	_player.global_position = Vector3(position.x, ground, position.z)
	_player.rotation.y = deg_to_rad(float(view["yaw"]))
	var head := _player.get_node_or_null("Head") as Node3D
	if head != null:
		head.rotation.x = deg_to_rad(float(view["pitch"]))

	for i in 12:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("无法取得渲染结果")
		return
	var path := ProjectSettings.globalize_path(OUT_DIR + "/%s_%s.png" % [_current_tier, view["name"]])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if image.save_png(path) != OK:
		push_error("截图写入失败：%s" % path)
		return
	print("SHOT %s %dx%d" % [path, image.get_width(), image.get_height()])
