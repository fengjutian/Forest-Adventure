class_name GuardianEnemy
extends EnemyBase
## 异常守护者（docs/vertical-slice-completion.md §2）。
##
## 物种特性：
##   - 单体。守着一个地方，没有同伴，也就不会有群狼式的示警。
##   - 慢速、高生命。追不上玩家，所以玩家有余裕绕到背后。
##   - 攻击前摇明显（1.15 秒）：躲得开，也能被打断。
##   - 弱点是背上的结晶，要先命中够多次「观察」到才会暴露。
##   - 不逃跑，也不怕火：它是异常体，狼的求生本能套不上它。
##
## 数值全部在 scenes/enemies/guardian.tscn 里配置，便于和 wolf.tscn 对照。

## 离开岗位多远算跑偏了。超出后会主动返回涌泉，而不是在原地乱转。
const POST_RADIUS: float = 8.0
## 返回岗位时的移动速度。
const RETURN_SPEED: float = 2.2

## 岗位坐标。出生点就是岗位。
var _home_point: Vector3 = Vector3.ZERO


func _ready() -> void:
	super()
	add_to_group(&"guardian")
	# 基类已经把岗位对齐到地面高度了（_home），这里直接沿用。
	_home_point = _home
	# 场景里写死的 y 是 0，真实地面在别处。
	# 基类每帧会把敌人贴到地面，但那要几帧；这里直接就位。
	if _terrain != null and _terrain.has_method("height_at"):
		var g := global_position
		global_position = Vector3(g.x, float(_terrain.call("height_at", g.x, g.z)), g.z)


## 躯干与背部结晶。结晶用自发光材质，弱点就在它上面。
func _build_visual() -> void:
	var body_color := Color(0.145, 0.16, 0.145)

	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = PropKit.make_guardian_body(body_color)
	body.material_override = PropKit.painted_material()
	add_child(body)

	var crystal := MeshInstance3D.new()
	crystal.name = "Crystal"
	crystal.mesh = PropKit.make_guardian_crystal()
	# 自发光强度别调太高：AgX 会把高饱和自发光冲成灰白，
	# 1.2 足够让结晶在林子里一眼可见，又不会糊成一团光。
	crystal.material_override = PropKit.glow_material(Color(0.40, 0.76, 0.82), 1.2)
	add_child(crystal)


## 动作层：跑偏了就回岗位。
##
## 守护型敌人不追着玩家满山跑——它守的是地方，不是你。
## 脱战的判定放在 EnemyBase._decide() 里（leash_radius），
## 守护者的 leash_radius 设为 20 m，所以它最多追出岗位 20 m。
##
## 这里刻意不覆写 _steer_direction()：基类的实现不绕火源，
## 于是守护者无视火光。狼畏火，它不怕——两种敌人要两种应对。
func _act(delta: float) -> void:
	if state != State.CHASE and state != State.ATTACK:
		if global_position.distance_to(_home_point) > POST_RADIUS:
			_move_toward(_home_point, RETURN_SPEED, delta)
			return
	super(delta)
