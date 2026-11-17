class_name QuestState
extends RefCounted
## 任务运行状态（docs/technical-design.md §4.4）：当前阶段、已完成目标和时间戳。

var quest_id: StringName = &""
var current_stage: int = 0
## objective_id → bool
var completed_objectives: Dictionary = {}
## objective_id → 已累计进度
var objective_progress: Dictionary = {}
var started_at: int = 0
var completed_at: int = 0
var is_completed: bool = false


static func create(p_quest_id: StringName) -> QuestState:
	var state := QuestState.new()
	state.quest_id = p_quest_id
	state.started_at = int(Time.get_unix_time_from_system())
	return state


func is_objective_completed(objective_id: StringName) -> bool:
	return completed_objectives.has(objective_id)


func objective_progress_of(objective_id: StringName) -> int:
	return int(objective_progress.get(objective_id, 0))


func to_dict() -> Dictionary:
	return {
		"quest_id": String(quest_id),
		"current_stage": current_stage,
		"completed_objectives": completed_objectives.duplicate(true),
		"objective_progress": objective_progress.duplicate(true),
		"started_at": started_at,
		"completed_at": completed_at,
		"is_completed": is_completed,
	}


func from_dict(data: Dictionary) -> void:
	quest_id = StringName(data.get("quest_id", ""))
	current_stage = int(data.get("current_stage", 0))
	completed_objectives = (data.get("completed_objectives", {}) as Dictionary).duplicate(true)
	objective_progress = (data.get("objective_progress", {}) as Dictionary).duplicate(true)
	started_at = int(data.get("started_at", 0))
	completed_at = int(data.get("completed_at", 0))
	is_completed = bool(data.get("is_completed", false))
