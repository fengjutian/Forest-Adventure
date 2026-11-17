class_name Bow
extends Node3D
## 弓箭（docs/combat-and-progression.md §1、§8）。
##
## 垂直切片只做弓这一种主武器：
##   - 右键瞄准：视野收窄、鼠标灵敏度降低
##   - 左键按住蓄力，松开射箭
##   - 蓄力消耗体力，体力不足就蓄不满
##   - 箭矢从背包扣除，打空就没有远程手段

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
@export var view_offset: Vector3 = Vector3(0.3, -0.26, -0.4)
@export var view_rotation_degrees: Vector3 = Vector3(14.0, 30.0, 24.0)
## 举弓瞄准时相对镜头的偏移与朝向。弓弦落在屏幕中心。
@export var aim_view_offset: Vector3 = Vector3(0.0, -0.02, -0.4)
@export var aim_view_rotation_degrees: Vector3 = Vector3(0.0, 16.0, 0.0)
## 第一人称模型整体缩放。弓高约 1.26m，缩到 0.26 后刚好占满屏幕高度。
@export var view_scale: float = 0.26

var _player: Player = null
var _inventory: Inventory = null
var _camera: Camera3D = null
var _view_model: MeshInstance3D = null

var _charge: float = 0.0
var _charging: bool = false
var _aiming: bool = false
var _base_fov: float = 75.0


func _ready() -> void:
	_player = get_tree().get_first_node_in_group(&"player") as Player
	if _player == null:
		return
	_inventory = _player.get_node_or_null("Inventory") as Inventory
	_camera = _player.get_node_or_null("Head/Camera3D") as Camera3D
	if _camera == null:
		return
	_base_fov = _camera.fov

	_build_view_model()

	# 箭矢数量会因为初始装备、拾取掉落物、其它消耗而变化，
	# 背包一有变动就重新广播，否则 HUD 会一直显示 0。
	if _inventory != null:
		_inventory.item_added.connect(_on_inventory_changed)
		_inventory.item_removed.connect(_on_inventory_changed)

	EventBus.ammo_changed.emit(ammo_item_id, _ammo_count())


## 第一人称手里的弓。
func _build_view_model() -> void:
	_view_model = MeshInstance3D.new()
	_view_model.name = "BowViewModel"
	_view_model.mesh = PropKit.make_bow()
	_view_model.material_override = PropKit.painted_material()
	_view_model.position = view_offset
	_view_model.rotation_degrees = view_rotation_degrees
	_view_model.scale = Vector3.ONE * view_scale
	_view_model.visible = false
	_camera.add_child(_view_model)


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
	# 必须先入树再设 global_position：
	# 节点没入树时 Godot 会把 global_position 写进「局部」变换，
	# 结果就是箭整体偏移父节点的位移（父节点在原点时看不出来），
	# 而且每次射击都会刷一条引擎错误。
	# 必须先入树再设 global_position：
	# 节点没入树时 Godot 会把 global_position 写进「局部」变换，
	# 结果就是箭整体偏移父节点的位移（父节点在原点时看不出来），
	# 而且每次射击都会刷一条引擎错误。
	var parent := _player.get_parent()
	if parent == null:
		parent = get_tree().current_scene
	parent.add_child(arrow)
	arrow.global_position = _camera.global_position + forward * 0.6 - _camera.global_transform.basis.y * 0.15

	# 弓响会暴露位置
	_player.notify_noise(1.2)


func _on_arrow_hit(_target: Node, _damage: float, weakpoint: bool) -> void:
	EventBus.hit_confirmed.emit(weakpoint)


## 更新第一人称弓的姿态。
##
## 手里有弓就一直拿在手上（垂在画面右下），瞄准或蓄力时抬到屏幕中心。
func _update_view(has_bow: bool, delta: float) -> void:
	if _view_model != null:
		_view_model.visible = has_bow

		var raised := _aiming or _charging
		var target_offset := aim_view_offset if raised else view_offset
		var target_rotation := aim_view_rotation_degrees if raised else view_rotation_degrees
		var weight := minf(1.0, 12.0 * delta)
		_view_model.position = _view_model.position.lerp(target_offset, weight)
		_view_model.rotation_degrees = _view_model.rotation_degrees.lerp(target_rotation, weight)

	# 瞄准时收窄视野
	var target_fov := _base_fov
	if _aiming:
		target_fov = aim_fov
	_camera.fov = lerpf(_camera.fov, target_fov, 0.25)

	if _player != null:
		_player.look_sensitivity_scale = aim_sensitivity_scale if _aiming else 1.0


func _ammo_count() -> int:
	if _inventory == null:
		return 0
	return _inventory.count_item(ammo_item_id)


## 当前蓄力比例，供 HUD 显示。
func get_charge() -> float:
	return _charge


func is_aiming() -> bool:
	return _aiming
