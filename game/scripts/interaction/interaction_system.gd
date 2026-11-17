class_name InteractionSystem
extends Node
## 交互系统：从摄像机中心发射射线，驱动可交互对象的查询与调用。
##
## 挂在 Player 节点下，通过 NodePath 引用摄像机与射线。

@export var camera_path: NodePath = ^"../Head/Camera3D"
@export var ray_path: NodePath = ^"../Head/InteractionRay"
@export var interaction_range: float = 3.0

var _camera: Camera3D
var _ray: RayCast3D
var _current_target: Node = null


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D
	_ray = get_node_or_null(ray_path) as RayCast3D
	if _ray != null:
		_ray.enabled = true
		_ray.collide_with_areas = true
		_ray.collide_with_bodies = true


func _physics_process(_delta: float) -> void:
	if _ray == null or _camera == null:
		return

	var origin := _camera.global_position
	var forward := -_camera.global_transform.basis.z

	_ray.global_position = origin
	# 把世界方向换算到射线的本地空间，避免父节点旋转带来的偏差
	_ray.target_position = _ray.global_transform.basis.inverse() * (forward * interaction_range)
	_ray.force_raycast_update()

	var target := _resolve_target()
	if target != _current_target:
		_current_target = target
		EventBus.interaction_target_changed.emit(target)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return

	var target := _current_target
	if target == null:
		return

	var actor := get_parent()
	if not target.has_method("can_interact") or not target.can_interact(actor):
		return

	target.interact(actor)

	var target_id := target.get("stable_id")
	if target_id is StringName:
		EventBus.object_interacted.emit(target_id)


## 从碰撞体向上查找带 Interactable 契约的节点。
func _resolve_target() -> Node:
	if not _ray.is_colliding():
		return null

	var node: Node = _ray.get_collider()
	while node != null:
		if _is_interactable(node):
			return node
		node = node.get_parent()
	return null


func _is_interactable(node: Node) -> bool:
	return node.has_method("interact") and node.has_method("can_interact") and node.has_method("get_prompt")


func get_current_target() -> Node:
	return _current_target


func clear_target() -> void:
	_current_target = null
	EventBus.interaction_target_changed.emit(null)
