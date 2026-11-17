class_name LocationTrigger
extends Area3D
## 区域触发器。进入 / 离开时发出 location.entered / location.exited。
##
## 兼做隐藏地点的发现点（docs/vertical-slice-completion.md §3）：
## discoverable 为 true 时，玩家第一次进入即视为「发现」，
## 发一次 location_discovered 并发放 reward_items。
##
## 普通区域触发器只设 location_id，不设 discoverable，行为与之前完全一致。

@export var location_id: StringName = &""
## 发现时显示的地点名。留空则回退到 location_id。
@export var display_name: String = ""
## 是否是隐藏地点。true = 第一次进入即触发发现流程。
@export var discoverable: bool = false
## 发现时一次性发放的物品。格式：[{id: StringName, amount: int}]。
@export var reward_items: Array[Dictionary] = []
## 发现时展示的世界观文本。
@export_multiline var discovery_text: String = ""


func _ready() -> void:
	add_to_group(&"location_trigger")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		EventBus.location_entered.emit(location_id)
		GameLog.info("进入区域", {"location": location_id})
		if discoverable:
			_discover()


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		EventBus.location_exited.emit(location_id)


## 发现隐藏地点。已经发现过就直接返回：奖励只发一次。
func _discover() -> void:
	if GameState.is_location_discovered(location_id):
		return
	GameState.mark_location_discovered(location_id)

	var name_text := display_name if display_name != "" else String(location_id)
	EventBus.location_discovered.emit(location_id, name_text)
	GameLog.info("发现隐藏地点", {"location": location_id, "name": name_text})

	for reward in reward_items:
		var item_id := StringName(reward.get("id", &""))
		var amount := int(reward.get("amount", 1))
		if item_id == &"" or amount <= 0:
			continue
		if not _grant(item_id, amount):
			continue
		EventBus.location_reward_claimed.emit(location_id, item_id)


## 把物品发进背包。背包满或找不到背包时记警告，不吞掉事件。
func _grant(item_id: StringName, amount: int) -> bool:
	var inventory := get_tree().get_first_node_in_group(&"inventory") as Inventory
	if inventory == null:
		GameLog.warn("找不到背包，隐藏地点奖励未发放", {"location": location_id, "item": item_id})
		return false
	var added := inventory.add_item(item_id, amount)
	if added <= 0:
		GameLog.warn("背包已满，隐藏地点奖励未发放", {"location": location_id, "item": item_id})
		return false
	return true
