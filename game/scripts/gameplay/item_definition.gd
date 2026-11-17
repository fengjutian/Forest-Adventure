class_name ItemDefinition
extends Resource
## 物品定义（docs/technical-design.md §4.4）。
##
## 只读设计数据，与玩家背包中的运行时数量分离。

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var max_stack: int = 1
@export var tags: Array[StringName] = []
