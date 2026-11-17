class_name GameLog
extends RefCounted
## 结构化日志（docs/development-plan.md M0：设置和日志）。
##
## 作为静态工具类使用，不占用 autoload 槽位：
##   GameLog.info("事件", {"key": value})
##
## 同时写入 stdout 与 user://logs/game.log，文件超限时自动轮转一份备份。

const LOG_DIR := "user://logs"
const LOG_FILE := "game.log"
const MAX_BYTES := 2 * 1024 * 1024
const KEEP_BACKUPS := 2

static func info(message: String, context: Dictionary = {}) -> void:
	_write("INFO", message, context)

static func warn(message: String, context: Dictionary = {}) -> void:
	_write("WARN", message, context)

static func error(message: String, context: Dictionary = {}) -> void:
	_write("ERROR", message, context)

static func _write(level: String, message: String, context: Dictionary) -> void:
	var entry := {
		"ts": Time.get_datetime_string_from_system(),
		"level": level,
		"msg": message,
	}
	if not context.is_empty():
		entry["ctx"] = context

	var line := JSON.stringify(entry)
	print("[%s] %s" % [level, line])

	if level == "ERROR":
		push_error("%s %s" % [message, context])

	_ensure_dir()
	_rotate_if_needed()

	var path := "%s/%s" % [LOG_DIR, LOG_FILE]
	# READ_WRITE 不会创建缺失的文件，首次写入必须用 WRITE
	var mode := FileAccess.WRITE
	if FileAccess.file_exists(path):
		mode = FileAccess.READ_WRITE

	var file := FileAccess.open(path, mode)
	if file == null:
		return
	file.seek_end()
	file.store_line(line)
	file.close()


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		DirAccess.make_dir_recursive_absolute(LOG_DIR)


static func _rotate_if_needed() -> void:
	var path := "%s/%s" % [LOG_DIR, LOG_FILE]
	if not FileAccess.file_exists(path):
		return
	if FileAccess.get_file_as_bytes(path).size() < MAX_BYTES:
		return

	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return
	# 旧备份依次后移：.2 丢弃，.1 -> .2，当前 -> .1
	var oldest := "%s.%d" % [LOG_FILE, KEEP_BACKUPS]
	if dir.file_exists(oldest):
		dir.remove(oldest)
	for i in range(KEEP_BACKUPS - 1, 0, -1):
		var from := "%s.%d" % [LOG_FILE, i]
		var to := "%s.%d" % [LOG_FILE, i + 1]
		if dir.file_exists(from):
			dir.rename(from, to)
	dir.rename(LOG_FILE, "%s.1" % LOG_FILE)
