extends SceneTree
## 临时探针：测量溪流横截面，找出两岸低洼（可涉水）位置。
## 用完即删。

func _init() -> void:
	var field := TerrainField.new(TerrainField.DEFAULT_SEED, TerrainField.DEFAULT_SIZE)
	var cx := field.creek_center_x

	print("=== 溪流横截面（岸高随 x 变化） ===")
	for z in [-90.0, -40.0, 10.0, 30.0, 48.0, 66.0, 90.0, 140.0]:
		var row := "  z=%6.1f : " % z
		for x in [cx - 9.0, cx - 6.0, cx - 3.0, cx, cx + 3.0, cx + 6.0, cx + 9.0]:
			row += "%6.2f " % field.height_at(x, z)
		print(row)
	print("  （列顺序：x = creek-9, -6, -3, 0, +3, +6, +9）")

	print("")
	print("=== 涨水段 z∈[24,72] 逐点岸高 ===")
	for z in range(18, 79, 6):
		var left := field.height_at(cx - 4.0, float(z))
		var right := field.height_at(cx + 4.0, float(z))
		print("  z=%3d  左岸(x=7)=%6.2f  右岸(x=15)=%6.2f" % [z, left, right])

	print("")
	print("=== 营地附近溪流水面（z=0 附近） ===")
	for z in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		print("  z=%6.1f  左岸(x=7)=%6.2f  溪心=%6.2f  右岸(x=15)=%6.2f"
			% [z, field.height_at(cx - 4.0, z), field.height_at(cx, z), field.height_at(cx + 4.0, z)])

	quit()
