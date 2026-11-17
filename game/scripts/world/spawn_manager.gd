class_name SpawnManager
extends Node
## 出生点管理（docs/technical-design.md §4.1）。
##
## 玩家死亡或读档后回到安全据点。出生点以稳定 ID 记录。

signal player_respawned(spawn_id: StringName)

## 节点加入该分组即可成为出生点。
const SPAWN_GROUP := &"spawn_point"
## 地形节点加入该分组后可提供地面高度（实现 height_at 的节点即可）。
const TERRAIN_GROUP := &"terrain"

var _spawns: Dictionary = {}   # StringName -> Node3D
var _default_spawn_id: StringName = &""


func _ready() -> void:
	_scan_spawns()
	GameLog.info("SpawnManager 就绪", {"spawns": _spawns.size()})


func _scan_spawns() -> void:
	for node in get_tree().get_nodes_in_group(SPAWN_GROUP):
		_register(node)


func _register(node: Node) -> void:
	if not (node is Node3D):
		return
	var spawn_id := StringName(node.name)
	_spawns[spawn_id] = node
	if _default_spawn_id == &"":
		_default_spawn_id = spawn_id


func register_spawn(node: Node3D, spawn_id: StringName) -> void:
	_spawns[spawn_id] = node
	if _default_spawn_id == &"":
		_default_spawn_id = spawn_id


func get_spawn(spawn_id: StringName = &"") -> Node3D:
	# 区域场景可能晚于本节点加载，这里做一次兜底扫描
	if _spawns.is_empty():
		_scan_spawns()
	if spawn_id != &"" and _spawns.has(spawn_id):
		return _spawns[spawn_id]
	if _default_spawn_id != &"" and _spawns.has(_default_spawn_id):
		return _spawns[_default_spawn_id]
	return null


## 查找当前世界的地形，用于把玩家贴到地面。
func _find_terrain() -> Node3D:
	return get_tree().get_first_node_in_group(TERRAIN_GROUP) as Node3D


## 把玩家移动到指定出生点，并贴到地面高度。
func respawn_player(player: Player, spawn_id: StringName = &"") -> bool:
	var spawn := get_spawn(spawn_id)
	if spawn == null or player == null:
		GameLog.error("找不到出生点", {"spawn": spawn_id})
		return false

	var target := spawn.global_position
	var terrain := _find_terrain()
	if terrain != null and terrain.has_method("height_at"):
		# 出生点标记通常放在地形上，贴地后再留一点余量避免初始穿插
		target.y = float(terrain.call("height_at", target.x, target.z)) + 0.05

	player.global_position = target
	player.velocity = Vector3.ZERO
	player.set_control_enabled(true)
	player_respawned.emit(spawn_id)
	GameLog.info("玩家已重生", {"spawn": spawn_id, "position": target})
	return true
