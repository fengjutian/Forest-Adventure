class_name QuestManager
extends Node
## 任务管理器（docs/technical-design.md §4.4）：监听领域事件并更新 QuestState。
##
## 事件流：
##   交互对象 → EventBus.<事件> → QuestManager 更新阶段 → EventBus.quest_stage_changed
##
## 任务定义通过 register_quest 注册；运行状态随存档持久化。

## StringName → QuestDefinition
var _definitions: Dictionary = {}
## StringName → QuestState
var _states: Dictionary = {}
## 处于进行中的任务 ID。
var _active: Array = []


func _ready() -> void:
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.location_entered.connect(_on_location_entered)
	EventBus.object_inspected.connect(_on_object_inspected)
	EventBus.device_repaired.connect(_on_device_repaired)
	EventBus.camp_returned.connect(_on_camp_returned)

	SaveManager.register_provider("quest_states", Callable(self, "to_dict"))
	SaveManager.register_loader("quest_states", Callable(self, "from_dict"))

	GameLog.info("QuestManager 就绪")


## 离树时注销存档回调。
##
## SaveManager 是常驻 autoload，它持有的 Callable 指向本节点。
## 不注销的话，本节点先被释放、autoload 后释放，Godot 关闭阶段
## 解析这些悬空 Callable 会触发访问冲突（测试退出码偶发 0xC0000005）。
func _exit_tree() -> void:
	if SaveManager != null:
		SaveManager.unregister("quest_states")


# ------------------------------------------------------------------ 注册与开始

func register_quest(definition: QuestDefinition) -> void:
	if definition == null or definition.id == &"":
		GameLog.warn("忽略无效任务定义")
		return
	_definitions[definition.id] = definition
	if definition.auto_start and not _states.has(definition.id):
		start_quest(definition.id)


func start_quest(quest_id: StringName) -> void:
	if not _definitions.has(quest_id):
		GameLog.error("任务定义未注册", {"quest": quest_id})
		return
	if _states.has(quest_id):
		return

	var state := QuestState.create(quest_id)
	_states[quest_id] = state
	_active.append(quest_id)

	EventBus.quest_started.emit(quest_id)
	GameLog.info("任务开始", {"quest": quest_id})

	var definition: QuestDefinition = _definitions[quest_id]
	if definition.stages.size() > 0:
		var stage: QuestStage = definition.stages[0]
		EventBus.quest_stage_changed.emit(quest_id, 0, stage.id)


func get_definition(quest_id: StringName) -> QuestDefinition:
	return _definitions.get(quest_id, null)


func get_state(quest_id: StringName) -> QuestState:
	return _states.get(quest_id, null)


func get_active_quests() -> Array:
	return _active.duplicate()


func is_quest_completed(quest_id: StringName) -> bool:
	var state := get_state(quest_id)
	return state != null and state.is_completed


## 当前阶段的玩家提示文本。
func get_current_objective_text(quest_id: StringName) -> String:
	var definition := get_definition(quest_id)
	var state := get_state(quest_id)
	if definition == null or state == null or state.is_completed:
		return ""

	if state.current_stage >= definition.stages.size():
		return ""

	var stage: QuestStage = definition.stages[state.current_stage]
	var pending := _pending_objectives(stage, state)
	if pending.is_empty():
		return stage.description

	var objective: QuestObjective = pending[0]
	var text := objective.description if not objective.description.is_empty() else stage.description
	if objective.amount > 1:
		var progress := state.objective_progress_of(objective.id)
		text += "  (%d/%d)" % [progress, objective.amount]
	return text


func _pending_objectives(stage: QuestStage, state: QuestState) -> Array:
	var pending := []
	for objective in stage.objectives:
		var obj: QuestObjective = objective
		if not state.is_objective_completed(obj.id):
			pending.append(obj)
	return pending


# ------------------------------------------------------------------ 事件接入

func _on_item_collected(item_id: StringName, amount: int) -> void:
	_apply_event(&"item.collected", item_id, amount)


func _on_location_entered(location_id: StringName) -> void:
	_apply_event(&"location.entered", location_id, 1)


func _on_object_inspected(object_id: StringName) -> void:
	_apply_event(&"object.inspected", object_id, 1)


func _on_device_repaired(device_id: StringName) -> void:
	_apply_event(&"device.repaired", device_id, 1)


func _on_camp_returned(camp_id: StringName) -> void:
	_apply_event(&"camp.returned", camp_id, 1)


func _apply_event(event_type: StringName, target: StringName, amount: int) -> void:
	for quest_id in _active.duplicate():
		var state: QuestState = _states.get(quest_id, null)
		var definition: QuestDefinition = _definitions.get(quest_id, null)
		if state == null or definition == null or state.is_completed:
			continue
		if state.current_stage >= definition.stages.size():
			continue

		var stage: QuestStage = definition.stages[state.current_stage]
		var stage_complete := true

		for objective in stage.objectives:
			var obj: QuestObjective = objective
			if state.is_objective_completed(obj.id):
				continue

			if obj.event_type == event_type and obj.target == target:
				var progress := state.objective_progress_of(obj.id) + amount
				state.objective_progress[obj.id] = progress
				if progress >= obj.amount:
					state.completed_objectives[obj.id] = true
					EventBus.quest_objective_completed.emit(quest_id, obj.id)
					GameLog.info("任务目标完成", {"quest": quest_id, "objective": obj.id})

			if not state.is_objective_completed(obj.id):
				stage_complete = false

		if stage_complete:
			_advance_stage(quest_id)


func _advance_stage(quest_id: StringName) -> void:
	var state: QuestState = _states[quest_id]
	var definition: QuestDefinition = _definitions[quest_id]
	state.current_stage += 1

	if state.current_stage >= definition.stages.size():
		state.is_completed = true
		state.completed_at = int(Time.get_unix_time_from_system())
		_active.erase(quest_id)
		EventBus.quest_completed.emit(quest_id)
		GameLog.info("任务完成", {"quest": quest_id})
		return

	var stage: QuestStage = definition.stages[state.current_stage]
	EventBus.quest_stage_changed.emit(quest_id, state.current_stage, stage.id)
	GameLog.info("任务进入新阶段", {"quest": quest_id, "stage": stage.id})


# ------------------------------------------------------------------ 存档

func to_dict() -> Dictionary:
	var states := {}
	for quest_id in _states:
		var state: QuestState = _states[quest_id]
		states[String(quest_id)] = state.to_dict()
	return {
		"quest_states": states,
		"active": _active.duplicate(),
	}


func from_dict(data: Dictionary) -> void:
	var saved: Dictionary = data.get("quest_states", {})
	_states.clear()
	_active = (data.get("active", []) as Array).duplicate()

	for key in saved:
		var state := QuestState.new()
		state.from_dict(saved[key])
		_states[StringName(key)] = state

	GameLog.info("任务状态已恢复", {"count": _states.size(), "active": _active.size()})
