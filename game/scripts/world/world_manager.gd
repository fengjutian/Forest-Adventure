class_name WorldManager
extends Node3D
## 世界管理器（docs/technical-design.md §4.1）：世界状态与区域生命周期。
##
## 持有当前区域标识与场景块挂载点；区域切换由 ChunkLoader 执行。

signal region_changed(region_id: StringName)

@export var region_id: StringName = &"region_00_camp"

var _chunk_loader: Node
var _world_root: Node3D


func _ready() -> void:
	_chunk_loader = get_node_or_null("ChunkLoader")
	_world_root = get_node_or_null("WorldRoot")
	GameState.current_region_id = region_id
	GameLog.info("WorldManager 就绪", {"region": region_id})


func get_world_root() -> Node3D:
	return _world_root


func get_chunk_loader() -> Node:
	return _chunk_loader


## 切换区域。内容生产层负责提供目标场景路径。
func set_region(new_region_id: StringName, scene_path: String = "") -> bool:
	if _chunk_loader == null:
		GameLog.error("ChunkLoader 缺失，无法切换区域")
		return false

	if not _chunk_loader.has_method("load_region"):
		GameLog.error("ChunkLoader 缺少 load_region 接口")
		return false

	var ok: bool = _chunk_loader.load_region(scene_path)
	if ok:
		region_id = new_region_id
		GameState.current_region_id = new_region_id
		region_changed.emit(new_region_id)
		GameLog.info("区域切换完成", {"region": new_region_id, "scene": scene_path})
	return ok
