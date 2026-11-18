class_name ArrowProjectile
extends Node3D
## 箭矢：带弹道的投射物（docs/combat-and-progression.md §5）。
##
## 自己积分位置并做射线检测，不用刚体：
## 箭速可达 40 m/s 以上，物理帧之间会穿过去，手动射线更可靠，
## 也方便精确取命中点来判断弱点。
##
## 箭矢无限供应（docs/archery-and-realism.md §2），
## 所以箭不消耗、不回收——但**它留在世界里**：
## 射偏的箭插在树干上，玩家能看见自己偏了多少；
## 一路走一路射，森林里插着你射过的箭。
## 这是"我来过"最直接的证据，比任何数值系统都更能造出真实感。

signal hit(target: Node, damage: float, is_weakpoint: bool)
signal missed()

@export var damage: float = 32.0
## 初速区间，取决于蓄力。
@export var min_speed: float = 16.0
@export var max_speed: float = 42.0
## 重力加速度。
@export var gravity: float = 9.8
## 存活时间（秒）。飞行中超过这么久就消失。
@export var lifetime: float = 25.0
## 命中后停留多久再消失。小于 0 表示永久留下。
@export var stuck_duration: float = -1.0
## 命中后的余震幅度（弧度）。箭杆插进去时其实还在抖。
@export var wobble_strength: float = 0.06
## 余震衰减速度（弧度/秒）。
@export var wobble_decay: float = 7.0

## 插在地上的箭所在的分组。
const STUCK_GROUP := &"stuck_arrow"
## 场上同时存在的箭矢上限。超出的最早那支会消失——
## 森林里插满几千支箭既不真实也会拖垮场景。
const MAX_STUCK_ARROWS := 40

## 发射序号。用来判断哪支箭更早插下。
static var _spawn_serial: int = 0

var velocity: Vector3 = Vector3.ZERO

var _age: float = 0.0
var _stuck: bool = false
var _stuck_timer: float = 0.0
var _serial: int = 0
## 钉住那一刻的朝向，余震围绕它摆动。
var _stuck_basis: Basis = Basis.IDENTITY
var _wobble_angle: float = 0.0
var _wobble_speed: float = 0.0


func _ready() -> void:
	_serial = _spawn_serial
	_spawn_serial += 1

	var mesh := MeshInstance3D.new()
	mesh.name = "ArrowMesh"
	mesh.mesh = PropKit.make_arrow()
	mesh.material_override = PropKit.painted_material()
	add_child(mesh)


## 发射。direction 为世界方向，power 为蓄力比例 0~1。
func launch(direction: Vector3, power: float) -> void:
	velocity = direction.normalized() * lerpf(min_speed, max_speed, clampf(power, 0.0, 1.0))


## 让箭身对准一个世界方向（箭尖是 -Z）。
##
## 不能直接 look_at(..., Vector3.UP)：方向和 UP 平行时（箭垂直扎进地面、
## 或者被射上天）look_at 会退化，Godot 会报错并留下一个乱转的朝向。
func face(direction: Vector3) -> void:
	var dir := direction.normalized()
	if dir.length_squared() < 0.000001:
		return
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
	look_at(global_position + dir, up)


func _physics_process(delta: float) -> void:
	if _stuck:
		_stuck_timer -= delta
		if stuck_duration >= 0.0 and _stuck_timer <= 0.0:
			queue_free()
			return
		_apply_wobble(delta)
		return

	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	var step := velocity * delta
	var from := global_position
	var to := from + step

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 8   # 世界层 + 敌人层
	query.collide_with_areas = false

	var result := space.intersect_ray(query)
	if not result.is_empty():
		_apply_hit(result)
		return

	global_position = to
	velocity.y -= gravity * delta

	# 让箭矢始终指向飞行方向
	if velocity.length_squared() > 0.01:
		face(velocity)


## 命中后的余震。箭杆插进去时还在抖，几百毫秒后静止。
func _apply_wobble(delta: float) -> void:
	if _wobble_speed <= 0.001:
		return
	_wobble_angle += _wobble_speed * delta
	_wobble_speed = maxf(0.0, _wobble_speed - wobble_decay * delta)
	var wobble := Basis.from_euler(Vector3(_wobble_angle, 0.0, 0.0))
	global_transform = Transform3D(_stuck_basis * wobble, global_position)


func _apply_hit(result: Dictionary) -> void:
	var collider: Object = result.get("collider")
	var hit_point: Vector3 = result.get("position", global_position)

	if collider is EnemyBase:
		var enemy := collider as EnemyBase
		var is_weak := enemy.is_weak_point(hit_point)
		var kind := EnemyBase.DamageKind.WEAKPOINT if is_weak else EnemyBase.DamageKind.NORMAL
		enemy.apply_damage(damage, kind, hit_point)
		hit.emit(enemy, damage, is_weak)
		_stick(hit_point, -velocity.normalized())
		return

	# 命中环境：钉在表面
	hit.emit(null, 0.0, false)
	missed.emit()
	_stick(hit_point, -velocity.normalized())


func _stick(point: Vector3, normal: Vector3) -> void:
	_stuck = true
	_stuck_timer = stuck_duration
	velocity = Vector3.ZERO
	if normal.length_squared() < 0.01:
		global_position = point
		_after_stick()
		return
	var outward := normal.normalized()
	# 箭尾在网格原点，箭身朝 -Z 伸出 0.59 m（PropKit._bow_arrow_parts）。
	# 钉住时把箭尾留在表面外 0.30 m：约一半插进去、一半露在外面，
	# 不然以原点定位会把整支箭埋进墙里，只剩一个看不见的点。
	global_position = point + outward * 0.30
	face(-outward)
	_after_stick()


## 钉住之后的收尾：记下朝向、起余震、进分组、清理超量的旧箭。
func _after_stick() -> void:
	_stuck_basis = global_transform.basis
	_wobble_speed = wobble_strength * 12.0
	_wobble_angle = 0.0
	add_to_group(STUCK_GROUP)
	_enforce_stuck_limit()


## 场上箭矢数量上限。超出时最早插下的那支消失。
func _enforce_stuck_limit() -> void:
	var arrows := get_tree().get_nodes_in_group(STUCK_GROUP)
	if arrows.size() <= MAX_STUCK_ARROWS:
		return
	var oldest: ArrowProjectile = null
	for node in arrows:
		var candidate := node as ArrowProjectile
		if candidate == null:
			continue
		if oldest == null or candidate._serial < oldest._serial:
			oldest = candidate
	if oldest != null and oldest != self:
		oldest.queue_free()


## 这支箭是否已经插在地上。
func is_stuck() -> bool:
	return _stuck


## 供测试用：场上有多少支插着的箭。
static func count_stuck(tree: SceneTree) -> int:
	return tree.get_nodes_in_group(STUCK_GROUP).size()
