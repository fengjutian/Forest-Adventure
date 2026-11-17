extends Node
## 截图工具：在真实渲染后端下抓取一帧，输出 PNG。
##
## 用法：godot --path game res://tests/capture_screenshot.tscn
## 注意：必须使用带图形后端的 Godot（不能 --headless），否则拿到的是空帧。

@export var output_path: String = "res://../build/screenshots/frame.png"
@export var settle_frames: int = 12


func _ready() -> void:
	for i in range(settle_frames):
		await get_tree().process_frame

	await RenderingServer.frame_post_draw

	var viewport := get_viewport()
	var image := viewport.get_texture().get_image()
	if image == null:
		push_error("无法取得渲染结果")
		get_tree().quit(1)
		return

	var absolute := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var err := image.save_png(absolute)
	if err != OK:
		push_error("截图写入失败：%s（错误 %d）" % [absolute, err])
		get_tree().quit(1)
		return

	print("SCREENSHOT_SAVED:%s %dx%d" % [absolute, image.get_width(), image.get_height()])
	get_tree().quit(0)
