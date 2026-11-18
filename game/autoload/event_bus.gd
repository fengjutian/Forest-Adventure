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
## 天气切换。世界事件的条件依赖它，所以走全局总线而不是只在控制器上发。
signal weather_changed(new_weather: StringName)

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

# ---------------------------------------------------------------- 战斗
## 蓄力进度 0~1，0 表示未在蓄力。
signal bow_charge_changed(charge: float)
## 命中反馈，weakpoint 为真表示打在弱点。
signal hit_confirmed(weakpoint: bool)
signal enemy_health_changed(enemy_name: String, current: float, maximum: float)
## 弱点被观察到。守卫型敌人的弱点需要先看清才生效。
signal weak_point_discovered(enemy_name: String)
## 威胁等级 0~1，用于 HUD 的敌人提示。
signal enemy_threat_changed(threat_level: float)

# ---------------------------------------------------------------- 世界事件
signal world_event_started(event_id: StringName)
signal world_event_ended(event_id: StringName, reason: StringName)

# ---------------------------------------------------------------- 隐藏地点
signal location_discovered(location_id: StringName, display_name: String)
signal location_reward_claimed(location_id: StringName, item_id: StringName)

# ---------------------------------------------------------------- 存档
signal game_saved(slot: int)
signal game_loaded(slot: int)
signal save_failed(reason: String)
