class_name TimeOfDay
extends Node3D
## 昼夜循环（docs/technical-design.md §4.1）。
##
## 以任务节奏驱动，不追求真实时间比例；关键任务可锁定时间与天气。

signal time_updated(minutes: float)

@export_group("时间")
## 一整天对应的真实秒数。M0/M1 使用较短周期以便观察。
@export var day_length_seconds: float = 600.0
@export var start_minutes: float = 8.0 * 60.0
## 锁定时间，任务需要固定光照时使用。
@export var time_locked: bool = false
@export var locked_minutes: float = 8.0 * 60.0

@export_group("光照")
## 指向主场景中的 WorldEnvironment 节点。
@export var environment_path: NodePath = ^"../../WorldEnvironment"
## 指向主场景中的太阳节点。
@export var sun_path: NodePath = ^"../../Sun"
@export var ambient_energy: float = 0.3

var _minutes: float = 8.0 * 60.0
var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var sun: DirectionalLight3D


func _ready() -> void:
	_minutes = locked_minutes if time_locked else start_minutes
	sun = get_node_or_null(sun_path) as DirectionalLight3D
	_setup_environment()
	_apply()
	GameLog.info("TimeOfDay 就绪", {"minutes": _minutes, "sun": sun != null})


func _process(delta: float) -> void:
	if time_locked:
		_minutes = locked_minutes
		_apply()
		return
	if day_length_seconds <= 0.0:
		return

	_minutes = fposmod(_minutes + (1440.0 / day_length_seconds) * delta, 1440.0)
	GameState.set_time_of_day(_minutes)
	_apply()
	time_updated.emit(_minutes)


func _setup_environment() -> void:
	var world_environment := get_node_or_null(environment_path) as WorldEnvironment
	if world_environment == null:
		GameLog.warn("找不到 WorldEnvironment，昼夜光照不可用")
		return

	if world_environment.environment == null:
		world_environment.environment = Environment.new()

	_environment = world_environment.environment
	_sky_material = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky_material

	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_energy = ambient_energy

	# 空气透视：近处清晰、远处被雾压暗并偏蓝。
	# 用「距离雾」而不是指数雾：近景不被糊白，1 km 世界的地形边缘又能被藏住。
	_environment.fog_enabled = true
	_environment.fog_mode = Environment.FOG_MODE_DEPTH
	_environment.fog_depth_begin = 30.0
	_environment.fog_depth_end = 380.0
	_environment.fog_depth_curve = 1.4
	_environment.fog_light_color = Color(0.62, 0.7, 0.74)
	_environment.fog_light_energy = 0.9
	_environment.fog_sky_affect = 0.3
	_environment.fog_aerial_perspective = 0.45

	# 影调：Filmic 压高光，轻微提饱和
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.adjustment_enabled = true
	_environment.adjustment_saturation = 1.06
	_environment.adjustment_contrast = 1.04


## 依据一天中的时间计算太阳高度、颜色与环境光。
func _apply() -> void:
	var day_fraction := _minutes / 1440.0
	# 06:00 东边升起，12:00 头顶，18:00 西边落下
	var sun_angle := (day_fraction * 360.0) - 90.0
	var height_factor := clampf(sin(deg_to_rad(day_fraction * 360.0 - 90.0)), 0.0, 1.0)
	var day_factor := clampf(sin(deg_to_rad(day_fraction * 360.0 - 90.0)) * 1.4 + 0.25, 0.0, 1.0)

	if sun != null:
		sun.rotation_degrees = Vector3(-sun_angle * 0.6, sun_angle, 0.0)
		sun.light_energy = lerpf(0.05, 1.2, height_factor)
		sun.light_color = Color(1.0, lerpf(0.72, 0.95, height_factor), lerpf(0.5, 0.88, height_factor))

	if _sky_material != null:
		var night := Color(0.05, 0.07, 0.12)
		var day := Color(0.52, 0.66, 0.82)
		_sky_material.sky_top_color = night.lerp(day, day_factor)
		_sky_material.sky_horizon_color = Color(0.09, 0.12, 0.16).lerp(Color(0.75, 0.78, 0.72), day_factor)
		_sky_material.ground_bottom_color = Color(0.05, 0.06, 0.05)
		_sky_material.ground_horizon_color = Color(0.12, 0.15, 0.12)

	if _environment != null:
		_environment.ambient_light_energy = lerpf(0.12, ambient_energy + 0.18, day_factor)
		# 雾色跟着昼夜走：白天偏冷白，夜里压暗
		var fog_day := Color(0.62, 0.7, 0.74)
		var fog_night := Color(0.09, 0.11, 0.15)
		_environment.fog_light_color = fog_night.lerp(fog_day, day_factor)
		_environment.fog_light_energy = lerpf(0.35, 0.9, day_factor)


func get_minutes() -> float:
	return _minutes


func set_minutes(value: float) -> void:
	_minutes = fposmod(value, 1440.0)
	GameState.set_time_of_day(_minutes)
	_apply()
