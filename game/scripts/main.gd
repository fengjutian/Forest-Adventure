class_name Main
extends Node3D
## 主场景控制器（docs/technical-design.md §4.1）。
##
## 负责装配存档提供者、加载任务定义，并把 M0/M1 的灰盒链路串起来。

const QUEST_CAMP_COMM := "res://resources/quests/camp_comm_radio.tres"

@onready var player: Player = $Player as Player
@onready var inventory: Inventory = $Player/Inventory as Inventory
@onready var quest_manager: QuestManager = $QuestManager as QuestManager
@onready var world_manager: WorldManager = $WorldManager as WorldManager
@onready var spawn_manager: SpawnManager = $SpawnManager as SpawnManager


func _ready() -> void:
	_register_save_handlers()
	_load_quests()
	GameLog.info("Main 就绪", {
		"scene": get_tree().current_scene.scene_file_path if get_tree().current_scene else "",
		"player": player.global_position if player else Vector3.ZERO,
	})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save"):
		SaveManager.save_game(SaveManager.DEFAULT_SLOT)
	elif event.is_action_pressed("quick_load"):
		SaveManager.load_game(SaveManager.DEFAULT_SLOT)


# ------------------------------------------------------------------ 存档装配

func _register_save_handlers() -> void:
	SaveManager.register_provider("current_scene", Callable(self, "_provide_current_scene"))
	SaveManager.register_provider("player", Callable(self, "_provide_player"))
	SaveManager.register_provider("inventory", Callable(self, "_provide_inventory"))
	SaveManager.register_provider("world", Callable(self, "_provide_world"))

	SaveManager.register_loader("player", Callable(self, "_load_player"))
	SaveManager.register_loader("inventory", Callable(self, "_load_inventory"))
	SaveManager.register_loader("world", Callable(self, "_load_world"))


func _provide_current_scene() -> Dictionary:
	var scene_path := ""
	var current := get_tree().current_scene
	if current != null:
		scene_path = current.scene_file_path
	return {"current_scene": scene_path}


func _provide_player() -> Dictionary:
	if player == null:
		return {}
	return player.to_dict()


func _provide_inventory() -> Dictionary:
	if inventory == null:
		return {}
	return {"inventory": inventory.to_dict()}


func _provide_world() -> Dictionary:
	return GameState.to_dict()


func _load_player(data: Dictionary) -> void:
	if player != null:
		player.from_dict(data)


func _load_inventory(data: Dictionary) -> void:
	if inventory == null:
		return
	var payload: Dictionary = data.get("inventory", {})
	inventory.from_dict(payload)


func _load_world(data: Dictionary) -> void:
	GameState.from_dict(data)
	_apply_changed_objects(GameState.changed_objects)


## 把存档中的对象状态还原到场景里对应的可交互对象。
func _apply_changed_objects(changed: Dictionary) -> void:
	if changed.is_empty():
		return
	for node in get_tree().get_nodes_in_group(&"interactable"):
		var interactable := node as Interactable
		if interactable == null:
			continue
		var object_id := interactable.stable_id
		if object_id != &"" and changed.has(object_id):
			interactable.apply_persistent_state(changed[object_id])
			GameLog.info("对象状态已恢复", {"object": object_id})


# ------------------------------------------------------------------ 任务

func _load_quests() -> void:
	if not ResourceLoader.exists(QUEST_CAMP_COMM):
		GameLog.error("任务资源不存在", {"path": QUEST_CAMP_COMM})
		return

	var definition := load(QUEST_CAMP_COMM) as QuestDefinition
	if definition == null:
		GameLog.error("任务资源类型不正确", {"path": QUEST_CAMP_COMM})
		return

	quest_manager.register_quest(definition)
	GameLog.info("任务已加载", {"quest": definition.id, "stages": definition.stages.size()})
