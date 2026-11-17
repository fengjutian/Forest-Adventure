class_name QuestStage
extends Resource
## 任务阶段。阶段内所有目标完成后进入下一阶段。

@export var id: StringName = &""
@export_multiline var description: String = ""
## Array[QuestObjective]
@export var objectives: Array = []
