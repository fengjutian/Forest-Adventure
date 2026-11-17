class_name RangerCampBuilder
extends Node3D
## 猎人营地遗址的人工地标（docs/vertical-slice-completion.md §3）。
##
## 与 CampBuilder 同一套做法：物件用世界坐标摆好，
## 高度由高度场提供，保证物件和脚下的地面永远对齐。
##
## 这些是人造物，不参与程序化重新生成（docs/content-pipeline.md §2）。

signal props_built()

@export var camp_seed: int = 44117

var _height_provider: Variant = null
## 营地中心的世界坐标（XZ）。局部摆位要加上它才是世界坐标。
var _origin: Vector2 = Vector2.ZERO


func build(height_provider: Variant, origin: Vector2) -> void:
	_height_provider = height_provider
	_origin = origin

	_place_collapsed_tent()
	_place_trap()
	_place_dead_campfire()
	_place_backpack()
	_place_marker_arrows()

	props_built.emit()
	GameLog.info("猎人营地遗址布置完成")


# ------------------------------------------------------------------ 道具

func _add_prop(node_name: String, mesh: Mesh, local_position: Vector2, rotation_y: float,
		solid_size: Vector3 = Vector3.ZERO) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.rotation.y = deg_to_rad(rotation_y)
	add_child(root)

	if mesh != null:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.material_override = PropKit.painted_material()
		root.add_child(mesh_instance)

	if solid_size != Vector3.ZERO:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0

		var shape := BoxShape3D.new()
		shape.size = solid_size

		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		root.add_child(body)

	# 局部坐标摆位，高度查的是世界坐标的高度场
	var world := _origin + local_position
	root.position = Vector3(local_position.x, _ground(world.x, world.y), local_position.y)
	return root


func _ground(x: float, z: float) -> float:
	if _height_provider == null:
		return 0.0
	return float(_height_provider.height_at(x, z))


# ------------------------------------------------------------------ 各物件

func _place_collapsed_tent() -> void:
	_add_prop("CollapsedTent", PropKit.make_collapsed_tent(),
		Vector2(-2.2, 1.4), 24.0, Vector3(1.4, 0.9, 1.4))


func _place_trap() -> void:
	_add_prop("Trap", PropKit.make_trap(), Vector2(1.8, -1.6), -40.0)


func _place_dead_campfire() -> void:
	_add_prop("DeadCampfire", PropKit.make_dead_campfire(), Vector2(0.3, 2.6), 0.0)


func _place_backpack() -> void:
	_add_prop("Backpack", PropKit.make_backpack(), Vector2(-0.9, -0.6), 15.0)


## 三支标箭散在不同方向，像是在标一条走过的小路。
func _place_marker_arrows() -> void:
	var spots := [Vector2(2.6, 2.2), Vector2(-2.8, -2.4), Vector2(1.2, -3.2)]
	var angles := [18.0, -64.0, 132.0]
	for i in spots.size():
		_add_prop("MarkerArrow%02d" % (i + 1), PropKit.make_marker_arrow(),
			spots[i], angles[i])
