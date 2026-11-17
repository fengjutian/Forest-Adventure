class_name RangerCamp
extends Node3D
## 猎人营地遗址：隐藏地点（docs/vertical-slice-completion.md §3）。
##
## 与营地一样不参与分块：它只有十几米见方，常驻世界里。
##
## 位置在松木林深处，世界坐标 (142, -168)。选点依据是实测的地形：
## 坡度 0.021（几乎是平地），植被密度 0.53（全图偏高的地带），
## 离溪流 131 m，离营地 219 m——走进去要花点时间，符合「深处」的观感。

@onready var props: RangerCampBuilder = $AuthoredProps

var _field: TerrainField = null


func _ready() -> void:
	var world := get_parent() as ChunkedWorld
	if world == null or world.field == null:
		GameLog.error("RangerCamp 必须挂在 ChunkedWorld 下")
		return
	_field = world.field

	# 整体贴到地势上。触发器有十几米宽，
	# 抬到中心的高度才不会有一半悬空。
	var g := global_position
	global_position = Vector3(g.x, _field.height_at(g.x, g.z), g.z)

	props.build(_field, Vector2(g.x, g.z))
	GameLog.info("猎人营地遗址就绪", {"position": global_position})
