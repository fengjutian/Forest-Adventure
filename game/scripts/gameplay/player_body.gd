extends MeshInstance3D
## 玩家本体网格：在 _ready 里用 PropKit 程序化拼装。
##
## 为什么放在脚本里而不是写进 .tscn：
## 身体和弓、林狼一样都是「盒体 + 锥体 + 顶点色」的灰盒资产，
## 统一放在 prop_kit 里。正式美术资产到位后只改 prop_kit，
## 场景文件和调用方都不用动。
##
## 只做躯干和腿（见 PropKit.make_player_body）：手臂归弓的视图模型管。
##
## 蹲伏时的整体压缩由 player.gd 驱动（按相机高度缩 Y），
## 这里不关心蹲伏，只负责把网格建出来。

func _ready() -> void:
	mesh = PropKit.make_player_body()
	material_override = PropKit.painted_material()
