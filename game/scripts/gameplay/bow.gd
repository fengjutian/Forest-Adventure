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
##   - 左手扣在握把上、右手捏弦，双手都挂在弓身上
##   - 蓄力时弓弦折成 V 形、箭一起后移，右手跟着弦走
##   - 走路/冲刺时有持弓摆动，站定时有呼吸起伏，转视角有惯性滞后
##   - 落地、射击各有一记短促的下沉
##
## 只画到手腕：第一人称里伸出来的整条手臂只有「从画面底边插进来的两根管子」，
## 读起来比没有手臂更诡异。手边留一小截小臂就够了——
## 有它手才不是悬在画面里的方块，又不至于变成两根大锥子糊住半个屏幕。
##
## 视图模型单独打光：弓是屏幕左下角唯一的近景，
## 跟着场景的太阳走会一会儿刺眼一会儿漆黑（见下方 VIEW_MODEL_LAYER）。

signal fired(power: float)
signal fire_failed(reason: String)

@export var bow_item_id: StringName = &"bow"
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
##
## 弓挂在画面右下角、略微侧倾，视野中央完全让给准星。
@export var view_offset: Vector3 = Vector3(0.42, -0.48, -1.00)
@export var view_rotation_degrees: Vector3 = Vector3(10.0, 22.0, -14.0)
## 举弓瞄准时相对镜头的偏移与朝向。
##
## 弓摆在画面左侧，偏航 26° 让弓面侧过来——
## 正对着镜头时弓臂会缩成一根竖棍，偏一点才有厚度和纵深。
## 往左下再压一点：举弓时弓的最上端不越过地平线太多，
## 视野中央和准星周围完全让出来，只留弓臂和弓弦贴在左边缘。
## 箭不跟着弓转，它单独朝相机前方偏右，箭尖因此收拢到准星附近。
## 箭的实际飞行方向仍取自相机前方，与画面构图无关。
@export var aim_view_offset: Vector3 = Vector3(-0.44, -0.20, -1.10)
@export var aim_view_rotation_degrees: Vector3 = Vector3(5.0, -26.0, 8.0)
## 第一人称模型整体缩放。
##
## 弓按视图模型的尺寸（0.58 m 高的短弓）建模，1.0 时在 1.15 m 处
## 会占到屏幕高度的六成、横在画面左三分之一——举弓时上半支弓臂
## 越过了地平线，把左边那片林子整块吃掉。
## 0.90 加上左下方的偏移，最上端压在视线下沿、准星周围全让出来，
## 同时弓和手仍是同一套缩放，不会出现「小方块手」。
@export var view_scale: float = 0.90
## 箭在相机空间里的指向（举起瞄准 / 垂弓时）。
@export var aim_arrow_direction: Vector3 = Vector3(0.33, 0.09, -0.94)
@export var hip_arrow_direction: Vector3 = Vector3(0.55, -0.42, -0.72)

## 视图模型单独占一个视觉层（第 19 层）。
##
## 场景里只有一盏太阳光：弓背对太阳时整把弓会变成一块黑影，
## 手里的东西必须永远看得清，所以给视图模型单独一套固定灯。
## 世界里的太阳与手电都被排除在这层之外
## （main.tscn 的 Sun / player.tscn 的 Flashlight 都设了 light_cull_mask = 524287），
## 否则弓会随时间变成白天刺眼、夜晚漆黑的一块板。
const VIEW_MODEL_LAYER := 1 << 19

## 弓本地坐标里的关键点。
const GRIP_POINT := Vector3(-0.115, 0.0, 0.0)
const STRING_TOP := Vector3(-0.030, 0.296, 0.0)
const STRING_BOTTOM := Vector3(-0.030, -0.296, 0.0)
## 弓弦静止位置（也是箭尾位置）。
const NOCK_REST := Vector3(-0.030, 0.004, 0.018)
## 满蓄力时弦被拉后的距离（弓本地单位）。
##
## 0.1 m 对应真实弓箭拉弦后的弦心行程，够用又不至于把弓弦拉成一张弓。
const MAX_DRAW := 0.1
## 持弓摆动幅度（米 / 度）。
const BOB_SIDE := 0.009
const BOB_UP := 0.006
const BOB_ROLL_DEGREES := 1.1
const SWAY_ROTATION_DEGREES := 2.2

## 左手（握弓）的手指朝向与小臂朝向，相机空间。
##
## 小臂指向决定了手从画面哪个方向插进来：左手往左下、右手往右下，
## 两条手臂各自从画面底边斜插出去，像「人举着弓」而不是「弓浮在半空」。
const BOW_HAND_FINGER := Vector3(1.0, 0.05, 0.15)
const BOW_HAND_ARM := Vector3(-0.58, -0.80, 0.15)
## 右手（拉弦）的手指朝向与小臂朝向，相机空间。
##
## 拉弦手的手指朝上勾着弦，小臂从右下角伸进来。
## 肘部必须朝「后下方」（+Z 是身后）：肘部朝前的话小臂会横着掠过
## 画面中段，像一根横杆横穿视野；朝后下它才会缩到画面右下角出画。
const STRING_HAND_FINGER := Vector3(0.1, 0.92, 0.38)
const STRING_HAND_ARM := Vector3(0.32, -0.92, 0.18)

var _player: Player = null
## 背包只用来确认玩家身上有弓。箭矢无限供应，不再读背包的弹药
## （docs/archery-and-realism.md §2）。
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
## 左右小臂：与对应的手共用同一套基，
## 手的局部 -Y 就是小臂伸出去的方向，所以两者天然接得上。
var _left_arm: MeshInstance3D = null
var _right_arm: MeshInstance3D = null

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
## 箭在相机空间里的当前指向（平滑过渡，避免抬弓瞬间跳变）。
var _arrow_dir: Vector3 = Vector3(0.33, 0.09, -0.94)
## 举弓程度：0 = 垂弓，1 = 举弓瞄准。
var _raise: float = 0.0


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
	# 箭矢无限供应（docs/archery-and-realism.md §2），
	# 这里不需要监听背包变动，也不需要广播弹药数量。


## 第一人称持弓：弓、弦、箭、双手，全部挂在弓上。
##
## 结构：
##   Camera3D
##   └── BowViewModel (Node3D)        摆动/呼吸/落地下沉都加在这一层
##       ├── BowViewLight             只照视图模型的一层补光
##       ├── BowPivot (Node3D)        弓的抬放与朝向
##       │   ├── BowFrame
##       │   ├── StringTop / StringBottom
##       │   └── LeftHand / RightHand
##       └── NockedArrow              单独挂在相机层，方向不跟着弓偏航
##
## 手挂在弓上而不是相机上：这样手和弓共用一套缩放，
## 手掌与握把的比例才是对的。
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

	var string_mesh := PropKit.make_bow_string()
	_string_top = _add_mesh(_bow_pivot, "StringTop", string_mesh)
	_string_bottom = _add_mesh(_bow_pivot, "StringBottom", string_mesh)

	var hand_mesh := PropKit.make_player_hand(Color(0.185, 0.10, 0.058))
	_left_hand = _add_mesh(_bow_pivot, "LeftHand", hand_mesh)
	_right_hand = _add_mesh(_bow_pivot, "RightHand", hand_mesh)

	# 小臂：从画面底边斜插进来，给手一个锚点。
	# 没有它，两只手就是悬在空中的方块，怎么调都像贴图。
	# 袖子是深色的：浅色袖子在这套明亮画面里会变成一根抢视线的管子。
	var arm_mesh := PropKit.make_player_forearm(Color(0.095, 0.068, 0.038), Color(0.14, 0.09, 0.052))
	_left_arm = _add_mesh(_bow_pivot, "LeftArm", arm_mesh)
	_right_arm = _add_mesh(_bow_pivot, "RightArm", arm_mesh)

	# 箭挂在相机层，不跟着弓一起偏航。
	# 跟着弓转的话箭会指向画面左后方，怎么调都不对。
	_nocked_arrow = _add_mesh(_view_root, "NockedArrow", PropKit.make_bow_nocked_arrow())

	_build_view_light()


## 视图模型灯组：一盏主光 + 一盏轮廓光。
##
## 主光从相机后上方打过来，朝镜头的那一面才有立体感；
## 轮廓光从左后方压一层暗面，免得弓变成一张剪纸。
func _build_view_light() -> void:
	var key := DirectionalLight3D.new()
	key.name = "BowViewKeyLight"
	key.light_cull_mask = VIEW_MODEL_LAYER
	key.light_energy = 0.45
	key.light_color = Color(1.0, 0.97, 0.92)
	key.shadow_enabled = false
	key.rotation_degrees = Vector3(-30.0, 22.0, 0.0)
	_camera.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.name = "BowViewRimLight"
	rim.light_cull_mask = VIEW_MODEL_LAYER
	rim.light_energy = 0.16
	# 轮廓光不能用冷色：视图模型里的暗色物件（袖子、皮手套）
	# 会被冷环境光染成青灰色，在暖调的森林里像贴上去的塑料。
	rim.light_color = Color(0.95, 0.94, 0.92)
	rim.shadow_enabled = false
	rim.rotation_degrees = Vector3(-8.0, -135.0, 0.0)
	_camera.add_child(rim)


func _add_mesh(parent: Node3D, node_name: String, mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = PropKit.painted_material()
	node.layers = VIEW_MODEL_LAYER
	# 视图模型不该在世界里投影：一把弓在雪地上投个影子出来会非常出戏
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


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

	# 箭矢无限供应：不扣背包，也不检查数量
	# （docs/archery-and-realism.md §2）。
	# 体力才是唯一的消耗型资源——蓄力已经扣过了。

	spawn_arrow(power)
	_kick = maxf(_kick, 0.022)
	fired.emit(power)


## 生成一支箭，返回生成的投射物（测试与调试用；没生成则返回 null）。
##
## 出膛点默认就是「搭在弦上那支箭的箭尾」：扣扳机时，弦上那支箭接着飞出去，
## 而不是从屏幕中央凭空刷出一支新的。目标比弦还近（贴脸、贴着墙）时退回
## 相机前方的枪口位置——否则箭会生在目标后面，从目标背后飞走。
##
## 暴露为公开方法，方便测试直接走真实发射路径。
func spawn_arrow(power: float) -> ArrowProjectile:
	if _camera == null or not _camera.is_inside_tree():
		return null
	var forward := -_camera.global_transform.basis.z
	# 兜底出膛点：比相机低 15 cm（持弓手的高度）、向前 0.6 m
	var muzzle := _camera.global_position + forward * 0.6 - _camera.global_transform.basis.y * 0.15

	# 出膛方向指向「准星真正打到的那个点」，而不是简单地和视线平行。
	# 出膛点在准星下方，速度若平行于视线，整支箭就会一直低一截：
	# 5 m 处正好从狼头上擦过去，玩家会觉得「准星明明压住了却没中」。
	# 从出膛点连线到命中点，近处自动补偿这个落差，远处仍然要自己抬枪补弹道。
	var aim_point := _crosshair_point()
	var aim_distance := _camera.global_position.distance_to(aim_point)

	var spawn := muzzle
	if _nocked_arrow != null and _nocked_arrow.is_inside_tree():
		var nock := _nocked_arrow.global_position
		# 目标必须明显在弦前面，箭才从弦上发
		if aim_distance > _camera.global_position.distance_to(nock) + 0.25:
			spawn = nock

	var direction := (aim_point - spawn).normalized()
	if direction.dot(forward) < 0.2:
		direction = forward

	var arrow := ArrowProjectile.new()
	arrow.name = "Arrow"
	arrow.damage = damage
	arrow.hit.connect(_on_arrow_hit)
	arrow.launch(direction, power)

	# 必须先入树再设 global_position：节点不在场景树里时 Godot 会忽略
	# 这个赋值，箭会落在父节点原点上（也就是世界原点），而不是射手手里。
	var parent := _player.get_parent()
	if parent == null:
		parent = get_tree().current_scene
	parent.add_child(arrow)
	# 往前让 6 cm，避免和还挂在弦上的那支箭共面闪烁
	arrow.global_position = spawn + direction * 0.06
	# 入树后立刻摆正朝向，否则第一帧的箭是横着的
	arrow.face(direction)

	# 弓响会暴露位置
	_player.notify_noise(1.2)
	return arrow


## 准星指向的世界坐标：从相机沿视线打一条射线，取第一个命中点。
##
## 没打到东西就返回 200 m 外的远点——那支箭的初速方向几乎等同于视线，
## 弹道下坠仍然要玩家自己估。
func _crosshair_point() -> Vector3:
	var forward := -_camera.global_transform.basis.z
	var from := _camera.global_position
	var to := from + forward * 200.0
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# 世界层 + 敌人层，和箭矢的射线一致；玩家自己不在这些层上，不会挡住射线
	query.collision_mask = 1 | 8
	query.collide_with_areas = false
	var result := space.intersect_ray(query)
	if result.is_empty():
		return to
	return result["position"]


func _on_arrow_hit(_target: Node, _damage: float, weakpoint: bool) -> void:
	EventBus.hit_confirmed.emit(weakpoint)


## 更新弓的抬放。
##
## 手里有弓就一直拿着（垂在画面右下），瞄准或蓄力时抬到画面左侧三分之一，
## 把屏幕中央让给准星。弓的朝向与位置都在这里平滑过渡。
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
	# 举弓程度：0 是垂弓，1 是举弓。右手的位置跟着它走。
	_raise = lerpf(_raise, 1.0 if raised else 0.0, minf(1.0, 18.0 * delta))

	# 瞄准时收窄视野
	var target_fov := _base_fov
	if _aiming:
		target_fov = aim_fov
	_camera.fov = lerpf(_camera.fov, target_fov, 0.25)

	if _player != null:
		_player.look_sensitivity_scale = aim_sensitivity_scale if _aiming else 1.0


## 每帧摆放双手、弓弦与箭，并叠加持弓的摆动。
func _update_pose(has_bow: bool, delta: float) -> void:
	_update_bob(delta)
	if not has_bow or _view_root == null:
		return

	# 拉弦量：蓄力时跟着 charge 走，松手/收弓时回弹
	var draw_target := _charge * MAX_DRAW if (_aiming or _charging) else 0.0
	_draw = lerpf(_draw, draw_target, minf(1.0, 18.0 * delta))

	# 双手与弓同一个父节点，用弓的本地坐标摆位即可
	var nock_local := NOCK_REST + Vector3(0.0, 0.0, _draw)

	# 弓弦：两段折线，从上下弓梢连到弦心；拉弦时折成 V 形
	_string_top.transform = _segment_transform(STRING_TOP, nock_local, 0.006)
	_string_bottom.transform = _segment_transform(STRING_BOTTOM, nock_local, 0.006)

	# 左手扣住弓把：四指朝右绕过竖直的弓把，小臂往左下出画
	var left_transform := Transform3D(
		_hand_basis(_to_bow_dir(BOW_HAND_FINGER), _to_bow_dir(BOW_HAND_ARM)),
		GRIP_POINT
	)
	_left_hand.transform = left_transform
	# 小臂不能用手的基。
	# 手要同时对齐「手指」和「小臂」两个方向，可这两个方向并不正交，
	# Basis.looking_at 会把小臂投影到手指的垂面上——右手因此被拧成
	# 92% 朝右、横着扫过整个屏幕，而不是按设定往右下出画。
	# 小臂是根轴对称的长条，单独给它一个「-Y 对准手臂方向」的基即可。
	_left_arm.transform = Transform3D(_limb_basis(_to_bow_dir(BOW_HAND_ARM)), GRIP_POINT)

	# 右手：拉弦时捏住弦心，没拉弦时垂在弓把下方。
	# 一直僵在握把边上，两只手会挤在一起，像一块看不出形状的疙瘩。
	#
	# 手必须真的搭在弦上：偏移一大，弦就从手边擦过去而不是穿过指弯，
	# 看起来就是「一只手悬在弦旁边」。+X 是手从右侧捏弦的那点厚度，
	# +Z 让掌心落在弦后（手指才包得住弦）。
	var draw_hand := nock_local + Vector3(0.030, -0.020, 0.028)
	var rest_hand := GRIP_POINT + Vector3(0.02, -0.21, 0.05)
	var string_hand_pos := rest_hand.lerp(draw_hand, _raise)
	var right_transform := Transform3D(
		_hand_basis(_to_bow_dir(STRING_HAND_FINGER), _to_bow_dir(STRING_HAND_ARM)),
		string_hand_pos
	)
	_right_hand.transform = right_transform
	_right_arm.transform = Transform3D(_limb_basis(_to_bow_dir(STRING_HAND_ARM)), string_hand_pos)

	_update_arrow(nock_local, delta)


## 箭的摆放：箭尾钉在弦心，方向单独给。
##
## 箭不跟着弓的偏航转，否则箭会指向画面左后方。
## 这里的方向写在相机空间里，箭尖因此能收拢到准星附近。
func _update_arrow(nock_local: Vector3, delta: float) -> void:
	if _nocked_arrow == null:
		return
	var target := aim_arrow_direction if (_aiming or _charging) else hip_arrow_direction
	_arrow_dir = _arrow_dir.lerp(target.normalized(), minf(1.0, 12.0 * delta)).normalized()
	var nock_view := _bow_pivot.transform * nock_local
	_nocked_arrow.transform = Transform3D(Basis.looking_at(_arrow_dir, Vector3.UP), nock_view)


## 手的第一人称朝向。
##
## 手模的手指是 -Z、小臂是 -Y，所以造一个正交基：
## -Z 对准手指方向，-Y 大致对准小臂方向。
##
## 注意这只是「手」的朝向：手指与小臂在解剖上并不垂直，
## 这里以手指为准，小臂方向会被投影到手指的垂面上。
## 小臂本身另用 _limb_basis 摆，见 _update_pose。
static func _hand_basis(finger_dir: Vector3, arm_dir: Vector3) -> Basis:
	var forward := finger_dir.normalized()
	var up := -arm_dir.normalized()
	if absf(forward.dot(up)) > 0.98:
		up = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	return Basis.looking_at(forward, up)


## 肢体（小臂）的朝向：网格沿 -Y 伸长，所以本地 -Y 精确对准 direction。
##
## 绕自身长轴的旋转对圆柱段没有意义，取任意正交补即可。
static func _limb_basis(direction: Vector3) -> Basis:
	var y := -direction.normalized()
	var reference := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := reference.cross(y).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


## 把相机空间的方向换算成弓的本地方向。
func _to_bow_dir(camera_dir: Vector3) -> Vector3:
	if _bow_pivot == null:
		return camera_dir
	return (_bow_pivot.transform.basis.inverse() * camera_dir).normalized()


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


## 当前蓄力比例，供 HUD 显示。
func get_charge() -> float:
	return _charge


func is_aiming() -> bool:
	return _aiming
