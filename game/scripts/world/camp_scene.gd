class_name CampScene
extends Node3D
## 灰盒营地场景的装配入口。
##
## 顺序很重要：先地形（其它系统都要查高度），再人工地标，最后植被散布
## （散布需要排除营地与主路径，而这些区域由地标定义）。

@onready var terrain: ProcTerrain = $Terrain
@onready var vegetation: VegetationScatter = $Vegetation
@onready var props: CampBuilder = $AuthoredProps

## 需要贴地的节点（可交互物、出生点与敌人）。
@export var ground_snap_paths: Array[NodePath] = [
	^"SupplyCrate", ^"CampRadio", ^"Campfire", ^"SpawnPoint",
	^"Wolf01", ^"Wolf02", ^"Wolf03",
]

var _water: MeshInstance3D
var _water_time: float = 0.0


func _ready() -> void:
	terrain.build()
	props.build(terrain)
	_snap_to_ground()
	vegetation.scatter(terrain)
	_find_water()

	GameLog.info("灰盒营地就绪", {"region": "region_00_camp"})


func _snap_to_ground() -> void:
	for path in ground_snap_paths:
		var node := get_node_or_null(path) as Node3D
		if node == null:
			continue
		var position := node.position
		node.position = Vector3(position.x, terrain.height_at(position.x, position.z), position.z)


func _find_water() -> void:
	var props_root := $AuthoredProps
	if props_root == null:
		return
	_water = props_root.get_node_or_null("CreekWater") as MeshInstance3D


func _process(delta: float) -> void:
	# 水面缓慢流动
	if _water == null:
		return
	_water_time += delta
	var material := _water.material_override as StandardMaterial3D
	if material == null:
		return
	material.uv1_offset = Vector3(0.0, -_water_time * 0.06, 0.0)
