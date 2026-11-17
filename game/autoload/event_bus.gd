extends Node
## 全局领域事件总线。
##
## 模块之间通过信号或 EventBus 传递领域事件，避免节点路径硬编码
## （docs/technical-design.md §4.1）。
##
## 事件命名与载荷遵循 docs/technical-design.md §4.4 的约定：
##   item.collected / location.entered / object.inspected / device.repaired / camp.returned

# ---------------------------------------------------------------- 物品
signal item_collected(item_id: StringName, amount: int)
signal item_consumed(item_id: StringName, amount: int)
signal inventory_changed()

# ---------------------------------------------------------------- 交互
signal object_interacted(object_id: StringName)
signal object_inspected(object_id: StringName)
signal interaction_target_changed(target: Node)

# ---------------------------------------------------------------- 世界
signal location_entered(location_id: StringName)
signal location_exited(location_id: StringName)
signal device_repaired(device_id: StringName)
signal camp_returned(camp_id: StringName)

# ---------------------------------------------------------------- 任务
signal quest_started(quest_id: StringName)
signal quest_stage_changed(quest_id: StringName, stage_index: int, stage_id: StringName)
signal quest_objective_completed(quest_id: StringName, objective_id: StringName)
signal quest_completed(quest_id: StringName)

# ---------------------------------------------------------------- 玩家状态
signal player_state_changed(state_name: StringName)
signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal flashlight_toggled(is_on: bool)
signal player_died()

# ---------------------------------------------------------------- 存档
signal game_saved(slot: int)
signal game_loaded(slot: int)
signal save_failed(reason: String)
