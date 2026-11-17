extends Node
## 设置管理：鼠标灵敏度、视野、体积等玩家设置，持久化到 user://settings.cfg。
##
## 存档只记录游戏进度；设置独立保存，不随游戏存档版本迁移。

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "settings"

const DEFAULT_MOUSE_SENSITIVITY := 0.002
const DEFAULT_FIELD_OF_VIEW := 75.0
const DEFAULT_MASTER_VOLUME := 0.8

signal settings_changed()

var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY
var field_of_view: float = DEFAULT_FIELD_OF_VIEW
var master_volume: float = DEFAULT_MASTER_VOLUME
var invert_y: bool = false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		GameLog.warn("设置文件不存在，使用默认值", {"path": SETTINGS_PATH})
		save_settings()
		return

	mouse_sensitivity = float(config.get_value(SECTION, "mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY))
	field_of_view = float(config.get_value(SECTION, "field_of_view", DEFAULT_FIELD_OF_VIEW))
	master_volume = float(config.get_value(SECTION, "master_volume", DEFAULT_MASTER_VOLUME))
	invert_y = bool(config.get_value(SECTION, "invert_y", false))
	settings_changed.emit()


func save_settings() -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	config.set_value(SECTION, "field_of_view", field_of_view)
	config.set_value(SECTION, "master_volume", master_volume)
	config.set_value(SECTION, "invert_y", invert_y)

	var err := config.save(SETTINGS_PATH)
	if err != OK:
		GameLog.error("设置保存失败", {"path": SETTINGS_PATH, "error": err})
		return false
	return true


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.0002, 0.01)
	save_settings()
	settings_changed.emit()


func set_field_of_view(value: float) -> void:
	field_of_view = clampf(value, 50.0, 110.0)
	save_settings()
	settings_changed.emit()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	save_settings()
	settings_changed.emit()


func set_invert_y(value: bool) -> void:
	invert_y = value
	save_settings()
	settings_changed.emit()


func to_dict() -> Dictionary:
	return {
		"mouse_sensitivity": mouse_sensitivity,
		"field_of_view": field_of_view,
		"master_volume": master_volume,
		"invert_y": invert_y,
	}
