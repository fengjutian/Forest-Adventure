class_name Crosshair
extends Control
## 准星。极简十字，不使用强烈描边（docs/first-scene-design.md §9.1）。

@export var extent: float = 6.0
@export var thickness: float = 1.5
@export var gap: float = 4.0
@export var color: Color = Color(1.0, 1.0, 1.0, 0.75)


func _draw() -> void:
	var center := extent / 2.0
	draw_line(Vector2(center - gap - extent, center), Vector2(center - gap, center), color, thickness)
	draw_line(Vector2(center + gap, center), Vector2(center + gap + extent, center), color, thickness)
	draw_line(Vector2(center, center - gap - extent), Vector2(center, center - gap), color, thickness)
	draw_line(Vector2(center, center + gap), Vector2(center, center + gap + extent), color, thickness)
