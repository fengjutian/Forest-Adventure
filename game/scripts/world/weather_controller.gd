class_name WeatherController
extends Node
## 天气控制器（docs/technical-design.md §4.1）。
##
## 天气改变能见度、声音传播和部分道路可达性（docs/game-design.md §6.4）。
## 关键任务可锁定天气。

signal weather_changed(new_weather: StringName)

@export var weather_locked: bool = false
@export var current_weather: StringName = &"clear"
@export var fog_enabled: bool = true
## 指向主场景中的 WorldEnvironment 节点。
@export var environment_path: NodePath = ^"../../WorldEnvironment"

## 天气 → 能见距离（米）。距离雾的远端越近，能见度越差。
const FOG_END := {
	&"clear": 420.0,
	&"cloudy": 330.0,
	&"rain": 240.0,
	&"fog": 120.0,
}

var _environment: Environment


func _ready() -> void:
	GameState.weather_id = current_weather
	_apply()


func set_weather(weather_id: StringName) -> void:
	if weather_locked:
		GameLog.info("天气已锁定，忽略变更请求", {"requested": weather_id})
		return
	if weather_id == current_weather:
		return
	current_weather = weather_id
	GameState.weather_id = weather_id
	_apply()
	weather_changed.emit(current_weather)
	EventBus.weather_changed.emit(current_weather)
	GameLog.info("天气切换", {"weather": current_weather})


func _apply() -> void:
	if _environment == null:
		var world_environment := get_node_or_null(environment_path) as WorldEnvironment
		if world_environment == null:
			return
		if world_environment.environment == null:
			world_environment.environment = Environment.new()
		_environment = world_environment.environment

	if not fog_enabled:
		_environment.fog_enabled = false
		return

	_environment.fog_enabled = true
	_environment.fog_mode = Environment.FOG_MODE_DEPTH
	_environment.fog_depth_begin = 30.0
	_environment.fog_depth_end = float(FOG_END.get(current_weather, 380.0))
	_environment.fog_depth_curve = 1.4
	_environment.fog_light_color = Color(0.55, 0.60, 0.62)
	_environment.fog_sun_scatter = 0.15
