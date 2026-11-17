extends Node
## 版本化存档管理（docs/technical-design.md §4.5）。
##
## 约束：
##  - 版本化 JSON，save_version 必填
##  - 写入采用临时文件 + 原子替换，并保留一个上一版本备份
##  - 加载时执行版本迁移，不因新增字段破坏旧存档
##  - 只使用稳定 ID 作为存档键，不使用运行时实例 ID
##
## 各模块通过 register_provider / register_loader 注册自己的状态片段，
## SaveManager 负责组装与分发，避免存档逻辑散落在各模块里。

const SAVE_VERSION := 1
const SAVE_DIR := "user://saves"
const FORMAT_ID := "forest_adventure_save"
const DEFAULT_SLOT := 0
const SLOT_COUNT := 3

## 旧版本 → 迁移函数名。加载时从存档版本逐级迁移到 SAVE_VERSION。
const MIGRATIONS := {
	0: "_migrate_0_to_1",
}

## String → Callable，返回 Dictionary 片段，写入存档。
var _providers: Dictionary = {}
## String → Callable，接收整个存档 Dictionary，用于恢复。
var _loaders: Dictionary = {}


func _ready() -> void:
	_ensure_save_dir()
	GameLog.info("SaveManager 就绪", {"save_version": SAVE_VERSION, "dir": SAVE_DIR})


# ------------------------------------------------------------------ 注册

func register_provider(key: String, provider: Callable) -> void:
	_providers[key] = provider


func register_loader(key: String, loader: Callable) -> void:
	_loaders[key] = loader


func unregister(key: String) -> void:
	_providers.erase(key)
	_loaders.erase(key)


# ------------------------------------------------------------------ 存档

func save_game(slot: int = DEFAULT_SLOT) -> bool:
	var data := _collect()
	var text := JSON.stringify(data, "\t")

	if not _write_atomic(slot, text):
		EventBus.save_failed.emit("写入存档失败")
		return false

	GameLog.info("存档写入成功", {"slot": slot, "version": SAVE_VERSION})
	EventBus.game_saved.emit(slot)
	return true


func load_game(slot: int = DEFAULT_SLOT) -> bool:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		GameLog.warn("存档不存在", {"slot": slot})
		EventBus.save_failed.emit("存档不存在")
		return false

	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		GameLog.error("存档解析失败", {"slot": slot})
		EventBus.save_failed.emit("存档解析失败")
		return false

	var data: Dictionary = parsed
	var original_version := int(data.get("save_version", 0))
	if not _migrate(data):
		EventBus.save_failed.emit("存档迁移失败")
		return false

	if not _apply(data):
		EventBus.save_failed.emit("存档格式不匹配")
		return false

	# 迁移成功后回写，把旧存档就地升级到当前版本，避免每次读档重复迁移
	if int(data.get("save_version", 0)) > original_version:
		if _write_atomic(slot, JSON.stringify(data, "\t")):
			GameLog.info("存档已升级到当前版本", {"slot": slot, "from": original_version, "to": SAVE_VERSION})

	GameLog.info("存档读取成功", {"slot": slot, "version": SAVE_VERSION})
	EventBus.game_loaded.emit(slot)
	return true


func has_save(slot: int = DEFAULT_SLOT) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func list_slots() -> Array:
	var slots := []
	for i in range(SLOT_COUNT):
		if has_save(i):
			slots.append(i)
	return slots


func delete_save(slot: int = DEFAULT_SLOT) -> bool:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return false
	return dir.remove(_slot_filename(slot)) == OK


# ------------------------------------------------------------------ 内部

func _collect() -> Dictionary:
	var data := {
		"format": FORMAT_ID,
		"save_version": SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
	}
	for key in _providers:
		var provider: Variant = _providers[key]
		if provider is Callable:
			var fragment: Variant = (provider as Callable).call()
			if fragment is Dictionary:
				data.merge(fragment, true)
	return data


func _apply(data: Dictionary) -> bool:
	if String(data.get("format", "")) != FORMAT_ID:
		GameLog.error("存档格式不匹配", {"expected": FORMAT_ID, "got": data.get("format", "")})
		return false
	for key in _loaders:
		var loader: Variant = _loaders[key]
		if loader is Callable:
			(loader as Callable).call(data)
	return true


func _migrate(data: Dictionary) -> bool:
	var version := int(data.get("save_version", 0))
	var guard := 0

	while version < SAVE_VERSION:
		guard += 1
		if guard > 16:
			GameLog.error("存档迁移陷入循环", {"from": version})
			return false

		var method_name := String(MIGRATIONS.get(version, ""))
		if method_name == "" or not has_method(method_name):
			GameLog.error("缺少存档迁移路径", {"from": version, "to": SAVE_VERSION})
			return false

		call(method_name, data)

		var new_version := int(data.get("save_version", version))
		if new_version <= version:
			GameLog.error("迁移函数未提升版本号", {"from": version, "to": new_version})
			return false
		version = new_version

	return true


## v0 → v1：补齐 v1 引入的必需字段。
func _migrate_0_to_1(data: Dictionary) -> void:
	data["format"] = FORMAT_ID
	data["current_scene"] = data.get("current_scene", "")
	data["player_transform"] = data.get("player_transform", {})
	data["player_state"] = data.get("player_state", {})
	# inventory 在 v1 起是字典 {capacity, slots, quest_slots}
	data["inventory"] = data.get("inventory", {})
	data["quest_states"] = data.get("quest_states", {})
	data["world_flags"] = data.get("world_flags", {})
	data["changed_objects"] = data.get("changed_objects", {})
	data["time_and_weather"] = data.get("time_and_weather", {})
	data["save_version"] = 1


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _slot_filename(slot: int) -> String:
	return "slot_%d.json" % slot


func _slot_path(slot: int) -> String:
	return "%s/%s" % [SAVE_DIR, _slot_filename(slot)]


## 写入流程：临时文件 → 原子替换 → 保留一份上一版本备份。
func _write_atomic(slot: int, text: String) -> bool:
	_ensure_save_dir()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		GameLog.error("无法打开存档目录", {"dir": SAVE_DIR})
		return false

	var final_name := _slot_filename(slot)
	var temp_name := final_name + ".tmp"
	var backup_name := final_name + ".bak"

	var file := FileAccess.open("%s/%s" % [SAVE_DIR, temp_name], FileAccess.WRITE)
	if file == null:
		GameLog.error("无法写入临时存档", {"path": temp_name})
		return false
	file.store_string(text)
	file.flush()
	file.close()

	if dir.file_exists(final_name):
		if dir.file_exists(backup_name):
			dir.remove(backup_name)
		dir.rename(final_name, backup_name)

	var err := dir.rename(temp_name, final_name)
	if err != OK:
		GameLog.error("存档原子替换失败", {"error": err})
		return false
	return true
