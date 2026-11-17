class_name ArrowProjectile
extends Node3D
## 箭矢：带弹道的投射物（docs/combat-and-progression.md §5）。
##
## 自己积分位置并做射线检测，不用刚体：
## 箭速可达 40 m/s 以上，物理帧之间会穿过去，手动射线更可靠，
## 也方便精确取命中点来判断弱点。

signal hit(target: Node, damage: float, is_weakpoint: bool)
signal missed()

@export var damage: float = 32.0
## 初速区间，取决于蓄力。
@export var min_speed: float = 16.0
@export var max_speed: float = 42.0
## 重力加速度。
@export var gravity: float = 9.8
## 存活时间（秒）。
@export var lifetime: float = 25.0
## 命中后停留多久再消失。
@export var stuck_duration: float = 6.0

var velocity: Vector3 = Vector3.ZERO

var _age: float = 0.0
var _stuck: bool = false
var _stuck_timer: float = 0.0


func _ready() -> void:
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
		if _stuck_timer <= 0.0:
			queue_free()
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
		return
	var outward := normal.normalized()
	# 箭尾在网格原点，箭身朝 -Z 伸出 0.59 m（PropKit._bow_arrow_parts）。
	# 钉住时把箭尾留在表面外 0.30 m：约一半插进去、一半露在外面，
	# 不然以原点定位会把整支箭埋进墙里，只剩一个看不见的点。
	global_position = point + outward * 0.30
	face(-outward)
