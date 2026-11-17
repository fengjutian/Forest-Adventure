class_name Crosshair
extends Control
## 准星。极简十字，不使用强烈描边（docs/first-scene-design.md §9.1）。
##
## 瞄准时张开一点，蓄力时随蓄力比例收拢，给出「拉满了」的视觉反馈。

@export var extent: float = 6.0
@export var thickness: float = 1.5
@export var gap: float = 4.0
@export var color: Color = Color(1.0, 1.0, 1.0, 0.75)
## 瞄准时额外的张开量。
@export var aim_spread: float = 5.0
## 蓄力时的收拢量。
@export var charge_spread: float = 3.0

var _aiming: bool = false
var _charge: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_aiming(aiming: bool) -> void:
	if _aiming == aiming:
		return
	_aiming = aiming
	queue_redraw()


func set_charge(charge: float) -> void:
	var clamped := clampf(charge, 0.0, 1.0)
	if is_equal_approx(clamped, _charge):
		return
	_charge = clamped
	queue_redraw()


func _draw() -> void:
	var center := extent / 2.0
	var current_gap := gap
	if _aiming:
		current_gap += aim_spread
	current_gap -= charge_spread * _charge
	current_gap = maxf(1.0, current_gap)

	var alpha := 0.75 + 0.25 * _charge
	var draw_color := color
	draw_color.a = alpha

	draw_line(Vector2(center - current_gap - extent, center), Vector2(center - current_gap, center), draw_color, thickness)
	draw_line(Vector2(center + current_gap, center), Vector2(center + current_gap + extent, center), draw_color, thickness)
	draw_line(Vector2(center, center - current_gap - extent), Vector2(center, center - current_gap), draw_color, thickness)
	draw_line(Vector2(center, center + current_gap), Vector2(center, center + current_gap + extent), draw_color, thickness)
