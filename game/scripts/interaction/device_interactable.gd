class_name DeviceInteractable
extends Interactable
## 可修复设备。调查时发出 object.inspected，修复成功时发出 device.repaired。

@export var device_id: StringName = &""
## 修复所需物品。为空表示无需物品即可修复。
@export var required_item_id: StringName = &""
@export var required_amount: int = 1
@export var prompt_text: String = "调查"
## 可视外观，对应 PropKit.make_prop 的名称。
@export var prop_visual: StringName = &"radio"

var _repaired: bool = false


func _build_visual() -> void:
	var mesh := PropKit.make_prop(prop_visual)
	if mesh == null:
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = PropKit.painted_material()
	add_child(mesh_instance)


func can_interact(_actor: Node) -> bool:
	return not _repaired


func get_prompt(_actor: Node) -> String:
	if _repaired:
		return "已修复"
	return prompt_text


func interact(actor: Node) -> void:
	EventBus.object_inspected.emit(stable_id)

	if _repaired:
		return

	if required_item_id != &"":
		var inventory := PickupInteractable.resolve_inventory(actor)
		if inventory == null or not inventory.has_item(required_item_id, required_amount):
			GameLog.info("缺少修复所需物品", {"device": device_id, "required": required_item_id})
			return
		inventory.remove_item(required_item_id, required_amount)

	_repaired = true
	EventBus.device_repaired.emit(device_id)
	GameLog.info("设备修复完成", {"device": device_id})
	GameState.mark_changed(stable_id, get_persistent_state())


func is_repaired() -> bool:
	return _repaired


func get_persistent_state() -> Dictionary:
	return {"repaired": _repaired}


func apply_persistent_state(state: Dictionary) -> void:
	_repaired = bool(state.get("repaired", false))
