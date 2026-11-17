class_name WorldEventDefinition
extends Resource
## 世界事件定义（docs/vertical-slice-completion.md §4）。
##
## 只读设计数据：触发条件、持续时间、冷却。
## 运行状态存在 GameState.world_events 里，两者分离——
## 改条件不会清掉玩家的进度，改进度也不会改设计。

## 事件 ID，存档键。稳定 ID，不能用运行时实例 ID。
@export var event_id: StringName = &""
## 显示名。
@export var display_name: String = ""
## 触发条件。每项是 {"type": ..., ...}，类型见 WorldEventManager 的求值器。
@export var conditions: Array[Dictionary] = []
## 条件不再满足后，事件再维持多久（分钟）。
## 0 表示条件一失效就结束。涨水事件靠它实现「雨停后 3 分钟才退水」。
@export var linger_minutes: float = 0.0
## 触发后进入冷却，持续（分钟）。冷却期内不再触发。
@export var cooldown_minutes: float = 60.0
## 一次性事件：结束后进入 COMPLETED 终态，不再重复。
@export var one_shot: bool = false
