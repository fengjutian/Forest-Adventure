class_name QuestDefinition
extends Resource
## 任务定义（docs/technical-design.md §4.4）：只读设计数据。
##
## 运行期状态保存在 QuestState 中，二者分离。

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""
## 进入场景时是否自动开始。
@export var auto_start: bool = true
## Array[QuestStage]
@export var stages: Array = []
