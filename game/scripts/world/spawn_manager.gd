class_name SpawnManager
extends Node
## 出生点管理（docs/technical-design.md §4.1）。
##
## 玩家死亡或读档后回到安全据点。出生点以稳定 ID 记录。

signal player_respawned(spawn_id: StringName)

## 节点加入该分组即可成为出生点。
const SPAWN_GROUP := &"spawn_point"

var _spawns: Dictionary = {}   # StringName -> Node3D
var _default_spawn_id: StringName = &""


func _ready() -> void:
	for node in get_tree().get_nodes_in_group(SPAWN_GROUP):
		_register(node)
	GameLog.info("SpawnManager 就绪", {"spawns": _spawns.size()})


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
	if spawn_id != &"" and _spawns.has(spawn_id):
		return _spawns[spawn_id]
	if _default_spawn_id != &"" and _spawns.has(_default_spawn_id):
		return _spawns[_default_spawn_id]
	return null


## 把玩家移动到指定出生点。
func respawn_player(player: Player, spawn_id: StringName = &"") -> bool:
	var spawn := get_spawn(spawn_id)
	if spawn == null or player == null:
		GameLog.error("找不到出生点", {"spawn": spawn_id})
		return false

	player.global_position = spawn.global_position + Vector3(0.0, 0.2, 0.0)
	player.velocity = Vector3.ZERO
	player.set_control_enabled(true)
	player_respawned.emit(spawn_id)
	GameLog.info("玩家已重生", {"spawn": spawn_id})
	return true
