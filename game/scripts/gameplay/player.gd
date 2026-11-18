class_name Player
extends CharacterBody3D
## 第一人称控制器（docs/technical-design.md §4.2）。
##
## 节点结构：
##   Player (CharacterBody3D)
##   ├── CollisionShape3D
##   ├── Body (MeshInstance3D)         程序化躯干 + 双腿，低头时才看得见
##   ├── Head (Node3D)
##   │   ├── Camera3D
##   │   ├── InteractionRay (RayCast3D)
##   │   ├── Flashlight (SpotLight3D)
##   │   └── AudioListener3D
##   ├── FootstepDetector (RayCast3D)
##   ├── StateMachine (Node)
##   └── InteractionSystem (Node)

## 身体模型（PropKit.make_player_body）肩线的高度。
## 站立时相机在 1.62 m，肩线 1.44 m：平视时身体完全在画面外。
const BODY_TOP_HEIGHT := 1.44

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
var _mouse_captured: bool = false
var _fall_apex_y: float = 0.0
var _airborne: bool = false
var _last_stamina_broadcast: float = -1.0
var _last_health_broadcast: float = -1.0
var _stamina_regen_blocked: bool = false
var _stamina_regen_timer: float = 0.0
## 视角灵敏度倍率。瞄准时由弓调低。
var look_sensitivity_scale: float = 1.0
## 噪声计时：受击、射箭等会短暂暴露位置。
var _noise_timer: float = 0.0

## 掉出世界的兜底检测。
##
## 传送 / 重生到还没建好碰撞的区块时，玩家会一路下落（实测能到 -53 m/s），
## 而且永远落不到底——地形是单面凹网格，从下面穿过去就再也碰不到。
## 每 0.5 s 采样一次脚下高度场，掉到地面以下就把人拉回来。
## 采样频率低到几乎不要钱，但能兜住所有「瞬移到空区块」的路径。
const VOID_CHECK_INTERVAL := 0.5
const VOID_MARGIN := 3.0
var _void_check_timer: float = 0.0

## 第一人称走路的镜头运动。相机初始位置（通常是 0，但不要假设）。
var _camera_rest_position: Vector3 = Vector3.ZERO
var _bob_phase: float = 0.0
var _bob_weight: float = 0.0
var _land_dip: float = 0.0
var _was_airborne: bool = false
var _prev_velocity_y: float = 0.0


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

	# 启动时不捕获鼠标：玩家主动点击画面后才进入视角控制，
	# 否则一启动就夺走鼠标（尤其多屏时非常难受）。
	release_mouse()

	# 记录相机初始局部位置：走路起伏都叠加在它上面，不重置蹲伏改的高度。
	_camera_rest_position = camera.position


## 捕获鼠标，进入第一人称视角控制。
func capture_mouse() -> void:
	_mouse_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 释放鼠标，把光标还给玩家。
func release_mouse() -> void:
	_mouse_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	return _mouse_captured


## Esc 处理：只归还鼠标，不冻结操作。
func handle_escape() -> void:
	release_mouse()


func _notification(what: int) -> void:
	# 窗口失焦时释放鼠标，避免切换到其他程序后光标仍被锁住
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_mouse()


func _physics_process(delta: float) -> void:
	_check_void_fall(delta)
	_prev_velocity_y = velocity.y
	if not _control_enabled:
		velocity.x = move_toward(velocity.x, 0.0, tuning.acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, tuning.acceleration * delta)
		move_and_slide()
		_update_landing()
		return

	_update_crouch()
	_update_stamina(delta)
	_update_flashlight(delta)
	_update_noise(delta)
	_update_fall()
	_apply_gravity(delta)
	_update_movement(delta)
	move_and_slide()
	_update_landing()
	_update_state()


## 第一人称镜头的呼吸感：只在视角层动，物理与碰撞体不受影响。
func _process(delta: float) -> void:
	_update_camera_motion(delta)


## 掉出世界的兜底。见 VOID_CHECK_INTERVAL 的说明。
func _check_void_fall(delta: float) -> void:
	_void_check_timer -= delta
	if _void_check_timer > 0.0:
		return
	_void_check_timer = VOID_CHECK_INTERVAL

	var terrain := get_tree().get_first_node_in_group(&"terrain") as Node3D
	if terrain == null or not terrain.has_method("height_at"):
		return
	var ground := float(terrain.call("height_at", global_position.x, global_position.z))
	if global_position.y >= ground - VOID_MARGIN:
		return

	global_position.y = ground + 0.3
	velocity = Vector3.ZERO
	GameLog.warn("玩家掉出世界，已拉回地面", {
		"y": global_position.y, "ground": ground,
	})


# ------------------------------------------------------------------ 第一人称运动

## 走路的镜头起伏：上下、左右、轻微侧倾，落地时补一记下沉。
##
## 只动 Camera3D 的局部变换，不动 Head——蹲伏改的是 Head 高度，
## 两者叠在一起才是「身体蹲下、头还在动」。
func _update_camera_motion(delta: float) -> void:
	if camera == null:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var grounded := is_on_floor()
	var moving := clampf(speed / maxf(tuning.walk_speed, 0.01), 0.0, 1.6)
	var target_weight := moving if grounded and _control_enabled else 0.0
	_bob_weight = lerpf(_bob_weight, target_weight, minf(1.0, 7.0 * delta))
	_bob_phase += delta * TAU * (0.75 + speed * 0.13)

	var amplitude := tuning.head_bob_amplitude * _bob_weight
	var side := sin(_bob_phase) * amplitude * 0.55
	var up := sin(_bob_phase * 2.0) * amplitude
	var roll := deg_to_rad(tuning.head_bob_roll_degrees) * sin(_bob_phase) * _bob_weight

	_land_dip = lerpf(_land_dip, 0.0, minf(1.0, 9.0 * delta))
	camera.position = _camera_rest_position + Vector3(side, up - _land_dip, 0.0)
	camera.rotation.z = roll


## 落地检测：用落地前一帧的竖直速度决定下沉幅度。
func _update_landing() -> void:
	var grounded := is_on_floor()
	if grounded and _was_airborne:
		_land_dip = clampf(absf(_prev_velocity_y) * 0.011, 0.0, tuning.head_bob_landing_dip)
	_was_airborne = not grounded


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _mouse_captured and _control_enabled:
			_handle_look(event as InputEventMouseMotion)
		return

	if event is InputEventMouseButton and event.is_pressed():
		# 点击画面才捕获鼠标；已捕获时不重复触发
		if not is_mouse_captured():
			capture_mouse()
		return

	if event.is_action_pressed("jump") and _control_enabled and is_on_floor():
		velocity.y = tuning.jump_velocity

	if event.is_action_pressed("flashlight") and _control_enabled:
		toggle_flashlight()

	if event.is_action_pressed("pause"):
		handle_escape()


# ------------------------------------------------------------------ 移动

func _handle_look(event: InputEventMouseMotion) -> void:
	var sensitivity: float = SettingsManager.mouse_sensitivity
	if sensitivity <= 0.0:
		sensitivity = tuning.mouse_sensitivity
	sensitivity *= look_sensitivity_scale

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
	_update_body_scale()


## 身体模型跟着相机高度整体压缩。
##
## 蹲下时相机降到 0.95 m，躯干还在 1.5 m 的话相机会钻进身体里，
## 低头直接看到躯干内壁（背面剔除后是一块空洞）。
## 规则很简单：身体顶端永远略低于相机。
## 脚不动、整体压扁——低多边形灰盒够用，不必去摆真正的蹲姿。
func _update_body_scale() -> void:
	var body := get_node_or_null("Body") as Node3D
	if body == null:
		return
	body.scale.y = clampf((head.position.y - 0.12) / BODY_TOP_HEIGHT, 0.35, 1.0)


func _update_noise(delta: float) -> void:
	if _noise_timer > 0.0:
		_noise_timer = maxf(0.0, _noise_timer - delta)


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


## 消耗体力。蓄力、重击等动作用。
func spend_stamina(amount: float) -> void:
	if amount <= 0.0:
		return
	stamina = maxf(0.0, stamina - amount)
	_broadcast_stamina()


## 制造噪声，持续一段时间内敌人容易听见（docs/combat-and-progression.md §4）。
func notify_noise(duration: float) -> void:
	_noise_timer = maxf(_noise_timer, duration)


## 当前是否在制造噪声。
func is_making_noise() -> bool:
	if _noise_timer > 0.0:
		return true
	if not _control_enabled:
		return false
	return state_machine.current_state == PlayerStateMachine.State.SPRINTING


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
