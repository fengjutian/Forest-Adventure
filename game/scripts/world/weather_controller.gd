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

## 天气 → 能见度（雾密度）参数。
const FOG_DENSITY := {
	&"clear": 0.006,
	&"cloudy": 0.012,
	&"rain": 0.022,
	&"fog": 0.055,
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
	_environment.fog_density = float(FOG_DENSITY.get(current_weather, 0.006))
	_environment.fog_light_color = Color(0.55, 0.60, 0.62)
	_environment.fog_sun_scatter = 0.15
