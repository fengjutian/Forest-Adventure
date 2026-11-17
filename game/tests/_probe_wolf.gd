extends SceneTree
## 临时诊断：检查林狼网格的顶点色是否真的写进了 ARRAY_COLOR。

func _initialize() -> void:
	var fur := Color(0.33, 0.3, 0.28)
	var belly := Color(0.52, 0.49, 0.45)
	var mesh := PropKit.make_wolf_body(fur, belly)
	print("SURFACES:", mesh.get_surface_count())
	var arrays := mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	print("VERT_COUNT:", verts.size())
	print("COLOR_COUNT:", colors.size())
	for i in range(mini(4, colors.size())):
		print("C", i, "=", colors[i], " v=", verts[i])
	if colors.size() > 0:
		print("C_LAST=", colors[colors.size() - 1])
	var mat := PropKit.painted_material()
	print("MAT_VERTEX_COLOR_AS_ALBEDO:", mat.vertex_color_use_as_albedo)
	print("MAT_CLASS:", mat.get_class())
	# 顺带检查弓
	var bow := PropKit.make_bow()
	var barrays := bow.surface_get_arrays(0)
	var bcolors: PackedColorArray = barrays[Mesh.ARRAY_COLOR]
	print("BOW_COLOR_COUNT:", bcolors.size())
	if bcolors.size() > 0:
		print("BOW_C0=", bcolors[0])
	quit()
