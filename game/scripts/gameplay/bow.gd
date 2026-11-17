class_name Bow
extends Node3D
## 弓箭（docs/combat-and-progression.md §1、§8）。
##
## 垂直切片只做弓这一种主武器：
##   - 右键瞄准：视野收窄、鼠标灵敏度降低
##   - 左键按住蓄力，松开射箭
##   - 蓄力消耗体力，体力不足就蓄不满
##   - 箭矢从背包扣除，打空就没有远程手段
##
## 第一人称表现（「人」的动作，而不是一把浮空的弓）：
##   - 左手扣在握把上、右手捏弦，双手与两条手臂都挂在相机下
##   - 蓄力时弓弦折成 V 形、箭一起后移，右手跟着弦走
##   - 走路/冲刺时有持弓摆动，站定时有呼吸起伏，转视角有惯性滞后
##   - 落地、射击各有一记短促的下沉

signal fired(power: float)
signal fire_failed(reason: String)

@export var bow_item_id: StringName = &"bow"
@export var ammo_item_id: StringName = &"arrow"
## 箭矢伤害。
@export var damage: float = 32.0
## 蓄满所需时间（秒）。
@export var max_charge_time: float = 1.1
## 蓄力时每秒消耗的体力。
@export var stamina_per_second: float = 14.0
## 低于这个蓄力比例视为误触，不发射。
@export var min_charge_to_fire: float = 0.18
## 瞄准时的视野角度。
@export var aim_fov: float = 55.0
## 瞄准时的鼠标灵敏度倍率。
@export var aim_sensitivity_scale: float = 0.45
## 垂下持弓时相对镜头的偏移与朝向。
@export var view_offset: Vector3 = Vector3(0.26, -0.31, -0.47)
@export var view_rotation_degrees: Vector3 = Vector3(8.0, 22.0, 10.0)
## 举弓瞄准时相对镜头的偏移与朝向。弓弦落在屏幕中心。
@export var aim_view_offset: Vector3 = Vector3(0.0, -0.02, -0.45)
@export var aim_view_rotation_degrees: Vector3 = Vector3(0.0, 8.0, 0.0)
## 第一人称模型整体缩放。
## 弓本身是 1.32 m 的猎弓，缩到 0.30 后与相机距离配合，正好占满画面高度。
@export var view_scale: float = 0.30

## 弓本地坐标里的关键点。
const GRIP_POINT := Vector3(-0.2, 0.0, 0.0)
const STRING_TOP := Vector3(0.0, 0.66, 0.0)
const STRING_BOTTOM := Vector3(0.0, -0.66, 0.0)
## 弓弦静止位置（也是箭尾位置）。
const NOCK_REST := Vector3(0.0, 0.02, 0.06)
## 满蓄力时弦被拉后的距离（弓本地单位）。乘上 view_scale 约 0.25 m。
const MAX_DRAW := 0.92
## 手部缩放。弓是缩小的视图模型，手不能按真人尺寸摆，否则像个巨人。
const HAND_SCALE := 0.62
## 手臂两段长度与肩点（相机空间，米）。
const LEFT_SHOULDER := Vector3(-0.2, -0.26, 0.03)
const RIGHT_SHOULDER := Vector3(0.22, -0.26, 0.03)
const UPPER_ARM := 0.33
const FOREARM := 0.32
## 持弓摆动幅度（米 / 度）。
const BOB_SIDE := 0.009
const BOB_UP := 0.006
const BOB_ROLL_DEGREES := 1.1
const SWAY_ROTATION_DEGREES := 2.2

var _player: Player = null
var _inventory: Inventory = null
var _camera: Camera3D = null
## 弓是玩家子节点，_ready 早于 Player，不能用 _player.head（那时还没就绪）。
var _head: Node3D = null

var _view_root: Node3D = null
var _bow_pivot: Node3D = null
var _nocked_arrow: MeshInstance3D = null
var _string_top: MeshInstance3D = null
var _string_bottom: MeshInstance3D = null
var _left_hand: MeshInstance3D = null
var _right_hand: MeshInstance3D = null
var _upper_left: MeshInstance3D = null
var _fore_left: MeshInstance3D = null
var _upper_right: MeshInstance3D = null
var _fore_right: MeshInstance3D = null

var _charge: float = 0.0
var _charging: bool = false
var _aiming: bool = false
var _base_fov: float = 75.0
## 当前拉弦量（0 → MAX_DRAW），蓄力后平滑过渡，松手时快速回弹。
var _draw: float = 0.0

var _bob_time: float = 0.0
var _bob_weight: float = 0.0
var _sway: Vector2 = Vector2.ZERO
var _kick: float = 0.0
var _was_grounded: bool = true
var _prev_yaw: float = 0.0
var _prev_pitch: float = 0.0


func _ready() -> void:
	_player = get_tree().get_first_node_in_group(&"player") as Player
	if _player == null:
		return
	_inventory = _player.get_node_or_null("Inventory") as Inventory
	_camera = _player.get_node_or_null("Head/Camera3D") as Camera3D
	_head = _player.get_node_or_null("Head") as Node3D
	if _camera == null:
		return
	_base_fov = _camera.fov
	_prev_yaw = _player.rotation.y
	_prev_pitch = _head.rotation.x if _head != null else 0.0

	_build_view_model()

	# 箭矢数量会因为初始装备、拾取掉落物、其它消耗而变化，
	# 背包一有变动就重新广播，否则 HUD 会一直显示 0。
	if _inventory != null:
		_inventory.item_added.connect(_on_inventory_changed)
		_inventory.item_removed.connect(_on_inventory_changed)

	EventBus.ammo_changed.emit(ammo_item_id, _ammo_count())


## 第一人称持弓：弓、弦、箭、双手、两段手臂，全部挂在相机下。
##
## 结构：
##   Camera3D
##   └── BowViewModel (Node3D)        摆动/呼吸/落地下沉都加在这一层
##       ├── BowPivot (Node3D)        弓的抬放与缩放
##       │   ├── BowFrame
##       │   ├── NockedArrow
##       │   ├── StringTop / StringBottom
##       ├── LeftHand / RightHand     相机空间尺寸，不跟弓一起缩小
##       └── UpperArmLeft / ForearmLeft / UpperArmRight / ForearmRight
func _build_view_model() -> void:
	_view_root = Node3D.new()
	_view_root.name = "BowViewModel"
	_view_root.visible = false
	_camera.add_child(_view_root)

	_bow_pivot = Node3D.new()
	_bow_pivot.name = "BowPivot"
	_bow_pivot.position = view_offset
	_bow_pivot.rotation_degrees = view_rotation_degrees
	_bow_pivot.scale = Vector3.ONE * view_scale
	_view_root.add_child(_bow_pivot)

	_add_mesh(_bow_pivot, "BowFrame", PropKit.make_bow_frame())
	_nocked_arrow = _add_mesh(_bow_pivot, "NockedArrow", PropKit.make_bow_nocked_arrow())

	var string_mesh := PropKit.make_bow_string()
	_string_top = _add_mesh(_bow_pivot, "StringTop", string_mesh)
	_string_bottom = _add_mesh(_bow_pivot, "StringBottom", string_mesh)

	var hand_mesh := PropKit.make_player_hand(Color(0.66, 0.49, 0.36), Color(0.27, 0.21, 0.16))
	_left_hand = _add_mesh(_view_root, "LeftHand", hand_mesh)
	_right_hand = _add_mesh(_view_root, "RightHand", hand_mesh)

	var sleeve := Color(0.21, 0.24, 0.19)
	var upper_mesh := PropKit.make_limb_mesh(sleeve)
	var fore_mesh := PropKit.make_limb_mesh(sleeve.lightened(0.07))
	_upper_left = _add_mesh(_view_root, "UpperArmLeft", upper_mesh)
	_fore_left = _add_mesh(_view_root, "ForearmLeft", fore_mesh)
	_upper_right = _add_mesh(_view_root, "UpperArmRight", upper_mesh)
	_fore_right = _add_mesh(_view_root, "ForearmRight", fore_mesh)


func _add_mesh(parent: Node3D, node_name: String, mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = PropKit.painted_material()
	parent.add_child(node)
	return node


## 背包里箭矢数量变了。
func _on_inventory_changed(item_id: StringName, _amount: int) -> void:
	if item_id != ammo_item_id:
		return
	EventBus.ammo_changed.emit(ammo_item_id, _ammo_count())


func _process(delta: float) -> void:
	if _player == null or _camera == null:
		return
	# 场景拆除阶段相机可能已经出树，这时不该再做任何事
	if not _camera.is_inside_tree():
		return

	var control_ok := _player.is_control_enabled() and _player.is_mouse_captured()
	var has_bow := _inventory != null and _inventory.has_item(bow_item_id)

	_aiming = control_ok and has_bow and Input.is_action_pressed("aim")

	if control_ok and has_bow and Input.is_action_pressed("fire"):
		_charge_up(delta)
	elif _charging:
		_release_and_fire()

	_update_view(has_bow, delta)
	_update_pose(has_bow, delta)


func _charge_up(delta: float) -> void:
	_charging = true
	# 体力不足时蓄力变慢，体力耗尽就完全蓄不满
	var stamina_ratio := 1.0
	if _player != null and _player.tuning.max_stamina > 0.0:
		stamina_ratio = clampf(_player.stamina / _player.tuning.max_stamina, 0.0, 1.0)

	var rate := 1.0 / maxf(max_charge_time, 0.01)
	if stamina_ratio <= 0.02:
		rate = 0.0
	elif stamina_ratio < 0.3:
		rate *= lerpf(0.35, 1.0, stamina_ratio / 0.3)

	_charge = clampf(_charge + rate * delta, 0.0, 1.0)

	if _player != null and stamina_ratio > 0.0:
		_player.spend_stamina(stamina_per_second * delta)

	EventBus.bow_charge_changed.emit(_charge)


func _release_and_fire() -> void:
	_charging = false
	var power := _charge
	_charge = 0.0
	EventBus.bow_charge_changed.emit(0.0)

	if power < min_charge_to_fire:
		return

	if _inventory == null or not _inventory.has_item(ammo_item_id, 1):
		fire_failed.emit("没有箭矢了")
		return

	_inventory.remove_item(ammo_item_id, 1)
	EventBus.ammo_changed.emit(ammo_item_id, _ammo_count())

	spawn_arrow(power)
	_kick = maxf(_kick, 0.022)
	fired.emit(power)


## 生成一支箭。
##
## 暴露为公开方法，方便测试直接走真实发射路径。
func spawn_arrow(power: float) -> void:
	if _camera == null or not _camera.is_inside_tree():
		return
	var arrow := ArrowProjectile.new()
	arrow.name = "Arrow"
	arrow.damage = damage
	arrow.hit.connect(_on_arrow_hit)
	var forward := -_camera.global_transform.basis.z
	arrow.launch(forward, power)

	# 必须先入树再设 global_position：节点不在场景树里时 Godot 会忽略
	# 这个赋值，箭会落在父节点原点上（也就是世界原点），而不是射手手里。
	var parent := _player.get_parent()
	if parent == null:
		parent = get_tree().current_scene
	parent.add_child(arrow)
	arrow.global_position = _camera.global_position + forward * 0.6 - _camera.global_transform.basis.y * 0.15

	# 弓响会暴露位置
	_player.notify_noise(1.2)


func _on_arrow_hit(_target: Node, _damage: float, weakpoint: bool) -> void:
	EventBus.hit_confirmed.emit(weakpoint)


## 更新弓的抬放。
##
## 手里有弓就一直拿在手上（垂在画面右下），瞄准或蓄力时抬到屏幕中心。
func _update_view(has_bow: bool, delta: float) -> void:
	if _view_root == null:
		return
	_view_root.visible = has_bow
	if not has_bow:
		_bob_weight = 0.0
		return

	var raised := _aiming or _charging
	var target_offset := aim_view_offset if raised else view_offset
	var target_rotation := aim_view_rotation_degrees if raised else view_rotation_degrees
	var weight := minf(1.0, 12.0 * delta)
	_bow_pivot.position = _bow_pivot.position.lerp(target_offset, weight)
	_bow_pivot.rotation_degrees = _bow_pivot.rotation_degrees.lerp(target_rotation, weight)

	# 瞄准时收窄视野
	var target_fov := _base_fov
	if _aiming:
		target_fov = aim_fov
	_camera.fov = lerpf(_camera.fov, target_fov, 0.25)

	if _player != null:
		_player.look_sensitivity_scale = aim_sensitivity_scale if _aiming else 1.0


## 每帧摆放双手、手臂、弓弦与箭，并叠加持弓的摆动。
func _update_pose(has_bow: bool, delta: float) -> void:
	_update_bob(delta)
	if not has_bow or _view_root == null:
		return

	# 拉弦量：蓄力时跟着 charge 走，松手/收弓时回弹
	var draw_target := _charge * MAX_DRAW if (_aiming or _charging) else 0.0
	_draw = lerpf(_draw, draw_target, minf(1.0, 18.0 * delta))

	var bow := _bow_pivot.transform
	var bow_rotation := bow.basis.orthonormalized()
	var nock_local := NOCK_REST + Vector3(0.0, 0.0, _draw)
	var grip := bow * GRIP_POINT
	var nock := bow * nock_local

	# 双手：左手扣住握把，右手捏着弦并跟着拉开
	var left_hand_pos := grip + bow_rotation * Vector3(0.0, 0.0, 0.03)
	var right_hand_pos := nock + bow_rotation * Vector3(0.0, 0.0, 0.018)
	var hand_basis := bow_rotation.scaled(Vector3.ONE * HAND_SCALE)
	_left_hand.transform = Transform3D(hand_basis, left_hand_pos)
	_right_hand.transform = Transform3D(hand_basis, right_hand_pos)

	# 手臂：肩 → 肘 → 手。手到肩的距离超过臂长时自动伸直。
	var left_elbow := _solve_elbow(LEFT_SHOULDER, left_hand_pos, UPPER_ARM, FOREARM, Vector3(-0.65, -1.0, 0.1))
	var right_elbow := _solve_elbow(RIGHT_SHOULDER, right_hand_pos, UPPER_ARM, FOREARM, Vector3(0.7, -1.0, 0.1))
	_upper_left.transform = _segment_transform(LEFT_SHOULDER, left_elbow, 0.066)
	_fore_left.transform = _segment_transform(left_elbow, left_hand_pos, 0.058)
	_upper_right.transform = _segment_transform(RIGHT_SHOULDER, right_elbow, 0.066)
	_fore_right.transform = _segment_transform(right_elbow, right_hand_pos, 0.058)

	# 弓弦：两段折线，从上下弓臂尖端连到弦心；拉弦时折成 V 形
	_string_top.transform = _segment_transform(STRING_TOP, nock_local, 0.012)
	_string_bottom.transform = _segment_transform(STRING_BOTTOM, nock_local, 0.012)

	# 箭跟着弦一起后移
	_nocked_arrow.position = Vector3(0.0, 0.0, _draw)


## 持弓的摆动：走路上下颠、左右晃，站定呼吸，转视角有惯性滞后。
func _update_bob(delta: float) -> void:
	if _player == null or _view_root == null:
		return

	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var grounded := _player.is_on_floor()
	var walk := clampf(speed / maxf(_player.tuning.walk_speed, 0.01), 0.0, 1.6)
	var target_weight := walk if grounded else 0.2
	_bob_weight = lerpf(_bob_weight, target_weight, minf(1.0, 6.0 * delta))
	_bob_time += delta * TAU * (0.85 + speed * 0.14)

	# 转视角时的滞后：镜头转得快，手里的弓慢半拍
	var yaw := _player.rotation.y
	var pitch := _head.rotation.x if _head != null else 0.0
	var yaw_delta := rad_to_deg(wrapf(yaw - _prev_yaw, -PI, PI))
	var pitch_delta := rad_to_deg(pitch - _prev_pitch)
	_prev_yaw = yaw
	_prev_pitch = pitch
	var lag := Vector2(
		clampf(-yaw_delta * 0.5, -SWAY_ROTATION_DEGREES, SWAY_ROTATION_DEGREES),
		clampf(-pitch_delta * 0.45, -SWAY_ROTATION_DEGREES, SWAY_ROTATION_DEGREES)
	)
	_sway = _sway.lerp(lag, minf(1.0, 10.0 * delta))

	# 落地时补一记下沉，射箭时也有一点点后坐
	if grounded and not _was_grounded:
		_kick = maxf(_kick, 0.03)
	_was_grounded = grounded
	_kick = lerpf(_kick, 0.0, minf(1.0, 9.0 * delta))

	var breathe := sin(Time.get_ticks_msec() * 0.0016) * 0.0012 * (1.0 - clampf(walk, 0.0, 1.0))
	var side := sin(_bob_time) * BOB_SIDE * _bob_weight
	var up := sin(_bob_time * 2.0) * BOB_UP * _bob_weight + breathe - _kick
	var roll := sin(_bob_time) * BOB_ROLL_DEGREES * _bob_weight

	_view_root.position = Vector3(side, up, 0.0)
	_view_root.rotation_degrees = Vector3(_sway.y, _sway.x, roll)


## 两段手臂的肘部求解：已知肩、手和两段长度，求肘的位置。
##
## 肘落在「肩→手」连线的垂直平面上，方向由 bend 指定，避免反关节。
static func _solve_elbow(shoulder: Vector3, hand: Vector3, upper: float, forearm: float, bend: Vector3) -> Vector3:
	var to_hand := hand - shoulder
	var distance := to_hand.length()
	if distance < 0.0001:
		return shoulder + Vector3(0.0, -upper, 0.0)
	distance = clampf(distance, absf(upper - forearm) + 0.005, upper + forearm - 0.005)
	var direction := to_hand.normalized()
	var along := (upper * upper - forearm * forearm + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper * upper - along * along))
	var bend_direction := bend - direction * bend.dot(direction)
	if bend_direction.length() < 0.001:
		bend_direction = Vector3.DOWN
	return shoulder + direction * along + bend_direction.normalized() * height


## 把一段沿 +Y 的方柱摆到 from → to，粗细为 thickness（与起点同一坐标空间）。
static func _segment_transform(from: Vector3, to: Vector3, thickness: float) -> Transform3D:
	var delta := to - from
	var length := delta.length()
	if length < 0.0001:
		return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * thickness), from)
	var y := delta / length
	var reference := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var x := reference.cross(y).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x * thickness, y * length, z * thickness), from)


func _ammo_count() -> int:
	if _inventory == null:
		return 0
	return _inventory.count_item(ammo_item_id)


## 当前蓄力比例，供 HUD 显示。
func get_charge() -> float:
	return _charge


func is_aiming() -> bool:
	return _aiming
