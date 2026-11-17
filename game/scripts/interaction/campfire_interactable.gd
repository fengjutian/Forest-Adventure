class_name CampfireInteractable
extends Interactable
## 营火。安全据点：恢复状态、记录检查点、发出 camp.returned 事件。

@export var camp_id: StringName = &"camp"
@export var prompt_text: String = "休息"
@export var restores_state: bool = true

var _last_visit: int = 0


func get_prompt(_actor: Node) -> String:
	return prompt_text


func interact(actor: Node) -> void:
	_last_visit = int(Time.get_unix_time_from_system())

	if restores_state:
		var player := actor as Player
		if player != null:
			player.heal(player.tuning.max_health)
			player.stamina = player.tuning.max_stamina
			GameLog.info("营火恢复状态", {"camp": camp_id})

	EventBus.camp_returned.emit(camp_id)
