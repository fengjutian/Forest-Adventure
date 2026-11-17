class_name HUD
extends CanvasLayer
## 抬头显示：交互提示、生命与体力、当前目标、调试信息。
##
## HUD 只在需要时显示信息，避免持续遮挡画面（docs/combat-and-progression.md §3）。

@onready var interaction_prompt: Label = $InteractionPrompt
@onready var health_bar: ProgressBar = $HealthBar
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var status_label: Label = $StatusLabel
@onready var quest_label: Label = $QuestLabel
@onready var debug_overlay: Label = $DebugOverlay
@onready var resume_hint: Label = $ResumeHint

var _player: Player
var _quest_manager: QuestManager


func _ready() -> void:
	EventBus.interaction_target_changed.connect(_on_target_changed)
	EventBus.health_changed.connect(_on_health_changed)
	EventBus.stamina_changed.connect(_on_stamina_changed)
	EventBus.player_state_changed.connect(_on_player_state_changed)
	EventBus.quest_stage_changed.connect(_on_quest_stage_changed)
	EventBus.quest_completed.connect(_on_quest_completed)

	_player = get_tree().get_first_node_in_group(&"player") as Player
	_quest_manager = get_tree().get_first_node_in_group(&"quest_manager") as QuestManager

	interaction_prompt.text = ""
	resume_hint.visible = false

	# Player 的 _ready 可能早于 HUD，首帧不会收到 health/stamina 广播，这里主动同步一次
	_sync_from_player()


func _sync_from_player() -> void:
	if _player == null:
		return
	health_bar.max_value = _player.tuning.max_health
	health_bar.value = _player.health
	stamina_bar.max_value = _player.tuning.max_stamina
	stamina_bar.value = _player.stamina
	status_label.text = "状态：%s" % _player.state_machine.state_name(_player.state_machine.current_state)


func _process(_delta: float) -> void:
	_update_quest_line()
	_update_debug_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		resume_hint.visible = true
	elif event is InputEventMouseButton and event.is_pressed():
		resume_hint.visible = false


func _on_target_changed(target: Node) -> void:
	if target == null:
		interaction_prompt.text = ""
		return

	var actor := _player
	var prompt := "交互"
	if target.has_method("get_prompt"):
		prompt = String(target.get_prompt(actor))
	interaction_prompt.text = prompt


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current


func _on_stamina_changed(current: float, maximum: float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current


func _on_player_state_changed(state_name: StringName) -> void:
	status_label.text = "状态：%s" % state_name


func _on_quest_stage_changed(_quest_id: StringName, stage_index: int, _stage_id: StringName) -> void:
	_update_quest_line()


func _on_quest_completed(quest_id: StringName) -> void:
	quest_label.text = "任务完成：%s" % quest_id


func _update_quest_line() -> void:
	if _quest_manager == null:
		quest_label.text = ""
		return

	var active := _quest_manager.get_active_quests()
	if active.is_empty():
		quest_label.text = ""
		return

	var quest_id: StringName = active[0]
	var definition := _quest_manager.get_definition(quest_id)
	var title := definition.title if definition != null else String(quest_id)
	quest_label.text = "当前目标：%s" % _quest_manager.get_current_objective_text(quest_id)


func _update_debug_overlay() -> void:
	var lines: Array[String] = []
	lines.append("FPS %d" % Engine.get_frames_per_second())

	if _player != null:
		var position := _player.global_position
		lines.append("位置 %.1f / %.1f / %.1f" % [position.x, position.y, position.z])
		lines.append("速度 %.2f" % _player.velocity.length())

	lines.append("时间 %s" % GameState.get_time_string())
	lines.append("天气 %s" % GameState.weather_id)

	debug_overlay.text = "\n".join(lines)
