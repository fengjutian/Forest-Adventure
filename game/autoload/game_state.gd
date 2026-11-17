extends Node
## 运行期世界状态：区域标记、当前场景、时间与天气。
##
## 这里保存的是跨会话需要延续的「世界事实」——例如守林站是否已被修复、
## 森林入口是否开放。属于存档 world_flags 的数据源。

## 稳定 ID → bool。用于剧情开关，避免在存档里写运行时实例 ID。
var world_flags: Dictionary = {}

## 稳定 ID → 状态字典。记录已改变对象的持久化状态（已拾取、已修复等）。
var changed_objects: Dictionary = {}

var current_scene_id: StringName = &""
var current_region_id: StringName = &""

## 一天中的分钟数，0..1440。由昼夜系统驱动。
var time_of_day_minutes: float = 8.0 * 60.0
var weather_id: StringName = &"clear"


func _ready() -> void:
	GameLog.info("GameState 就绪")


func set_flag(flag_id: StringName, value: bool = true) -> void:
	world_flags[flag_id] = value
	GameLog.info("世界标记更新", {"flag": flag_id, "value": value})


func get_flag(flag_id: StringName, default_value: bool = false) -> bool:
	return bool(world_flags.get(flag_id, default_value))


func has_flag(flag_id: StringName) -> bool:
	return world_flags.has(flag_id)


func clear_flags() -> void:
	world_flags.clear()


## 记录已改变对象的持久化状态。
func mark_changed(object_id: StringName, state: Dictionary) -> void:
	if object_id == &"":
		return
	changed_objects[object_id] = state.duplicate(true)


func set_time_of_day(minutes: float) -> void:
	time_of_day_minutes = fposmod(minutes, 1440.0)


func get_time_string() -> String:
	var total := int(time_of_day_minutes)
	return "%02d:%02d" % [total / 60, total % 60]


func to_dict() -> Dictionary:
	return {
		"world_flags": world_flags.duplicate(true),
		"changed_objects": changed_objects.duplicate(true),
		"time_and_weather": {
			"current_scene_id": String(current_scene_id),
			"current_region_id": String(current_region_id),
			"time_of_day_minutes": time_of_day_minutes,
			"weather_id": String(weather_id),
		},
	}


func from_dict(data: Dictionary) -> void:
	world_flags = (data.get("world_flags", {}) as Dictionary).duplicate(true)
	changed_objects = (data.get("changed_objects", {}) as Dictionary).duplicate(true)

	var time_and_weather: Dictionary = data.get("time_and_weather", {})
	current_scene_id = StringName(time_and_weather.get("current_scene_id", ""))
	current_region_id = StringName(time_and_weather.get("current_region_id", ""))
	time_of_day_minutes = float(time_and_weather.get("time_of_day_minutes", 8.0 * 60.0))
	weather_id = StringName(time_and_weather.get("weather_id", "clear"))
