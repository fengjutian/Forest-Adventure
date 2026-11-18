class_name AssetLibrary
extends RefCounted
## 管线产出的资产库（docs/forest-pipeline-spec.md §2、§7）。
##
## 运行时按**字符串键**取网格：先查管线产出的 GLB，没有再回退 `PropKit` 的程序化网格。
## 这样 M4 的内容替换只是把 GLB 放进 `game/assets/generated/`，运行时逻辑一行都不用改。
##
## 管线产的 manifest 形如：
##   game/assets/generated/<region_id>/manifest.json
##   game/assets/generated/<region_id>/meshes/env_tree_pine_a_lod0.glb
##
## manifest 不存在（还没跑过管线）时全部回退，不影响现有玩法。

const DEFAULT_MANIFEST_PATH := "res://assets/generated/pine_valley/manifest.json"

## key -> Mesh。GLB 一旦载入就常驻：1024 m 世界里同一种树要撒几万次。
static var _meshes: Dictionary = {}
## key -> 该资产 LOD0 的 res:// 路径
static var _paths: Dictionary = {}
## 读到的 manifest（供导入检查器与调试使用）
static var _manifest: Dictionary = {}
static var _loaded := false


## 读 manifest 并登记每个资产的 LOD0 路径。重复调用只会真正加载一次。
static func ensure_loaded(manifest_path: String = DEFAULT_MANIFEST_PATH) -> void:
	if _loaded:
		return
	_loaded = true

	if not FileAccess.file_exists(manifest_path):
		return
	var text := FileAccess.get_file_as_string(manifest_path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		GameLog.warn("生成资产 manifest 解析失败", {"path": manifest_path})
		return
	_manifest = parsed as Dictionary

	var base_dir := manifest_path.get_base_dir()
	for entry in _manifest.get("assets", []):
		if not (entry is Dictionary):
			continue
		var key := str((entry as Dictionary).get("key", ""))
		if key.is_empty():
			continue
		for file_entry in (entry as Dictionary).get("files", []):
			if not (file_entry is Dictionary):
				continue
			if int((file_entry as Dictionary).get("lod", -1)) != 0:
				continue
			var relative := str((file_entry as Dictionary).get("path", ""))
			if relative.is_empty():
				continue
			_paths[key] = base_dir.path_join(relative)


## 该键是否有管线产出的资产。
static func has_asset(key: String) -> bool:
	ensure_loaded()
	return _paths.has(key)


## 取管线产出的网格；没有就返回 null（调用方回退到 PropKit）。
static func mesh_for(key: String) -> Mesh:
	ensure_loaded()
	if _meshes.has(key):
		return _meshes[key]
	if not _paths.has(key):
		return null

	var path := str(_paths[key])
	if not ResourceLoader.exists(path):
		GameLog.warn("生成资产文件不存在", {"key": key, "path": path})
		return null

	var packed := load(path)
	if not (packed is PackedScene):
		GameLog.warn("生成资产不是 PackedScene", {"key": key, "path": path})
		return null

	var instance := (packed as PackedScene).instantiate()
	var mesh := _find_mesh(instance)
	instance.free()
	if mesh == null:
		GameLog.warn("生成资产里没有 MeshInstance3D", {"key": key, "path": path})
		return null

	_meshes[key] = mesh
	return mesh


## manifest 原文（供导入检查器比对 sha256 与键表）。
static func manifest() -> Dictionary:
	ensure_loaded()
	return _manifest


## 丢弃缓存（测试或重新导入后用）。
static func clear() -> void:
	_meshes.clear()
	_paths.clear()
	_manifest.clear()
	_loaded = false


static func _find_mesh(node: Node) -> Mesh:
	## 递归找第一个带网格的 MeshInstance3D。
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			return mesh
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
