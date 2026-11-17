class_name PlayerStateMachine
extends Node
## 玩家状态机（docs/technical-design.md §4.2）。
##
## 状态至少包含 Grounded / Sprinting / Crouching / Airborne / Disabled。
## 状态切换只经由 transition_to，避免脚本各处直接改状态导致不可追踪。

enum State {
	GROUNDED,
	SPRINTING,
	CROUCHING,
	AIRBORNE,
	DISABLED,
}

const STATE_NAMES := {
	State.GROUNDED: &"Grounded",
	State.SPRINTING: &"Sprinting",
	State.CROUCHING: &"Crouching",
	State.AIRBORNE: &"Airborne",
	State.DISABLED: &"Disabled",
}

signal state_changed(new_state: State, old_state: State)

var _current_state: State = State.GROUNDED

var current_state: State:
	get:
		return _current_state
	set(value):
		if value == _current_state:
			return
		var old := _current_state
		_current_state = value
		state_changed.emit(_current_state, old)
		EventBus.player_state_changed.emit(state_name(_current_state))


func state_name(state: State) -> StringName:
	return STATE_NAMES.get(state, &"Unknown")


func is_in(states: Array) -> bool:
	return states.has(_current_state)


func transition_to(state: State) -> void:
	current_state = state


## 恢复状态但不触发对外广播（读档时使用）。
func force_state(state: State) -> void:
	_current_state = state
	EventBus.player_state_changed.emit(state_name(_current_state))
