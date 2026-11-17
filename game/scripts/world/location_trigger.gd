class_name LocationTrigger
extends Area3D
## 区域触发器。进入 / 离开时发出 location.entered / location.exited。

@export var location_id: StringName = &""


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		EventBus.location_entered.emit(location_id)
		GameLog.info("进入区域", {"location": location_id})


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		EventBus.location_exited.emit(location_id)
