extends SceneTree
## 临时探针：测量候选地点的地形高度、坡度与植被密度。
## 用完即删。

func _init() -> void:
	var field := TerrainField.new(TerrainField.DEFAULT_SEED, TerrainField.DEFAULT_SIZE)

	print("=== 猎人营地遗址候选（松木林深处） ===")
	for c in [Vector2(150, -110), Vector2(130, -95), Vector2(168, -130),
			Vector2(115, -140), Vector2(196, -88), Vector2(142, -168)]:
		_report(field, c)

	print("")
	print("=== 守护者岗位候选（溪谷上游涌泉） ===")
	for c in [Vector2(18, -130), Vector2(24, -142), Vector2(14, -118),
			Vector2(30, -160), Vector2(20, -105)]:
		_report(field, c)

	print("")
	print("=== 溪流水位剖面（x = creek_center_x = %.1f） ===" % field.creek_center_x)
	for z in [-200.0, -160.0, -130.0, -100.0, -60.0, -20.0, 0.0, 24.0, 48.0, 72.0, 120.0]:
		var h := field.height_at(field.creek_center_x, z)
		print("  z=%7.1f  h=%7.2f" % [z, h])

	print("")
	print("=== 涨水段两端（涉水点 z∈[24,72]，x=%.1f） ===" % field.creek_center_x)
	for z in [10.0, 24.0, 40.0, 60.0, 72.0, 90.0]:
		var h := field.height_at(field.creek_center_x, z)
		var s := field.slope_at(field.creek_center_x, z)
		print("  z=%6.1f  h=%7.2f  slope=%.3f" % [z, h, s])

	quit()


func _report(field: TerrainField, c: Vector2) -> void:
	var h := field.height_at(c.x, c.y)
	var s := field.slope_at(c.x, c.y)
	var d := field.vegetation_density(c.x, c.y, 0.72)
	var creek_dist := absf(c.x - field.creek_center_x)
	print("  (%4d, %4d)  h=%7.2f  slope=%.3f  density=%.3f  离溪流=%5.1f  在世界内=%s"
		% [int(c.x), int(c.y), h, s, d, creek_dist, field.is_inside(c.x, c.y)])
