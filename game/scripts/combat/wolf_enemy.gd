class_name WolfEnemy
extends EnemyBase
## 林狼（docs/combat-and-progression.md §4 垂直切片敌人）。
##
## 物种特性：
##   - 成群行动，发现目标后会嚎叫示警，附近同伴一起进入警戒
##   - 听觉比视觉更灵敏，玩家冲刺或开枪容易暴露
##   - 先从两侧包围再一起扑上来，而不是正面硬冲
##   - 畏惧火光，靠近营火时会绕开

## 同一群狼互相知情的半径。
const PACK_ALERT_RADIUS: float = 30.0
## 包围时保持的距离。
const ENCIRCLE_RADIUS: float = 3.4

## 决定从哪一侧包抄，避免所有狼挤在同一边。
var _encircle_sign: float = 1.0

var _legs: Array[MeshInstance3D] = []
var _gait_time: float = 0.0


func _ready() -> void:
	super()
	add_to_group(&"wolf")
	# 狼群里的个体固定站位方向：用稳定 ID 派生，保证读档后一致
	if stable_id != &"":
		_encircle_sign = 1.0 if (hash(stable_id) % 2 == 0) else -1.0
	else:
		_encircle_sign = 1.0 if (get_instance_id() % 2 == 0) else -1.0


## 狼的躯干与四条腿。腿单独建，便于摆动。
func _build_visual() -> void:
	var fur := Color(0.33, 0.3, 0.28)
	var belly := Color(0.52, 0.49, 0.45)

	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = PropKit.make_wolf_body(fur, belly)
	body.material_override = PropKit.painted_material()
	add_child(body)

	var leg_mesh := PropKit.make_wolf_leg(fur)
	for i in 4:
		var leg := MeshInstance3D.new()
		leg.name = "Leg%d" % i
		leg.mesh = leg_mesh
		leg.material_override = PropKit.painted_material()
		var side_x := 1.0 if i % 2 == 0 else -1.0
		var side_z := 1.0 if i < 2 else -1.0
		leg.position = Vector3(side_x * 0.17, 0.0, side_z * 0.34)
		add_child(leg)
		_legs.append(leg)


func _physics_process(delta: float) -> void:
	super(delta)
	_animate_legs(delta)


## 对角步态：前后腿交替摆动。
func _animate_legs(delta: float) -> void:
	if _legs.is_empty():
		return

	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.25 or state == State.DEAD:
		for leg in _legs:
			leg.rotation.x = lerpf(leg.rotation.x, 0.0, minf(1.0, 8.0 * delta))
		return

	_gait_time += delta * speed * 1.5
	for i in _legs.size():
		# 前后腿反相，形成对角小跑
		var phase := 0.0 if (i == 0 or i == 3) else PI
		_legs[i].rotation.x = sin(_gait_time + phase) * 0.42


## 狼比其它野兽更怕光：靠近火源时会绕行。
func _decide(delta: float) -> void:
	super(delta)

	# 追逐时向同伴示警
	if state == State.CHASE and _state_timer < 0.2:
		_alert_pack()


## 视线比狼的听觉弱：狼主要靠声音发现目标。
func _perceive(delta: float) -> void:
	var previous_state := state
	super(delta)

	# 听觉触发时直接进入追逐，不需要先怀疑
	if previous_state != State.CHASE and state == State.SUSPICIOUS and _is_loud():
		_set_state(State.CHASE)


## 包围：不去抢同一个落点，从侧翼绕。
func _act(delta: float) -> void:
	if state == State.CHASE and _target != null:
		var destination := _encircle_destination()
		_move_toward(destination, chase_speed, delta)
		return
	super(delta)


func _encircle_destination() -> Vector3:
	if _target == null:
		return global_position

	var base := _target.global_position
	var to_me := global_position - base
	to_me.y = 0.0
	if to_me.length() < 0.1:
		return base

	var angle := atan2(to_me.z, to_me.x)
	var offset_angle := angle + _encircle_sign * 0.85
	var destination := base + Vector3(cos(offset_angle) * ENCIRCLE_RADIUS, 0.0, sin(offset_angle) * ENCIRCLE_RADIUS)

	# 目标很近时放弃包围，直接扑上去
	if global_position.distance_to(base) <= attack_range:
		return base

	return destination


## 通知附近的同伴：一只狼发现目标，整群都会进入警戒。
func _alert_pack() -> void:
	if _target == null:
		return
	for node in get_tree().get_nodes_in_group(&"wolf"):
		if node == self:
			continue
		var wolf := node as WolfEnemy
		if wolf == null or not wolf.is_alive():
			continue
		if wolf.global_position.distance_to(global_position) > PACK_ALERT_RADIUS:
			continue
		wolf.alert_to(_last_seen_position)


## 被同伴唤醒。
func alert_to(position: Vector3) -> void:
	if state == State.DEAD:
		return
	_last_seen_position = position
	if state != State.CHASE:
		_set_state(State.CHASE)


## 火光会让狼绕开：把火源当作排斥源。
func _steer_direction(direction: Vector3) -> Vector3:
	var result := direction
	for node in get_tree().get_nodes_in_group(&"fire_source"):
		var fire := node as Node3D
		if fire == null:
			continue
		var to_fire := fire.global_position - global_position
		to_fire.y = 0.0
		var distance := to_fire.length()
		if distance > 7.0 or distance < 0.01:
			continue
		var push := (-to_fire / distance) * (1.0 - distance / 7.0) * 1.4
		result = (result + push).normalized()
	return result
