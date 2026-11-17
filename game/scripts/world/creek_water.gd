class_name CreekWater
extends MeshInstance3D
## 溪流水位（docs/vertical-slice-completion.md §4.5）。
##
## 营地旁那段溪流水面在 CampBuilder 里铺好，这里负责它的水位：
## 涨水事件把水位抬起来，踩石没顶、东岸那条低地被淹，
## 通往东岸的通路断开；雨停后水位回落，通路恢复。
##
## 涨水期间会启用一道碰撞体挡住涉水点。
## 水面本身没有碰撞——水不是墙，能走进去只是「湿了」，
## 但涨水后这一段必须真的过不去，否则事件没有意义。

## 事件 ID。这个水面只响应这个事件。
@export var event_id: StringName = &"creek_surge"
## 平常水位（世界 Y）。
@export var base_level: float = -1.0
## 涨水后的水位。
@export var surge_level: float = 0.15
## 水位变化速度（米/秒）。
@export var rise_speed: float = 0.35
## 涉水点在本地 Z 上的位置（踩石那一排）。
@export var crossing_z: float = 22.0
## 涉水点的阻挡范围（本地 X 尺寸）。
@export var crossing_width: float = 18.0

var _target_level: float = -1.0
var _uv_time: float = 0.0
var _blocker: CollisionShape3D = null


func _ready() -> void:
	_target_level = base_level
	add_to_group(&"world_event_effect")
	_build_blocker()


func _process(delta: float) -> void:
	# 水位缓动。涨水和退水用同一个速度，退水看起来才不会突兀。
	if not is_equal_approx(position.y, _target_level):
		position.y = move_toward(position.y, _target_level, rise_speed * delta)

	# 水面流动
	_uv_time += delta
	var material := material_override as StandardMaterial3D
	if material != null:
		material.uv1_offset = Vector3(0.0, -_uv_time * 0.06, 0.0)


## 世界事件接口。管理器在事件开始与结束时调用它。
func apply_world_event(_event_id: StringName, active: bool) -> void:
	_target_level = surge_level if active else base_level
	_set_blocker_enabled(active)
	GameLog.info("溪流水位变化", {"level": _target_level, "active": active})


## 涉水点的阻挡体。涨水时启用，平时不挡路。
func _build_blocker() -> void:
	var body := StaticBody3D.new()
	body.name = "SurgeBlocker"
	body.collision_layer = 1
	body.collision_mask = 0

	var shape := BoxShape3D.new()
	shape.size = Vector3(crossing_width, 8.0, 4.0)

	_blocker = CollisionShape3D.new()
	_blocker.shape = shape
	_blocker.position = Vector3(0.0, 3.0, crossing_z)
	_blocker.disabled = true
	body.add_child(_blocker)
	add_child(body)


func _set_blocker_enabled(enabled: bool) -> void:
	if _blocker == null:
		return
	# 物理状态下改碰撞必须延后，否则会在物理线程里改结构。
	_blocker.set_deferred("disabled", not enabled)


## 供测试用：当前是否处于涨水状态。
func is_surging() -> bool:
	return _target_level > base_level + 0.001


## 供测试用：涉水点当前是否被挡住。
func is_crossing_blocked() -> bool:
	return _blocker != null and not _blocker.disabled
