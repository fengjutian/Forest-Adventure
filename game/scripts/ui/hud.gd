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
@onready var crosshair: Crosshair = $Crosshair
@onready var ammo_label: Label = $AmmoLabel
@onready var charge_bar: ProgressBar = $ChargeBar
@onready var hit_marker: Label = $HitMarker
@onready var enemy_name: Label = $EnemyName
@onready var enemy_bar: ProgressBar = $EnemyBar

var _player: Player
var _quest_manager: QuestManager
var _hit_marker_timer: float = 0.0
var _threat_timer: float = 0.0


func _ready() -> void:
	EventBus.interaction_target_changed.connect(_on_target_changed)
	EventBus.health_changed.connect(_on_health_changed)
	EventBus.stamina_changed.connect(_on_stamina_changed)
	EventBus.player_state_changed.connect(_on_player_state_changed)
	EventBus.quest_stage_changed.connect(_on_quest_stage_changed)
	EventBus.quest_completed.connect(_on_quest_completed)
	EventBus.ammo_changed.connect(_on_ammo_changed)
	EventBus.bow_charge_changed.connect(_on_bow_charge_changed)
	EventBus.hit_confirmed.connect(_on_hit_confirmed)
	EventBus.enemy_health_changed.connect(_on_enemy_health_changed)

	_player = get_tree().get_first_node_in_group(&"player") as Player
	_quest_manager = get_tree().get_first_node_in_group(&"quest_manager") as QuestManager

	interaction_prompt.text = ""
	resume_hint.visible = false
	charge_bar.visible = false
	hit_marker.modulate.a = 0.0
	enemy_name.visible = false
	enemy_bar.visible = false

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
	_update_focus_hint()
	_update_hit_marker(_delta)
	_update_bow_state()
	_update_threat()


func _update_bow_state() -> void:
	if _player == null:
		return
	var bow := _player.get_node_or_null("Bow") as Bow
	if bow == null:
		return
	crosshair.set_aiming(bow.is_aiming())
	crosshair.set_charge(bow.get_charge())


## 命中标记短暂显示。
func _update_hit_marker(delta: float) -> void:
	if _hit_marker_timer <= 0.0:
		return
	_hit_marker_timer = maxf(0.0, _hit_marker_timer - delta)
	var alpha := clampf(_hit_marker_timer / 0.25, 0.0, 1.0)
	hit_marker.modulate.a = alpha


## 敌人威胁提示：只显示正在威胁玩家的那一只。
func _update_threat() -> void:
	if _player == null:
		return
	var worst: EnemyBase = null
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as EnemyBase
		if enemy == null or not enemy.is_threatening():
			continue
		if worst == null or enemy.global_position.distance_to(_player.global_position) \
				< worst.global_position.distance_to(_player.global_position):
			worst = enemy

	if worst == null:
		if _threat_timer > 0.0:
			_threat_timer = maxf(0.0, _threat_timer - get_process_delta_time())
		if _threat_timer <= 0.0:
			enemy_name.visible = false
			enemy_bar.visible = false
		return

	_threat_timer = 2.5
	enemy_name.visible = true
	enemy_bar.visible = true
	enemy_name.text = "%s · 生命 %.0f" % [worst.display_name, worst.get_health()]
	enemy_bar.max_value = worst.max_health
	enemy_bar.value = worst.get_health()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		release_mouse_hint()


## 鼠标未被捕获时提示玩家点击画面，Esc 归还鼠标。
func _update_focus_hint() -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	resume_hint.visible = not captured
	if not captured:
		resume_hint.text = "点击画面控制视角　·　Esc 释放鼠标"


func release_mouse_hint() -> void:
	resume_hint.visible = true
	resume_hint.text = "点击画面控制视角　·　Esc 释放鼠标"


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


func _on_ammo_changed(_item_id: StringName, count: int) -> void:
	ammo_label.text = "箭矢 %d" % count


func _on_bow_charge_changed(charge: float) -> void:
	charge_bar.visible = charge > 0.0
	charge_bar.value = charge * 100.0


func _on_hit_confirmed(weakpoint: bool) -> void:
	_hit_marker_timer = 0.25
	hit_marker.modulate = Color(1.0, 0.45, 0.35) if weakpoint else Color(1.0, 1.0, 1.0)
	hit_marker.modulate.a = 1.0


func _on_enemy_health_changed(_enemy_name: String, _current: float, _maximum: float) -> void:
	pass


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
