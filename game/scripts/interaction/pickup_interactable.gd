class_name PickupInteractable
extends Interactable
## 拾取物。交互后把物品放入背包，并发出 item.collected 领域事件。

@export var item_id: StringName = &""
@export var amount: int = 1
@export var prompt_text: String = "拾取"

var _collected: bool = false


func can_interact(_actor: Node) -> bool:
	return not _collected


func get_prompt(_actor: Node) -> String:
	return prompt_text


func interact(actor: Node) -> void:
	if _collected:
		return

	var inventory := resolve_inventory(actor)
	if inventory == null:
		GameLog.error("找不到背包，无法拾取", {"stable_id": stable_id, "item": item_id})
		return

	var added := inventory.add_item(item_id, amount)
	if added <= 0:
		GameLog.warn("背包已满", {"item": item_id})
		return

	_collected = true
	EventBus.item_collected.emit(item_id, added)
	GameLog.info("拾取物品", {"item": item_id, "amount": added})

	if is_consumed_on_interact():
		set_interactive_enabled(false)

	GameState.mark_changed(stable_id, get_persistent_state())


func is_consumed_on_interact() -> bool:
	return true


func get_persistent_state() -> Dictionary:
	return {"collected": _collected}


func apply_persistent_state(state: Dictionary) -> void:
	_collected = bool(state.get("collected", false))
	if _collected:
		set_interactive_enabled(false)


## 在 actor 及其祖先的子节点中查找背包。
static func resolve_inventory(actor: Node) -> Inventory:
	var node: Node = actor
	while node != null:
		for child in node.get_children():
			if child is Inventory:
				return child
		node = node.get_parent()
	return null
