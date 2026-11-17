class_name Interactable
extends Node3D
## 可交互对象的统一约定（docs/technical-design.md §4.3）。
##
## 交互流程：
##   1. Camera3D 中心发射射线
##   2. 查找碰撞体或其父节点上的 Interactable
##   3. 调用 can_interact
##   4. UI 显示 get_prompt 返回的文本
##   5. 玩家按下交互键后调用 interact
##   6. 交互对象发出领域事件，任务系统按事件推进

## 稳定 ID。存档键必须使用稳定 ID，不能使用运行时实例 ID。
@export var stable_id: StringName = &""


func _ready() -> void:
	add_to_group(&"interactable")


## 需要持久化的状态。写入存档的 changed_objects。
func get_persistent_state() -> Dictionary:
	return {}


## 从存档恢复状态。
func apply_persistent_state(_state: Dictionary) -> void:
	pass


func can_interact(_actor: Node) -> bool:
	return true


func get_prompt(_actor: Node) -> String:
	return "交互"


func interact(_actor: Node) -> void:
	pass


## 交互后是否隐藏自身（拾取类对象）。
func is_consumed_on_interact() -> bool:
	return false


## 关闭交互能力：隐藏模型并移除碰撞，使射线不再命中。
func set_interactive_enabled(enabled: bool) -> void:
	for child in get_children():
		if child is CollisionObject3D:
			var body := child as CollisionObject3D
			if enabled:
				if not body.has_meta(&"original_layer"):
					body.set_meta(&"original_layer", body.collision_layer)
				body.collision_layer = int(body.get_meta(&"original_layer"))
			else:
				body.collision_layer = 0
			body.visible = enabled
		elif child is Node3D:
			(child as Node3D).visible = enabled
	visible = enabled
