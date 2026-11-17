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
## 弓与镜头之间的手持偏移。
@export var view_offset: Vector3 = Vector3(0.24, -0.2, -0.42)

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
	EventBus.ammo_changed.emit(ammo_item_id, _ammo_count())


## 第一人称手里的弓。
func _build_view_model() -> void:
	_view_model = MeshInstance3D.new()
	_view_model.name = "BowViewModel"
	_view_model.mesh = PropKit.make_bow()
	_view_model.material_override = PropKit.painted_material()
	_view_model.position = view_offset
	_view_model.rotation_degrees = Vector3(4.0, 9.0, 6.0)
	_view_model.visible = false
	_camera.add_child(_view_model)


func _process(delta: float) -> void:
	if _player == null or _camera == null:
		return

	var control_ok := _player.is_control_enabled() and _player.is_mouse_captured()
	var has_bow := _inventory != null and _inventory.has_item(bow_item_id)

	_aiming = control_ok and has_bow and Input.is_action_pressed("aim")

	if control_ok and has_bow and Input.is_action_pressed("fire"):
		_charge_up(delta)
	elif _charging:
		_release_and_fire()

	_update_view(control_ok and has_bow)


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

	_spawn_arrow(power)
	fired.emit(power)


func _spawn_arrow(power: float) -> void:
	var arrow := ArrowProjectile.new()
	arrow.name = "Arrow"
	arrow.damage = damage
	arrow.hit.connect(_on_arrow_hit)
	var forward := -_camera.global_transform.basis.z
	arrow.global_position = _camera.global_position + forward * 0.6 - _camera.global_transform.basis.y * 0.15
	arrow.launch(forward, power)

	var parent := _player.get_parent()
	if parent == null:
		parent = get_tree().current_scene
	parent.add_child(arrow)

	# 弓响会暴露位置
	_player.notify_noise(1.2)


func _on_arrow_hit(_target: Node, _damage: float, weakpoint: bool) -> void:
	EventBus.hit_confirmed.emit(weakpoint)


func _update_view(can_use: bool) -> void:
	if _view_model != null:
		# 瞄准或蓄力时才举起弓
		_view_model.visible = can_use and (_aiming or _charging)

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
