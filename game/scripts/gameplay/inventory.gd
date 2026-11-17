class_name Inventory
extends Node
## 背包：有限槽位制（docs/game-design.md §6.2）。
##
## 任务关键物品不占普通槽位——由 is_quest_item 标记，存入时单独计数。

signal changed()
signal item_added(item_id: StringName, amount: int)
signal item_removed(item_id: StringName, amount: int)

## 普通槽位上限。
@export var capacity: int = 12

## 任务关键物品，独立于普通槽位。
@export var quest_item_capacity: int = 4

var _slots: Array = []          # Array[Dictionary]: {id: StringName, amount: int}
var _quest_slots: Array = []    # Array[Dictionary]: {id: StringName, amount: int}


## 物品定义库。灰色盒阶段允许未注册物品，按 max_stack = 1 处理。
var _definitions: Dictionary = {}


func register_definition(definition: ItemDefinition) -> void:
	if definition == null or definition.id == &"":
		return
	_definitions[definition.id] = definition


func get_definition(item_id: StringName) -> ItemDefinition:
	return _definitions.get(item_id, null)


func is_stackable(item_id: StringName) -> bool:
	var definition := get_definition(item_id)
	return definition != null and definition.max_stack > 1


## 任务关键物品不占普通槽位。
func is_quest_item(item_id: StringName) -> bool:
	var definition := get_definition(item_id)
	if definition == null:
		return false
	return definition.tags.has(&"quest_item")


## 返回实际放入的数量。
func add_item(item_id: StringName, amount: int = 1) -> int:
	if amount <= 0:
		return 0

	var target_slots := _quest_slots if is_quest_item(item_id) else _slots
	var limit := quest_item_capacity if is_quest_item(item_id) else capacity

	var remaining := amount
	var max_stack := 1
	var definition := get_definition(item_id)
	if definition != null:
		max_stack = maxi(1, definition.max_stack)

	# 先填充已有槽位
	for slot in target_slots:
		if slot["id"] == item_id and int(slot["amount"]) < max_stack:
			var space: int = max_stack - int(slot["amount"])
			var take: int = mini(space, remaining)
			slot["amount"] = int(slot["amount"]) + take
			remaining -= take
			if remaining <= 0:
				break

	# 再占用空槽位
	while remaining > 0 and target_slots.size() < limit:
		var take := mini(max_stack, remaining)
		target_slots.append({"id": item_id, "amount": take})
		remaining -= take

	var added := amount - remaining
	if added > 0:
		changed.emit()
		item_added.emit(item_id, added)
	return added


func remove_item(item_id: StringName, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if count_item(item_id) < amount:
		return false

	var remaining := amount
	for slots: Array in [_slots, _quest_slots]:
		for i in range(slots.size() - 1, -1, -1):
			if remaining <= 0:
				break
			var slot: Dictionary = slots[i]
			if slot["id"] != item_id:
				continue
			var take: int = mini(int(slot["amount"]), remaining)
			slot["amount"] = int(slot["amount"]) - take
			remaining -= take
			if int(slot["amount"]) <= 0:
				slots.remove_at(i)

	if remaining <= 0:
		changed.emit()
		item_removed.emit(item_id, amount - remaining)
		return true
	return false


func has_item(item_id: StringName, amount: int = 1) -> bool:
	return count_item(item_id) >= amount


func count_item(item_id: StringName) -> int:
	var total := 0
	for slots: Array in [_slots, _quest_slots]:
		for slot in slots:
			if slot["id"] == item_id:
				total += int(slot["amount"])
	return total


func is_full() -> bool:
	return _slots.size() >= capacity


func clear() -> void:
	_slots.clear()
	_quest_slots.clear()
	changed.emit()


func get_slots() -> Array:
	return _slots.duplicate(true)


func get_quest_slots() -> Array:
	return _quest_slots.duplicate(true)


# ------------------------------------------------------------------ 存档

func to_dict() -> Dictionary:
	return {
		"capacity": capacity,
		"slots": _slots.duplicate(true),
		"quest_slots": _quest_slots.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	capacity = int(data.get("capacity", capacity))
	_slots = (data.get("slots", []) as Array).duplicate(true)
	_quest_slots = (data.get("quest_slots", []) as Array).duplicate(true)
	changed.emit()
