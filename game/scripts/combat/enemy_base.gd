class_name EnemyBase
extends CharacterBody3D
## 敌人基类（docs/combat-and-progression.md §4）。
##
## 分层结构：
##   感知层  _perceive()    视觉 / 听觉，判断是否发现目标
##   决策层  _decide()      巡逻 / 调查 / 追逐 / 攻击 / 逃跑
##   动作层  _move_toward() 移动与转向
##   状态层  生命 / 硬直 / 死亡
##
## 子类只需覆盖 _decide() 与 _perceive() 就能得到不同的物种行为。

signal health_changed(current: float, maximum: float)
signal died(enemy: EnemyBase)
signal state_changed(state: State)

enum State {
	IDLE,        ## 原地待机
	PATROL,      ## 巡逻
	SUSPICIOUS,  ## 察觉异常，靠近查看
	CHASE,       ## 追逐目标
	ATTACK,      ## 攻击目标
	FLEE,        ## 逃离
	DEAD,        ## 已死亡
}

enum DamageKind {
	NORMAL,       ## 普通伤害
	WEAKPOINT,    ## 弱点伤害
	FIRE,         ## 火焰持续伤害
	ENVIRONMENT,  ## 跌落与环境伤害
}

const GRAVITY: float = 9.8

@export_group("身份")
## 稳定 ID。存档键必须使用稳定 ID，不能使用运行时实例 ID。
@export var stable_id: StringName = &""
@export var display_name: String = "野兽"

@export_group("属性")
@export var max_health: float = 60.0
## 掉落物：{物品ID: 数量}
@export var drops: Array[Dictionary] = []

@export_group("感知")
## 视觉距离。
@export var sight_range: float = 26.0
## 视野半角（度）。
@export var sight_angle_deg: float = 70.0
## 听觉距离。
@export var hearing_range: float = 14.0
## 失去目标后仍继续追击的时间（秒）。
@export var chase_memory: float = 6.0

@export_group("战斗")
@export var move_speed: float = 2.6
@export var chase_speed: float = 5.4
@export var attack_range: float = 1.9
@export var attack_damage: float = 10.0
## 两次攻击之间的间隔。
@export var attack_interval: float = 1.6
## 攻击前摇时间，蓄力期间可被打断。
@export var attack_windup: float = 0.45
## 弱点判定：命中点高于此高度算弱点。
@export var weak_point_height: float = 0.85
## 受击硬直时长。
@export var stagger_duration: float = 0.35

@export_group("活动范围")
## 离开这个半径就会脱离战斗并返回。
@export var leash_radius: float = 28.0
## 巡逻半径。
@export var patrol_radius: float = 9.0
## 受击后进入逃跑状态的阈值（生命比例）。
@export var flee_health_ratio: float = 0.25

var state: State = State.IDLE

var _health: float = 0.0
var _target: Node3D = null
var _state_timer: float = 0.0
var _last_seen_position: Vector3 = Vector3.ZERO
var _attack_cooldown: float = 0.0
var _attack_winding: bool = false
var _stagger_timer: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _patrol_target: Vector3 = Vector3.ZERO
var _has_patrol_target: bool = false
var _rng := RandomNumberGenerator.new()
var _terrain: Node3D = null
var _flash_timer: float = 0.0
var _base_scale: Vector3 = Vector3.ONE


func _ready() -> void:
	add_to_group(&"enemy")
	_health = max_health
	_rng.randomize()
	_base_scale = scale
	_home = global_position
	_terrain = get_tree().get_first_node_in_group(&"terrain") as Node3D
	_build_visual()


## 子类覆盖：构建外观。
func _build_visual() -> void:
	pass


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	_state_timer += delta
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_stagger_timer = maxf(0.0, _stagger_timer - delta)
	_update_flash(delta)

	_perceive(delta)
	_decide(delta)

	if _stagger_timer > 0.0:
		# 硬直期间无法移动
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	else:
		_act(delta)

	_apply_gravity(delta)
	move_and_slide()
	_clamp_to_home()


# ------------------------------------------------------------------ 感知层

## 子类可覆盖：默认视觉 + 听觉。
func _perceive(_delta: float) -> void:
	if _target == null:
		_target = get_tree().get_first_node_in_group(&"player") as Node3D
		return

	var distance := global_position.distance_to(_target.global_position)
	var can_see := distance <= sight_range and _has_line_of_sight()
	var heard := distance <= hearing_range and _is_loud()

	if can_see or heard:
		_last_seen_position = _target.global_position
		if state == State.PATROL or state == State.IDLE:
			_set_state(State.SUSPICIOUS)


## 视觉是否被遮挡。验收标准要求敌人不能隔墙发现玩家。
func _has_line_of_sight() -> bool:
	if _target == null:
		return false

	var eye := global_position + Vector3(0.0, 0.85, 0.0)
	var target_point := _target.global_position + Vector3(0.0, 0.9, 0.0)
	var to_target := target_point - eye
	var distance := to_target.length()
	if distance <= 0.01:
		return true

	# 视野角检查
	var forward := -global_transform.basis.z
	var angle := rad_to_deg(forward.angle_to(to_target / distance))
	if angle > sight_angle_deg:
		return false

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, target_point)
	query.collision_mask = 1  # 只检查世界层，忽略目标自身
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	return hit.is_empty()


## 目标是否足够吵。玩家冲刺或开枪会暴露位置。
func _is_loud() -> bool:
	if _target == null:
		return false
	if not _target.has_method("is_making_noise"):
		return false
	return bool(_target.call("is_making_noise"))


# ------------------------------------------------------------------ 决策层

## 子类覆盖具体行为。
func _decide(delta: float) -> void:
	match state:
		State.IDLE:
			if _state_timer > 2.0:
				_set_state(State.PATROL)
		State.PATROL:
			_do_patrol(delta)
		State.SUSPICIOUS:
			if _target != null and global_position.distance_to(_target.global_position) <= attack_range:
				_set_state(State.CHASE)
			elif _state_timer > 3.0:
				_set_state(State.PATROL)
		State.CHASE:
			if _target == null:
				_set_state(State.PATROL)
				return
			var distance := global_position.distance_to(_target.global_position)
			if distance <= attack_range and _attack_cooldown <= 0.0:
				_set_state(State.ATTACK)
			elif distance > sight_range + chase_memory:
				_set_state(State.SUSPICIOUS)
		State.ATTACK:
			if _attack_winding:
				# 前摇结束才真正出手
				if _state_timer >= attack_windup:
					_attack_winding = false
					_perform_attack()
					_attack_cooldown = attack_interval
					_set_state(State.CHASE)
			else:
				_set_state(State.CHASE)
		State.FLEE:
			if _state_timer > 6.0:
				_set_state(State.PATROL)


func _do_patrol(_delta: float) -> void:
	if not _has_patrol_target or global_position.distance_to(_patrol_target) < 1.0:
		var angle := _rng.randf_range(0.0, TAU)
		var radius := _rng.randf_range(1.0, patrol_radius)
		_patrol_target = _home + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_has_patrol_target = true
		_state_timer = 0.0


# ------------------------------------------------------------------ 动作层

func _act(delta: float) -> void:
	match state:
		State.IDLE:
			_stop()
		State.PATROL:
			_move_toward(_patrol_target, move_speed, delta)
		State.SUSPICIOUS:
			_move_toward(_last_seen_position, move_speed * 1.2, delta)
		State.CHASE:
			if _target != null:
				_move_toward(_target.global_position, chase_speed, delta)
		State.ATTACK:
			if _target != null:
				_face(_target.global_position, delta)
			_stop()
		State.FLEE:
			if _target != null:
				var away := global_position - _target.global_position
				_move_toward(global_position + away.normalized() * 10.0, chase_speed, delta)


func _move_toward(destination: Vector3, speed: float, delta: float) -> void:
	var to_target := destination - global_position
	to_target.y = 0.0
	if to_target.length() < 0.05:
		_stop()
		return

	var direction := to_target.normalized()
	direction = _steer_direction(direction)
	# 绕开正前方的遮挡：左右各试一个偏角
	var desired := direction
	if _is_blocked(direction):
		var side := 1.0 if _rng.randf() > 0.5 else -1.0
		desired = direction.rotated(Vector3.UP, side * 0.9)
		if _is_blocked(desired):
			desired = direction.rotated(Vector3.UP, -side * 0.9)

	velocity.x = move_toward(velocity.x, desired.x * speed, 16.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z * speed, 16.0 * delta)
	_face(global_position + desired, delta)


## 转向修正钩子。子类可在这里加入排斥火源、回避同伴之类的逻辑。
func _steer_direction(direction: Vector3) -> Vector3:
	return direction


## 前方是否有障碍（只看地形与静态物体）。
func _is_blocked(direction: Vector3) -> bool:
	var from := global_position + Vector3(0.0, 0.7, 0.0)
	var to := from + direction * 1.6
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


func _face(destination: Vector3, delta: float) -> void:
	var to_target := destination - global_position
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return
	var target_angle := atan2(-to_target.x, -to_target.z)
	rotation.y = lerp_angle(rotation.y, target_angle, minf(1.0, 10.0 * delta))


func _stop() -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * 0.016)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * 0.016)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = -2.0


## 贴地：优先用地形高度查询，落在地面上。
func _clamp_to_home() -> void:
	if _terrain != null and _terrain.has_method("height_at"):
		var ground := float(_terrain.call("height_at", global_position.x, global_position.z))
		if global_position.y < ground:
			global_position.y = lerpf(global_position.y, ground, 0.5)


# ------------------------------------------------------------------ 伤害

## 造成伤害。命中点用于判定弱点。
func apply_damage(amount: float, kind: DamageKind = DamageKind.NORMAL,
		hit_point: Vector3 = Vector3.INF) -> void:
	if state == State.DEAD or amount <= 0.0:
		return

	var final_amount := amount
	if kind == DamageKind.WEAKPOINT:
		final_amount *= 2.0

	_health = maxf(0.0, _health - final_amount)
	health_changed.emit(_health, max_health)
	EventBus.enemy_health_changed.emit(display_name, _health, max_health)
	_flash_timer = 0.18
	_stagger_timer = stagger_duration

	# 受击会立刻暴露攻击者的位置
	if _target != null:
		_last_seen_position = _target.global_position

	if _health <= 0.0:
		_die()
	else:
		if _health / max_health <= flee_health_ratio and state != State.FLEE:
			_set_state(State.FLEE)
		elif state != State.CHASE and state != State.ATTACK:
			_set_state(State.CHASE)


## 命中点是否落在弱点。
func is_weak_point(hit_point: Vector3) -> bool:
	if hit_point == Vector3.INF:
		return false
	return hit_point.y - global_position.y >= weak_point_height


func _die() -> void:
	_set_state(State.DEAD)
	velocity = Vector3.ZERO
	set_physics_process(false)
	_on_death()
	died.emit(self)


## 子类覆盖：死亡表现。
func _on_death() -> void:
	collision_layer = 0
	collision_mask = 0
	scale = _base_scale * Vector3(1.0, 0.35, 1.0)
	_spawn_drops()


## 死亡掉落：在尸体位置生成可拾取物。
func _spawn_drops() -> void:
	if drops.is_empty():
		return
	var parent := get_parent()
	if parent == null:
		return

	for drop in drops:
		var item_id := StringName(drop.get("id", &""))
		var amount := int(drop.get("amount", 1))
		if item_id == &"" or amount <= 0:
			continue

		var pickup := PickupInteractable.new()
		pickup.name = "Drop_%s" % item_id
		pickup.stable_id = StringName("%s_drop_%s" % [stable_id, item_id])
		pickup.item_id = item_id
		pickup.amount = amount
		pickup.prompt_text = "拾取"
		pickup.prop_visual = &"arrow_bundle"

		# 拾取物需要碰撞体，交互射线才能命中
		var shape := SphereShape3D.new()
		shape.radius = 0.32
		var body := StaticBody3D.new()
		body.collision_layer = 4   # interactable 层
		body.collision_mask = 0
		var body_collision := CollisionShape3D.new()
		body_collision.shape = shape
		body.add_child(body_collision)
		pickup.add_child(body)

		pickup.position = global_position + Vector3(
			_rng.randf_range(-0.4, 0.4), 0.15, _rng.randf_range(-0.4, 0.4))
		parent.add_child(pickup)


func _update_flash(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer = maxf(0.0, _flash_timer - delta)
	var t := 1.0 - _flash_timer / 0.18
	scale = _base_scale * Vector3(1.18, 0.86, 1.18).lerp(Vector3.ONE, t)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	_state_timer = 0.0
	if new_state == State.ATTACK:
		_attack_winding = true
	state_changed.emit(new_state)


# ------------------------------------------------------------------ 对外接口

func get_health() -> float:
	return _health


## 状态的文本形式，用于日志与调试。
func state_name_text() -> String:
	match state:
		State.IDLE:
			return "IDLE"
		State.PATROL:
			return "PATROL"
		State.SUSPICIOUS:
			return "SUSPICIOUS"
		State.CHASE:
			return "CHASE"
		State.ATTACK:
			return "ATTACK"
		State.FLEE:
			return "FLEE"
		State.DEAD:
			return "DEAD"
	return "UNKNOWN"


func is_alive() -> bool:
	return state != State.DEAD


## 当前是否对目标构成威胁（用于 HUD 提示）。
func is_threatening() -> bool:
	return state == State.CHASE or state == State.ATTACK or state == State.SUSPICIOUS


## 当前敌意方向，HUD 用它提示玩家被哪个方向攻击。
func threat_direction() -> Vector3:
	if _target == null:
		return Vector3.ZERO
	return (_target.global_position - global_position).normalized()


func _perform_attack() -> void:
	if _target == null:
		return
	if global_position.distance_to(_target.global_position) > attack_range * 1.35:
		return
	if _target.has_method("apply_damage"):
		_target.call("apply_damage", attack_damage)


# ------------------------------------------------------------------ 存档

## 需要持久化的状态。已击败的敌人通过稳定 ID 记录。
func get_persistent_state() -> Dictionary:
	return {
		"alive": is_alive(),
		"health": _health,
	}


func apply_persistent_state(state_data: Dictionary) -> void:
	if state_data.is_empty():
		return
	_health = float(state_data.get("health", _health))
	health_changed.emit(_health, max_health)
	if not bool(state_data.get("alive", true)):
		_set_state(State.DEAD)
		_on_death()
		set_physics_process(false)
