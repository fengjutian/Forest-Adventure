class_name ChunkLoader
extends Node
## 场景块加载器（docs/technical-design.md §5.1）。
##
## M0/M1 阶段只加载单一区域场景；分块流式加载属于 M2 范围。
## 接口按流式加载设计，便于后续扩展而不改动调用方。

signal chunk_loaded(chunk_id: StringName)
signal chunk_unloaded(chunk_id: StringName)

@export var world_root_path: NodePath = ^"../WorldRoot"
## 自动加载的首个场景。
@export var initial_scene: String = ""

var _world_root: Node3D
var _loaded_chunks: Dictionary = {}   # StringName -> Node
var _current_region_scene: String = ""


func _ready() -> void:
	_world_root = get_node_or_null(world_root_path) as Node3D
	if _world_root == null:
		GameLog.error("ChunkLoader 找不到 WorldRoot")
		return

	if not initial_scene.is_empty():
		load_region(initial_scene)


## 加载一个区域场景。会先卸载当前区域已加载的场景块。
func load_region(scene_path: String) -> bool:
	if scene_path.is_empty():
		return true

	if not ResourceLoader.exists(scene_path):
		GameLog.error("区域场景不存在", {"scene": scene_path})
		return false

	unload_all()

	var packed := load(scene_path) as PackedScene
	if packed == null:
		GameLog.error("区域场景加载失败", {"scene": scene_path})
		return false

	var instance := packed.instantiate()
	_world_root.add_child(instance)

	_current_region_scene = scene_path
	chunk_loaded.emit(StringName(scene_path.get_file().get_basename()))
	GameLog.info("区域场景已加载", {"scene": scene_path})
	return true


func unload_all() -> void:
	for chunk_id in _loaded_chunks.keys():
		var node: Node = _loaded_chunks[chunk_id]
		if is_instance_valid(node):
			node.queue_free()
		chunk_unloaded.emit(chunk_id)
	_loaded_chunks.clear()
	_current_region_scene = ""


func get_loaded_chunks() -> Array:
	return _loaded_chunks.keys()
