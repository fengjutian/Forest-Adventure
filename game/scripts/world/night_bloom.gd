class_name NightBloom
extends Node3D
## 夜间发光植物带（docs/vertical-slice-completion.md §4.4）。
##
## 夜里在溪谷上游沿岸长出一带发光植物，顺着溪水指向涌泉的方向。
## 它是纯环境引导：不给箭头，不给坐标，只把方向摆在那里。
##
## 表现由世界事件管理器驱动：night_bloom 事件开始时点亮，
## 结束时淡出。淡出而不是硬切，是为了不打断正在看它的玩家。

## 事件 ID。这个节点只响应这个事件。
@export var event_id: StringName = &"night_bloom"
## 植物带的起点（世界 XZ）。
@export var band_start: Vector2 = Vector2(2.0, -104.0)
## 植物带的终点（世界 XZ）。终点在涌泉方向。
@export var band_end: Vector2 = Vector2(15.0, -128.0)
## 植物数量。
@export var plant_count: int = 48
## 横向抖动幅度（米）。
@export var jitter: float = 2.6
## 点亮后的自发光强度。
@export var glow_energy: float = 2.0
## 淡入淡出的速度（强度/秒）。
@export var fade_speed: float = 1.6

var _material: StandardMaterial3D = null
var _energy: float = 0.0
var _target_energy: float = 0.0
var _instance: MultiMeshInstance3D = null


func _ready() -> void:
	add_to_group(&"world_event_effect")
	_build()
	_set_energy(0.0)
	visible = false


func _process(delta: float) -> void:
	if is_equal_approx(_energy, _target_energy):
		return
	_energy = move_toward(_energy, _target_energy, fade_speed * delta)
	_set_energy(_energy)
	visible = _energy > 0.001


## 世界事件接口。
func apply_world_event(_event_id: StringName, active: bool) -> void:
	_target_energy = glow_energy if active else 0.0
	GameLog.info("夜间发光带切换", {"active": active})


## 供测试用：当前发光强度。
func glow_level() -> float:
	return _energy


## 供测试用：目标发光强度。事件结束后会立刻掉到 0，实际亮度再慢慢淡下去。
func target_glow() -> float:
	return _target_energy


## 供测试用：植物带是否已经点亮。
func is_lit() -> bool:
	return _energy > 0.001


# ------------------------------------------------------------------ 构建

func _build() -> void:
	var field := _terrain_field()
	if field == null:
		GameLog.error("NightBloom 找不到地形高度场")
		return

	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.5
	_material.metallic = 0.0
	_material.emission_enabled = true
	_material.emission = Color(0.50, 0.84, 0.88)
	_material.emission_energy_multiplier = 0.0

	var mesh := PropKit.make_glow_sprout()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = plant_count

	var rng := RandomNumberGenerator.new()
	rng.seed = 51723
	var direction := (band_end - band_start).normalized()
	var side := Vector2(-direction.y, direction.x)

	for i in plant_count:
		var t := (float(i) + 0.5) / float(plant_count)
		var along := band_start.lerp(band_end, t)
		var offset := rng.randf_range(-jitter, jitter)
		var pos := along + side * offset
		var y := field.height_at(pos.x, pos.y)
		var scale := rng.randf_range(0.75, 1.35)
		var basis := Basis.from_euler(Vector3(0.0, rng.randf_range(0.0, TAU), 0.0)).scaled(Vector3.ONE * scale)
		multimesh.set_instance_transform(i, Transform3D(basis, Vector3(pos.x, y, pos.y)))
		multimesh.set_instance_color(i, Color(1, 1, 1).lerp(Color(0.78, 0.92, 0.95), rng.randf() * 0.6))

	_instance = MultiMeshInstance3D.new()
	_instance.name = "GlowSprouts"
	_instance.multimesh = multimesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_instance)


func _set_energy(value: float) -> void:
	if _material == null:
		return
	_material.emission_energy_multiplier = value


func _terrain_field() -> TerrainField:
	var world := get_tree().get_first_node_in_group(&"terrain") as ChunkedWorld
	if world == null:
		return null
	return world.field
