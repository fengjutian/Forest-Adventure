class_name CampSite
extends Node3D
## 营地：安全据点 + 人工地标 + 任务对象（docs/first-scene-design.md）。
##
## 营地不参与分块：它只有 40 m 见方，常驻在世界里。
## 地形网格仍然由 ChunkedWorld 按区块提供，这里只负责把人工物件贴到
## 同一个高度场上，保证木屋、营火、物资箱和脚下的地面永远对齐。

## 需要贴地的节点（可交互物、出生点与敌人）。
@export var ground_snap_paths: Array[NodePath] = [
	^"SupplyCrate", ^"CampRadio", ^"Campfire", ^"SpawnPoint",
	^"Wolf01", ^"Wolf02", ^"Wolf03",
]

@onready var props: CampBuilder = $AuthoredProps


func _ready() -> void:
	var world := get_parent() as ChunkedWorld
	if world == null or world.field == null:
		GameLog.error("CampSite 必须挂在 ChunkedWorld 下")
		return

	props.build(world.field)
	_snap_to_ground(world.field)
	GameLog.info("营地点位就绪", {"region": "region_00_camp"})


func _snap_to_ground(terrain: TerrainField) -> void:
	for path in ground_snap_paths:
		var node := get_node_or_null(path) as Node3D
		if node == null:
			continue
		var position := node.position
		node.position = Vector3(position.x, terrain.height_at(position.x, position.z), position.z)
