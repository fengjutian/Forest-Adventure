class_name CampfireInteractable
extends Interactable
## 营火。安全据点：恢复状态、记录检查点、发出 camp.returned 事件。
##
## 视觉上包含石圈、交叠柴火、跳动的火光与飞散的火星，
## 是营地里唯一的暖色光源，也是「安全区」的核心视觉锚点。

@export var camp_id: StringName = &"camp"
@export var prompt_text: String = "在营火旁休息"
@export var restores_state: bool = true

var _last_visit: int = 0
var _light: OmniLight3D
var _flame_time: float = 0.0
var _base_energy: float = 3.4


func _build_visual() -> void:
	# 火源分组：野兽会绕开火光
	add_to_group(&"fire_source")

	for prop_name: StringName in [&"campfire_stones", &"campfire_logs"]:
		var mesh := PropKit.make_prop(prop_name)
		if mesh == null:
			continue
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.material_override = PropKit.painted_material()
		add_child(mesh_instance)

	_build_fire()


func _build_fire() -> void:
	_light = OmniLight3D.new()
	_light.name = "FireLight"
	_light.light_color = Color(1.0, 0.56, 0.2)
	_light.light_energy = _base_energy
	_light.omni_range = 14.0
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.75, 0.0)
	add_child(_light)

	var embers := CPUParticles3D.new()
	embers.name = "Embers"
	embers.amount = 26
	embers.lifetime = 1.4
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.18
	embers.direction = Vector3(0.0, 1.0, 0.0)
	embers.spread = 22.0
	embers.initial_velocity_min = 0.7
	embers.initial_velocity_max = 1.7
	embers.gravity = Vector3(0.0, 1.1, 0.0)
	embers.scale_amount_min = 0.04
	embers.scale_amount_max = 0.11
	embers.damping_min = 0.4
	embers.damping_max = 1.0
	embers.color = Color(1.0, 0.55, 0.18)
	embers.position = Vector3(0.0, 0.35, 0.0)

	var ember_mesh := SphereMesh.new()
	ember_mesh.radius = 0.06
	ember_mesh.height = 0.12
	ember_mesh.radial_segments = 5
	ember_mesh.rings = 3
	embers.mesh = ember_mesh
	embers.material_override = PropKit.glow_material(Color(1.0, 0.55, 0.18), 3.0)
	add_child(embers)


func _process(delta: float) -> void:
	if _light == null:
		return
	# 火焰跳动：两个不同频率的正弦叠加，避免机械感
	_flame_time += delta
	var flicker := 1.0 \
		+ sin(_flame_time * 9.3) * 0.13 \
		+ sin(_flame_time * 21.7) * 0.07 \
		+ sin(_flame_time * 37.1) * 0.03
	_light.light_energy = _base_energy * flicker


func get_prompt(_actor: Node) -> String:
	return prompt_text


func interact(actor: Node) -> void:
	_last_visit = int(Time.get_unix_time_from_system())

	if restores_state:
		var player := actor as Player
		if player != null:
			player.heal(player.tuning.max_health)
			player.stamina = player.tuning.max_stamina
			GameLog.info("营火恢复状态", {"camp": camp_id})

	EventBus.camp_returned.emit(camp_id)
