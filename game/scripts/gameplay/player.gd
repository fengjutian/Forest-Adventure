class_name Player
extends CharacterBody3D
## 第一人称控制器（docs/technical-design.md §4.2）。
##
## 节点结构：
##   Player (CharacterBody3D)
##   ├── CollisionShape3D
##   ├── Head (Node3D)
##   │   ├── Camera3D
##   │   ├── InteractionRay (RayCast3D)
##   │   ├── Flashlight (SpotLight3D)
##   │   └── AudioListener3D
##   ├── FootstepDetector (RayCast3D)
##   ├── StateMachine (Node)
##   └── InteractionSystem (Node)

@export var tuning: PlayerTuning

@onready var state_machine: PlayerStateMachine = $StateMachine
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Flashlight
@onready var footstep_detector: RayCast3D = $FootstepDetector
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

var health: float = 100.0
var stamina: float = 100.0
var flashlight_on: bool = false
var flashlight_battery: float = 100.0

var _capsule: CapsuleShape3D
var _crouching: bool = false
var _control_enabled: bool = true
var _fall_apex_y: float = 0.0
var _airborne: bool = false
var _last_stamina_broadcast: float = -1.0
var _last_health_broadcast: float = -1.0
var _stamina_regen_blocked: bool = false
var _stamina_regen_timer: float = 0.0


func _ready() -> void:
	if tuning == null:
		tuning = PlayerTuning.new()

	health = tuning.max_health
	stamina = tuning.max_stamina
	flashlight_battery = tuning.flashlight_battery_max

	# 复制一份胶囊体，避免修改共享的导入资源
	_capsule = (_collision_shape.shape as CapsuleShape3D).duplicate()
	_collision_shape.shape = _capsule
	_apply_body_size(false)

	state_machine.state_changed.connect(_on_state_changed)
	EventBus.player_died.connect(_on_died)

	_broadcast_health(true)
	_broadcast_stamina(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not _control_enabled:
		velocity.x = move_toward(velocity.x, 0.0, tuning.acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, tuning.acceleration * delta)
		move_and_slide()
		return

	_update_crouch()
	_update_stamina(delta)
	_update_flashlight(delta)
	_update_fall()
	_apply_gravity(delta)
	_update_movement(delta)
	move_and_slide()
	_update_state()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _control_enabled:
			_handle_look(event as InputEventMouseMotion)
		return

	if event is InputEventMouseButton and event.is_pressed():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			set_control_enabled(true)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event.is_action_pressed("jump") and _control_enabled and is_on_floor():
		velocity.y = tuning.jump_velocity

	if event.is_action_pressed("flashlight") and _control_enabled:
		toggle_flashlight()

	if event.is_action_pressed("pause"):
		set_control_enabled(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ 移动

func _handle_look(event: InputEventMouseMotion) -> void:
	var sensitivity: float = SettingsManager.mouse_sensitivity
	if sensitivity <= 0.0:
		sensitivity = tuning.mouse_sensitivity

	rotate_y(-event.relative.x * sensitivity)

	var pitch := -event.relative.y * sensitivity
	if SettingsManager.invert_y:
		pitch = -pitch
	var limit := deg_to_rad(tuning.max_pitch_degrees)
	head.rotation.x = clampf(head.rotation.x + pitch, -limit, limit)


func _update_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed := _target_speed()
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var acceleration := tuning.acceleration
	if not is_on_floor():
		acceleration *= tuning.air_control

	var target := direction * speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * tuning.gravity_scale * delta
	elif velocity.y < 0.0:
		velocity.y = -2.0


func _update_state() -> void:
	if not _control_enabled:
		state_machine.transition_to(PlayerStateMachine.State.DISABLED)
		return
	if not is_on_floor():
		state_machine.transition_to(PlayerStateMachine.State.AIRBORNE)
	elif _crouching:
		state_machine.transition_to(PlayerStateMachine.State.CROUCHING)
	elif _wants_sprint():
		state_machine.transition_to(PlayerStateMachine.State.SPRINTING)
	else:
		state_machine.transition_to(PlayerStateMachine.State.GROUNDED)


# ------------------------------------------------------------------ 状态

func _wants_sprint() -> bool:
	return Input.is_action_pressed("sprint") and stamina > 0.0 and not _crouching


func _target_speed() -> float:
	if _crouching:
		return tuning.crouch_speed
	if _wants_sprint():
		return tuning.sprint_speed
	return tuning.walk_speed


func _update_crouch() -> void:
	var want_crouch := Input.is_action_pressed("crouch")
	if want_crouch == _crouching:
		return
	_crouching = want_crouch
	_apply_body_size(_crouching)


func _apply_body_size(crouching: bool) -> void:
	var height: float = tuning.crouch_height if crouching else tuning.stand_height
	var radius: float = tuning.crouch_radius if crouching else tuning.stand_radius
	_capsule.height = height
	_capsule.radius = radius
	_collision_shape.position.y = height * 0.5
	head.position.y = tuning.eye_offset_crouch if crouching else tuning.eye_offset_stand


func _update_stamina(delta: float) -> void:
	if _wants_sprint():
		stamina = maxf(0.0, stamina - tuning.stamina_drain_per_second * delta)
		_stamina_regen_blocked = true
	else:
		if _stamina_regen_blocked:
			_stamina_regen_timer -= delta
			if _stamina_regen_timer <= 0.0:
				_stamina_regen_blocked = false
				stamina = minf(tuning.max_stamina, stamina + tuning.stamina_regen_per_second * delta)
		else:
			stamina = minf(tuning.max_stamina, stamina + tuning.stamina_regen_per_second * delta)
	_broadcast_stamina()


func _update_fall() -> void:
	if is_on_floor():
		if _airborne:
			_airborne = false
			var drop := _fall_apex_y - global_position.y
			if drop > tuning.safe_fall_distance:
				apply_damage((drop - tuning.safe_fall_distance) * tuning.fall_damage_per_meter)
		return

	if not _airborne:
		_airborne = true
		_fall_apex_y = global_position.y
	else:
		_fall_apex_y = maxf(_fall_apex_y, global_position.y)


func _on_state_changed(new_state: PlayerStateMachine.State, _old_state: PlayerStateMachine.State) -> void:
	GameLog.info("玩家状态切换", {"state": state_machine.state_name(new_state)})


# ------------------------------------------------------------------ 生命

func apply_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_broadcast_health()
	GameLog.info("玩家受伤", {"amount": amount, "health": health})
	if health <= 0.0:
		EventBus.player_died.emit()


func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	health = minf(tuning.max_health, health + amount)
	_broadcast_health()


func _on_died() -> void:
	set_control_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _broadcast_health(force: bool = false) -> void:
	if force or absf(health - _last_health_broadcast) > 0.5:
		_last_health_broadcast = health
		EventBus.health_changed.emit(health, tuning.max_health)


func _broadcast_stamina(force: bool = false) -> void:
	if force or absf(stamina - _last_stamina_broadcast) > 0.5:
		_last_stamina_broadcast = stamina
		EventBus.stamina_changed.emit(stamina, tuning.max_stamina)


# ------------------------------------------------------------------ 手电筒

func toggle_flashlight() -> void:
	if not flashlight_on and flashlight_battery <= 0.0:
		GameLog.warn("手电筒电量耗尽")
		return
	flashlight_on = not flashlight_on
	flashlight.visible = flashlight_on
	EventBus.flashlight_toggled.emit(flashlight_on)
	GameLog.info("手电筒切换", {"on": flashlight_on})


func _update_flashlight(delta: float) -> void:
	if not flashlight_on:
		return
	flashlight_battery = maxf(0.0, flashlight_battery - tuning.flashlight_drain_per_second * delta)
	if flashlight_battery <= 0.0:
		flashlight_on = false
		flashlight.visible = false
		EventBus.flashlight_toggled.emit(false)


# ------------------------------------------------------------------ 控制与存档

func set_control_enabled(enabled: bool) -> void:
	_control_enabled = enabled
	if not enabled:
		state_machine.transition_to(PlayerStateMachine.State.DISABLED)


func is_control_enabled() -> bool:
	return _control_enabled


func to_dict() -> Dictionary:
	return {
		"player_transform": {
			"position": [global_position.x, global_position.y, global_position.z],
			"rotation_y": rotation.y,
		},
		"player_state": {
			"health": health,
			"stamina": stamina,
			"flashlight_on": flashlight_on,
			"flashlight_battery": flashlight_battery,
			"crouching": _crouching,
		},
	}


func from_dict(data: Dictionary) -> void:
	var transform_data: Dictionary = data.get("player_transform", {})
	var position: Array = transform_data.get("position", [0.0, 0.0, 0.0])
	if position.size() == 3:
		global_position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	rotation.y = float(transform_data.get("rotation_y", 0.0))

	var state: Dictionary = data.get("player_state", {})
	health = float(state.get("health", tuning.max_health))
	stamina = float(state.get("stamina", tuning.max_stamina))
	flashlight_battery = float(state.get("flashlight_battery", tuning.flashlight_battery_max))
	flashlight_on = bool(state.get("flashlight_on", false))
	flashlight.visible = flashlight_on

	var crouching := bool(state.get("crouching", false))
	_crouching = crouching
	_apply_body_size(_crouching)

	_broadcast_health(true)
	_broadcast_stamina(true)
