class_name QuestObjective
extends Resource
## 任务目标（docs/technical-design.md §4.4）。
##
## 目标由「领域事件 + 目标标识」驱动，例如：
##   event_type = &"item.collected"   target = &"fuse"   amount = 1
##   event_type = &"device.repaired"  target = &"camp_radio"  amount = 1
##   event_type = &"camp.returned"    target = &"camp"  amount = 1

@export var id: StringName = &""
## 对应 EventBus 上的事件类型名，例如 item.collected。
@export var event_type: StringName = &""
## 事件载荷中的目标标识，例如物品 ID、对象 ID、营地 ID。
@export var target: StringName = &""
@export var amount: int = 1
@export_multiline var description: String = ""
