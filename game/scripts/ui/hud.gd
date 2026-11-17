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

## 按键提示：进游戏先自动显示几秒，之后按 H 开关。
const CONTROLS_HINT_SECONDS := 9.0
const TOGGLE_HELP_ACTION := &"toggle_help"
var _controls_panel: PanelContainer = null
var _controls_toggle: Label = null
var _controls_auto_timer: float = 0.0
## 玩家用 H 手动打开后，就不再自动收起。
var _controls_pinned: bool = false


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

	_build_controls_hint()
	_show_controls_hint(true)
	_controls_auto_timer = CONTROLS_HINT_SECONDS

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
	_update_controls_hint(_delta)


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
	if event.is_action_pressed(TOGGLE_HELP_ACTION):
		toggle_controls_hint()
		return
	if event.is_action_pressed("pause"):
		release_mouse_hint()


# ------------------------------------------------------------------ 按键提示

## 打开/关闭按键提示面板。手动打开后不再自动收起。
func toggle_controls_hint() -> void:
	if _controls_panel == null:
		return
	var next := not _controls_panel.visible
	_controls_pinned = next
	_controls_auto_timer = 0.0
	_show_controls_hint(next)


## 直接收起按键提示（截图、过场等场景用），不改变「玩家手动打开」状态。
func close_controls_hint() -> void:
	_controls_auto_timer = 0.0
	_show_controls_hint(false)


func _show_controls_hint(show: bool) -> void:
	if _controls_panel == null:
		return
	_controls_panel.visible = show
	if _controls_toggle != null:
		_controls_toggle.visible = not show


func _update_controls_hint(delta: float) -> void:
	if _controls_auto_timer <= 0.0:
		return
	_controls_auto_timer = maxf(0.0, _controls_auto_timer - delta)
	if _controls_auto_timer <= 0.0 and not _controls_pinned:
		_show_controls_hint(false)


## 把动作绑定的第一个按键转成可读文本；鼠标动作直接给中文。
func _binding_text(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
			var text := OS.get_keycode_string(code)
			if text == "Escape":
				text = "Esc"
			return text
		if event is InputEventMouseButton:
			var button := (event as InputEventMouseButton).button_index
			if button == MOUSE_BUTTON_LEFT:
				return "鼠标左键"
			if button == MOUSE_BUTTON_RIGHT:
				return "鼠标右键"
	return "?"


## 按键提示的内容：左列按键、右列动作，凑四列排成一张小表。
func _controls_entries() -> Array:
	var move := "%s %s %s %s" % [
		_binding_text(&"move_forward"), _binding_text(&"move_left"),
		_binding_text(&"move_back"), _binding_text(&"move_right"),
	]
	return [
		[move, "移动"],
		["鼠标", "转动视角"],
		[_binding_text(&"sprint"), "冲刺"],
		[_binding_text(&"crouch"), "下蹲"],
		[_binding_text(&"jump"), "跳跃"],
		[_binding_text(&"interact"), "交互 / 拾取"],
		[_binding_text(&"fire"), "按住蓄力射击"],
		[_binding_text(&"aim"), "按住举弓瞄准"],
		[_binding_text(&"flashlight"), "手电筒"],
		[_binding_text(&"inventory"), "背包"],
		[_binding_text(&"map"), "地图"],
		[_binding_text(&"compass"), "指南针"],
		["%s / %s" % [_binding_text(&"quick_save"), _binding_text(&"quick_load")], "快速存档 / 读档"],
		[_binding_text(&"pause"), "释放鼠标"],
	]


## 按键提示面板完全由代码搭建：内容来自输入映射，改键后不用同步改 UI。
func _build_controls_hint() -> void:
	var root := Control.new()
	root.name = "ControlsHint"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.07, 0.72)
	style.border_color = Color(1.0, 1.0, 1.0, 0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)

	var panel := PanelContainer.new()
	panel.name = "ControlsPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -24.0
	panel.offset_right = -24.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	_controls_panel = panel

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "按键提示"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.92, 0.95, 0.9))
	box.add_child(title)

	var grid := GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 5)
	box.add_child(grid)

	for entry in _controls_entries():
		var key := Label.new()
		key.text = String(entry[0])
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key.custom_minimum_size = Vector2(78.0, 0.0)
		key.add_theme_font_size_override("font_size", 13)
		key.add_theme_color_override("font_color", Color(0.96, 0.84, 0.58))
		grid.add_child(key)

		var action := Label.new()
		action.text = String(entry[1])
		action.add_theme_font_size_override("font_size", 13)
		action.add_theme_color_override("font_color", Color(0.86, 0.89, 0.86))
		grid.add_child(action)

	var footer := Label.new()
	footer.text = "%s 收起提示" % _binding_text(TOGGLE_HELP_ACTION)
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(0.7, 0.73, 0.7))
	box.add_child(footer)

	var toggle := Label.new()
	toggle.name = "ToggleHint"
	toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle.text = "%s 按键提示" % _binding_text(TOGGLE_HELP_ACTION)
	toggle.anchor_left = 1.0
	toggle.anchor_right = 1.0
	toggle.anchor_top = 0.0
	toggle.anchor_bottom = 0.0
	toggle.offset_left = -260.0
	toggle.offset_right = -24.0
	toggle.offset_top = 16.0
	toggle.offset_bottom = 40.0
	toggle.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toggle.add_theme_font_size_override("font_size", 13)
	toggle.modulate = Color(1.0, 1.0, 1.0, 0.55)
	root.add_child(toggle)
	_controls_toggle = toggle


## 鼠标未被捕获时提示玩家点击画面；窗口失焦时直接说明原因。
##
## 窗口失焦时 WASD 会被系统送到别的窗口，玩家只会看到「人不会动」，
## 所以这里把「窗口未聚焦」说清楚，而不是只提示点击鼠标。
func _update_focus_hint() -> void:
	var focused := DisplayServer.window_is_focused()
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	resume_hint.visible = not focused or not captured
	if not focused:
		resume_hint.text = "窗口未聚焦 — 点击游戏窗口继续"
	elif not captured:
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
	# 交互提示带上当前绑定键，改键后自动跟着变
	interaction_prompt.text = "[%s] %s" % [_binding_text(&"interact"), prompt]


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
