class_name WorldEventManager
extends Node
## 世界事件管理器（docs/vertical-slice-completion.md §4）。
##
## 每 0.5 秒求值一次所有事件的触发条件，驱动
## IDLE → ACTIVE → COOLDOWN 的状态流转。
##
## 事件的表现由「效果节点」自己实现：节点注册到 world_event_effect 分组，
## 并声明自己响应的 event_id。管理器不关心表现怎么做，
## 只负责在事件开始与结束时通知它们。
##
## 状态存在 GameState.world_events 里，读档后按存档继续。

enum State { IDLE, ACTIVE, COOLDOWN, COMPLETED }

## 事件定义资源。
const EVENT_DEFINITIONS := [
	"res://resources/events/night_bloom.tres",
	"res://resources/events/creek_surge.tres",
]

## 效果节点所在的分组。
const EFFECT_GROUP := &"world_event_effect"

## 条件求值间隔（秒）。0.5 秒是为了让「夜间开始」这类窗口切换体感及时，
## 又不至于每帧求值。
const EVAL_INTERVAL := 0.5

## 时间与天气变化时的即时重算间隔下限。
const WEATHER_SETTLE_SECONDS := 3.0

@export var eval_interval: float = EVAL_INTERVAL

var _definitions: Array[WorldEventDefinition] = []
var _player_regions: Dictionary = {}    # location_id → true
var _weather_since: float = 0.0          # 当前天气开始的时间戳
var _fail_since: Dictionary = {}         # event_id → 条件失效的时间戳
var _timer: float = 0.0
var _settle_timer: float = 0.0


func _ready() -> void:
	add_to_group(&"world_event_manager")
	_load_definitions()
	EventBus.location_entered.connect(_on_location_entered)
	EventBus.location_exited.connect(_on_location_exited)
	EventBus.weather_changed.connect(_on_weather_changed)
	_weather_since = _now()
	GameLog.info("世界事件管理器就绪", {"count": _definitions.size()})


func _process(delta: float) -> void:
	_timer -= delta
	_settle_timer = maxf(0.0, _settle_timer - delta)
	if _timer > 0.0:
		return
	# 天气刚变时加快求值：「下雨满 3 分钟」这类条件不该等满一个周期才生效
	_timer = eval_interval if _settle_timer <= 0.0 else minf(eval_interval, 0.1)
	_evaluate()


# ------------------------------------------------------------------ 条件求值

## 求值所有事件的条件并推进状态机。
func _evaluate() -> void:
	for definition in _definitions:
		if definition == null or definition.event_id == &"":
			continue
		match _state_of(definition.event_id):
			State.COMPLETED:
				continue
			State.ACTIVE:
				_update_active(definition)
			State.COOLDOWN:
				if _cooldown_elapsed(definition):
					_set_state(definition, State.IDLE)
					if _conditions_met(definition):
						_start_event(definition)
			State.IDLE:
				if _conditions_met(definition):
					_start_event(definition)


## 活跃中的事件：条件掉了还要再撑一会儿（linger），才真正结束。
func _update_active(definition: WorldEventDefinition) -> void:
	if _conditions_met(definition):
		_fail_since.erase(definition.event_id)
		return

	var now := _now()
	if not _fail_since.has(definition.event_id):
		_fail_since[definition.event_id] = now
		return
	var linger := definition.linger_minutes * 60.0
	if now - float(_fail_since[definition.event_id]) >= linger:
		_end_event(definition, &"conditions_lost")


func _conditions_met(definition: WorldEventDefinition) -> bool:
	for condition in definition.conditions:
		if not _check_condition(condition):
			return false
	return true


func _check_condition(condition: Dictionary) -> bool:
	match String(condition.get("type", "")):
		"time_window":
			return _in_time_window(
				float(condition.get("from", 0.0)),
				float(condition.get("to", 0.0)),
				GameState.time_of_day_minutes)
		"weather":
			var allow: Variant = condition.get("allow", [])
			if not (allow is Array):
				return false
			for item in allow:
				if String(item) == String(GameState.weather_id):
					return true
			return false
		"weather_duration":
			if String(condition.get("weather", "")) != String(GameState.weather_id):
				return false
			return _weather_elapsed() >= float(condition.get("minutes", 0.0)) * 60.0
		"player_in_region":
			var region := StringName(condition.get("region", &""))
			return bool(_player_regions.get(region, false))
		"quest":
			return _check_quest_condition(condition)
		"world_flag":
			var flag := StringName(condition.get("flag", &""))
			return GameState.get_flag(flag, bool(condition.get("value", true)))
	return false


## 时间窗口。from > to 表示跨零点，例如 21:00 → 04:00。
func _in_time_window(from_minutes: float, to_minutes: float, now_minutes: float) -> bool:
	if from_minutes <= to_minutes:
		return now_minutes >= from_minutes and now_minutes <= to_minutes
	return now_minutes >= from_minutes or now_minutes <= to_minutes


func _check_quest_condition(condition: Dictionary) -> bool:
	var manager := get_tree().get_first_node_in_group(&"quest_manager") as QuestManager
	if manager == null:
		return false
	var quest_id := StringName(condition.get("quest_id", &""))
	var wanted := String(condition.get("state", "in_progress"))
	var state := manager.get_state(quest_id)
	if state == null:
		return wanted == "not_started"
	match wanted:
		"completed":
			return state.is_completed
		"not_started":
			return false
		_:
			return not state.is_completed


# ------------------------------------------------------------------ 状态流转

func _start_event(definition: WorldEventDefinition) -> void:
	_set_state(definition, State.ACTIVE)
	_apply_effect(definition, true)
	EventBus.world_event_started.emit(definition.event_id)
	GameLog.info("世界事件开始", {"event": definition.event_id})


func _end_event(definition: WorldEventDefinition, reason: StringName) -> void:
	if definition.one_shot:
		_set_state(definition, State.COMPLETED)
	else:
		_set_state(definition, State.COOLDOWN)
	_apply_effect(definition, false)
	EventBus.world_event_ended.emit(definition.event_id, reason)
	GameLog.info("世界事件结束", {"event": definition.event_id, "reason": reason})


## 通知效果节点。节点自己声明响应的 event_id，管理器不关心表现细节。
func _apply_effect(definition: WorldEventDefinition, active: bool) -> void:
	for node in get_tree().get_nodes_in_group(EFFECT_GROUP):
		var effect := node as Node
		if effect == null:
			continue
		if StringName(effect.get("event_id")) != definition.event_id:
			continue
		if effect.has_method("apply_world_event"):
			effect.call("apply_world_event", definition.event_id, active)


func _state_of(event_id: StringName) -> int:
	return int(GameState.get_world_event_state(event_id).get("state", State.IDLE))


func _set_state(definition: WorldEventDefinition, new_state: int) -> void:
	var data := GameState.get_world_event_state(definition.event_id)
	data["state"] = new_state
	data["completed"] = new_state == State.COMPLETED
	match new_state:
		State.ACTIVE:
			data["active_since"] = _now()
		State.COOLDOWN:
			data["cooldown_until"] = _now() + definition.cooldown_minutes * 60.0
		_:
			pass
	GameState.set_world_event_state(definition.event_id, data)


func _cooldown_elapsed(definition: WorldEventDefinition) -> bool:
	var data := GameState.get_world_event_state(definition.event_id)
	var until := float(data.get("cooldown_until", 0.0))
	if until <= 0.0:
		return true
	return _now() >= until


# ------------------------------------------------------------------ 外部信号

func _on_location_entered(location_id: StringName) -> void:
	_player_regions[location_id] = true


func _on_location_exited(location_id: StringName) -> void:
	_player_regions.erase(location_id)


func _on_weather_changed(new_weather: StringName) -> void:
	_weather_since = _now()
	# 天气一变就重算：下雨满 3 分钟这类条件不能等下一个 0.5 秒周期才生效。
	_settle_timer = WEATHER_SETTLE_SECONDS


func _weather_elapsed() -> float:
	return _now() - _weather_since


func _now() -> float:
	return Time.get_unix_time_from_system()


# ------------------------------------------------------------------ 装载

func _load_definitions() -> void:
	_definitions.clear()
	for path in EVENT_DEFINITIONS:
		if not ResourceLoader.exists(path):
			GameLog.warn("世界事件定义资源不存在", {"path": path})
			continue
		var definition := load(path) as WorldEventDefinition
		if definition == null:
			GameLog.error("世界事件定义资源类型不正确", {"path": path})
			continue
		_definitions.append(definition)


## 供测试用：直接求值某个事件的条件，不改变状态。
func conditions_met_for(event_id: StringName) -> bool:
	for definition in _definitions:
		if definition != null and definition.event_id == event_id:
			return _conditions_met(definition)
	return false


## 供测试用：强制触发一个事件。
func force_start(event_id: StringName) -> bool:
	for definition in _definitions:
		if definition != null and definition.event_id == event_id:
			_start_event(definition)
			return true
	return false


## 供测试用：强制结束一个事件。
func force_end(event_id: StringName, reason: StringName = &"forced") -> bool:
	for definition in _definitions:
		if definition != null and definition.event_id == event_id:
			_end_event(definition, reason)
			return true
	return false


## 供测试用：把当前天气的起始时间往前推，模拟「已经下了多久雨」。
func shift_weather_start(seconds: float) -> void:
	_weather_since -= seconds
