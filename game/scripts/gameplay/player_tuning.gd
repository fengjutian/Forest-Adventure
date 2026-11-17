class_name PlayerTuning
extends Resource
## 玩家关键参数（docs/technical-design.md §4.2）。
##
## 数值集中存放为 Resource，便于调参与存档，不散落在脚本里。

@export_group("移动")
@export var walk_speed := 4.5
@export var sprint_speed := 7.0
@export var crouch_speed := 2.2
@export var acceleration := 14.0
@export var air_control := 0.25
@export var jump_velocity := 4.2
@export var gravity_scale := 1.0

@export_group("视角")
@export var mouse_sensitivity := 0.002
@export var max_pitch_degrees := 89.0

@export_group("体力")
@export var max_stamina := 100.0
@export var stamina_drain_per_second := 18.0
@export var stamina_regen_per_second := 12.0
@export var stamina_regen_delay := 0.8

@export_group("体型")
@export var stand_height := 1.8
@export var stand_radius := 0.35
@export var crouch_height := 1.1
@export var crouch_radius := 0.35
@export var eye_offset_stand := 1.62
@export var eye_offset_crouch := 0.95
@export var step_height := 0.4

@export_group("生命与受伤")
@export var max_health := 100.0
## 超过该下落距离开始计算跌落伤害。
@export var safe_fall_distance := 3.0
## 每米落差造成的伤害。
@export var fall_damage_per_meter := 12.0

@export_group("手电筒")
@export var flashlight_battery_max := 100.0
@export var flashlight_drain_per_second := 1.5
