class_name Main
extends Node3D
## 主场景控制器（docs/technical-design.md §4.1）。
##
## 负责装配存档提供者、加载任务定义，并把 M0/M1 的灰盒链路串起来。

const QUEST_CAMP_COMM := "res://resources/quests/camp_comm_radio.tres"

## 物品定义（docs/game-design.md §6.2：工具 / 消耗品 / 资源 / 线索）。
const ITEM_DEFINITIONS := [
	"res://resources/items/map.tres",
	"res://resources/items/compass.tres",
	"res://resources/items/flashlight.tres",
	"res://resources/items/bow.tres",
	"res://resources/items/fuse.tres",
	"res://resources/items/arrow.tres",
	"res://resources/items/first_aid.tres",
	"res://resources/items/ration.tres",
]

## 出发时携带的装备：一张弓和若干箭矢。
const STARTING_GEAR := {
	&"bow": 1,
	&"arrow": 12,
	&"flashlight": 1,
}

@onready var player: Player = $Player as Player
@onready var inventory: Inventory = $Player/Inventory as Inventory
@onready var quest_manager: QuestManager = $QuestManager as QuestManager
@onready var world_manager: WorldManager = $WorldManager as WorldManager
@onready var spawn_manager: SpawnManager = $SpawnManager as SpawnManager


func _ready() -> void:
	_register_save_handlers()
	_load_items()
	_grant_starting_gear()
	_load_quests()
	_place_player_at_spawn()
	GameLog.info("Main 就绪", {
		"scene": get_tree().current_scene.scene_file_path if get_tree().current_scene else "",
		"player": player.global_position if player else Vector3.ZERO,
	})


## 离树时注销存档回调。
##
## SaveManager 是常驻 autoload，它持有的 Callable 指向本节点。
## 不注销的话，本节点先被释放、autoload 后释放，Godot 关闭阶段
## 解析这些悬空 Callable 会触发访问冲突（测试退出码偶发 0xC0000005）。
func _exit_tree() -> void:
	if SaveManager == null:
		return
	for key in ["current_scene", "player", "inventory", "world"]:
		SaveManager.unregister(key)


## 发放初始装备。读档时会用存档里的背包覆盖，不重复发放。
func _grant_starting_gear() -> void:
	if inventory == null:
		return
	for item_id: StringName in STARTING_GEAR:
		var amount: int = STARTING_GEAR[item_id]
		if amount > 0:
			inventory.add_item(item_id, amount)


## 把玩家放到世界出生点并贴到地面，避免出生时悬空坠落。
## 读档会覆盖该位置（Player.from_dict），因此两者不冲突。
func _place_player_at_spawn() -> void:
	if player == null or spawn_manager == null:
		return
	if spawn_manager.get_spawn() == null:
		GameLog.warn("当前世界没有出生点，玩家保留场景中的初始位置")
		return
	spawn_manager.respawn_player(player)


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
	var payload: Variant = data.get("inventory", {})
	if payload is Dictionary:
		inventory.from_dict(payload)
	elif payload is Array:
		# 兼容早期把槽位直接写成数组的存档
		inventory.from_dict({"slots": payload})
	else:
		GameLog.warn("存档中的背包数据格式无法识别", {"type": typeof(payload)})


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


# ------------------------------------------------------------------ 物品

func _load_items() -> void:
	if inventory == null:
		return
	var loaded := 0
	for path in ITEM_DEFINITIONS:
		if not ResourceLoader.exists(path):
			GameLog.warn("物品资源不存在", {"path": path})
			continue
		var definition := load(path) as ItemDefinition
		if definition == null:
			GameLog.error("物品资源类型不正确", {"path": path})
			continue
		inventory.register_definition(definition)
		loaded += 1
	GameLog.info("物品定义已加载", {"count": loaded})


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
