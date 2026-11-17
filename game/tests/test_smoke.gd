extends Node
## 无头冒烟测试（docs/development-plan.md M0 / M1）。
##
## 运行：godot --headless --path game res://tests/test_smoke.tscn
##
## 覆盖：autoload 注册、输入映射、任务推进、背包、存档写读与迁移。

const REQUIRED_ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right",
	"sprint", "crouch", "jump", "interact", "flashlight",
	"inventory", "map", "compass", "pause", "quick_save", "quick_load",
]

const REQUIRED_SAVE_KEYS := [
	"save_version", "current_scene", "player_transform", "player_state",
	"inventory", "quest_states", "world_flags", "changed_objects", "time_and_weather",
]

var _checks: int = 0
var _failures: Array[String] = []
var _main: Node
var _player: Player
var _inventory: Inventory
var _quest_manager: QuestManager


func _ready() -> void:
	await get_tree().process_frame

	_main = get_node_or_null("Main")
	if _main == null:
		_fail("主场景未实例化")
		_finish()
		return

	_player = _main.get("player")
	_inventory = _main.get("inventory")
	_quest_manager = _main.get("quest_manager")

	_test_autoloads()
	_test_input_map()
	_test_mouse_capture()
	await _test_player_grounding()
	_test_quest_definition()
	_test_quest_chain()
	_test_inventory()
	await _test_enemy_perception()
	await _test_combat()
	_test_save_keys()
	_test_save_load_round_trip()
	_test_migration()
	_test_backup()

	_finish()


# ------------------------------------------------------------------ 检查项

func _test_autoloads() -> void:
	_assert(get_node_or_null("/root/EventBus") != null, "EventBus 已注册")
	_assert(get_node_or_null("/root/GameState") != null, "GameState 已注册")
	_assert(get_node_or_null("/root/SettingsManager") != null, "SettingsManager 已注册")
	_assert(get_node_or_null("/root/SaveManager") != null, "SaveManager 已注册")


func _test_input_map() -> void:
	for action in REQUIRED_ACTIONS:
		_assert(InputMap.has_action(action), "输入动作存在：%s" % action)
		if InputMap.has_action(action):
			_assert(InputMap.action_get_events(action).size() > 0, "输入动作已绑定事件：%s" % action)


## 鼠标不应该在启动时被夺走；Esc 必须能归还鼠标。
func _test_mouse_capture() -> void:
	_assert(not _player.is_mouse_captured(), "启动时鼠标未被捕获")

	_player.capture_mouse()
	_assert(_player.is_mouse_captured(), "调用 capture_mouse 后鼠标已捕获")

	_player.handle_escape()
	_assert(not _player.is_mouse_captured(), "Esc 后鼠标已释放")

	_player.capture_mouse()
	_player.release_mouse()
	_assert(not _player.is_mouse_captured(), "调用 release_mouse 后鼠标已释放")


## 玩家必须站在程序化地形上。
## 这条断言是「地形碰撞面绕向写反 → 角色直接穿地下落」的回归防护。
func _test_player_grounding() -> void:
	for i in 30:
		await get_tree().physics_frame

	_assert(_player.is_on_floor(), "玩家站在地面上（is_on_floor）")
	_assert(_player.state_machine.current_state == PlayerStateMachine.State.GROUNDED,
		"玩家状态为 Grounded（实际 %s）" % _player.state_machine.state_name(_player.state_machine.current_state))
	_assert(is_equal_approx(_player.health, _player.tuning.max_health),
		"出生没有跌落伤害（当前生命 %f）" % _player.health)

	var terrain := get_tree().get_first_node_in_group(&"terrain") as ProcTerrain
	_assert(terrain != null, "地形已注册到 terrain 分组")
	if terrain != null:
		var ground := terrain.height_at(_player.global_position.x, _player.global_position.z)
		_assert(absf(_player.global_position.y - ground) < 1.0,
			"玩家高度贴近地面（y=%.2f 地面=%.2f）" % [_player.global_position.y, ground])


func _test_quest_definition() -> void:
	var definition := _quest_manager.get_definition(&"camp_comm_radio")
	_assert(definition != null, "任务定义已注册")
	if definition == null:
		return
	_assert(definition.stages.size() == 3, "任务阶段数为 3（实际 %d）" % definition.stages.size())
	_assert(_quest_manager.get_active_quests().has(&"camp_comm_radio"), "任务已自动开始")
	_assert(not _quest_manager.is_quest_completed(&"camp_comm_radio"), "任务初始未处于完成状态")


## 端到端驱动 M1 灰盒链路：拾取保险丝 → 修复无线电 → 返回营火。
func _test_quest_chain() -> void:
	var crate := _find_interactable(&"supply_crate")
	var radio := _find_interactable(&"camp_radio")
	var campfire := _find_interactable(&"campfire")
	_assert(crate != null, "物资箱已找到")
	_assert(radio != null, "无线电已找到")
	_assert(campfire != null, "营火已找到")
	if crate == null or radio == null or campfire == null:
		return

	var state := _quest_manager.get_state(&"camp_comm_radio")
	_assert(state.current_stage == 0, "初始阶段为 0（实际 %d）" % state.current_stage)

	# 第一步：拾取保险丝
	crate.interact(_player)
	_assert(_inventory.has_item(&"fuse"), "保险丝已进入背包")
	_assert(state.current_stage == 1, "拾取后阶段为 1（实际 %d）" % state.current_stage)

	# 第二步：修复无线电（消耗保险丝）
	radio.interact(_player)
	_assert(not _inventory.has_item(&"fuse"), "修复后保险丝已被消耗")
	_assert(state.current_stage == 2, "修复后阶段为 2（实际 %d）" % state.current_stage)

	# 第三步：返回营火
	campfire.interact(_player)
	_assert(_quest_manager.is_quest_completed(&"camp_comm_radio"), "返回营火后任务已完成")
	_assert(state.is_completed, "任务状态已标记完成")


func _test_inventory() -> void:
	_assert(_inventory.count_item(&"fuse") == 0, "修复后背包已无保险丝")

	var before := _inventory.count_item(&"arrow")
	_inventory.add_item(&"arrow", 5)
	_assert(_inventory.count_item(&"arrow") == before + 5, "物品数量已增加")
	_assert(_inventory.remove_item(&"arrow", 2), "物品已移除")
	_assert(_inventory.count_item(&"arrow") == before + 3, "移除物品数量正确")
	_assert(not _inventory.remove_item(&"arrow", 999), "数量不足时移除被正确拒绝")


func _test_save_keys() -> void:
	_assert(SaveManager.save_game(0), "存档写入成功")

	var path := "user://saves/slot_0.json"
	_assert(FileAccess.file_exists(path), "存档文件已生成")

	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	_assert(parsed is Dictionary, "存档为合法 JSON")
	if not (parsed is Dictionary):
		return

	var data: Dictionary = parsed
	for key in REQUIRED_SAVE_KEYS:
		_assert(data.has(key), "存档含必需字段：%s" % key)
	_assert(int(data.get("save_version", 0)) == SaveManager.SAVE_VERSION, "存档版本号正确")


func _test_save_load_round_trip() -> void:
	# 存档后破坏状态，再读档验证恢复
	_inventory.add_item(&"test_marker", 3)
	GameState.set_flag(&"test_flag", true)
	SaveManager.save_game(0)

	_inventory.remove_item(&"test_marker", 3)
	GameState.set_flag(&"test_flag", false)
	_assert(not _inventory.has_item(&"test_marker"), "破坏状态成功：物品已从背包移除")
	_assert(not GameState.get_flag(&"test_flag"), "破坏状态成功：标记已置假")

	_assert(SaveManager.load_game(0), "读档成功")
	_assert(_inventory.has_item(&"test_marker"), "读档后物品已恢复")
	_assert(GameState.get_flag(&"test_flag"), "读档后世界标记已恢复")
	_assert(_quest_manager.is_quest_completed(&"camp_comm_radio"), "读档后任务完成状态已恢复")

	# 对象状态也应恢复：已拾取的物资箱应保持隐藏
	var crate := _find_interactable(&"supply_crate")
	if crate != null:
		_assert(not crate.can_interact(_player), "读档后已拾取的物资箱不可交互")


func _test_migration() -> void:
	# 构造一个 v0 存档（缺少 v1 引入的字段），验证迁移路径
	var legacy := {
		"format": "forest_adventure_save",
		"save_version": 0,
		"player_transform": {"position": [1.0, 2.0, 3.0]},
	}
	var dir := DirAccess.open("user://saves")
	_assert(dir != null, "存档目录可打开")
	if dir == null:
		return
	var file := FileAccess.open("user://saves/slot_2.json", FileAccess.WRITE)
	_assert(file != null, "迁移测试存档已写入")
	if file == null:
		return
	file.store_string(JSON.stringify(legacy))
	file.close()

	_assert(SaveManager.load_game(2), "v0 存档迁移后加载成功")

	var text := FileAccess.get_file_as_string("user://saves/slot_2.json")
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_assert(int((parsed as Dictionary).get("save_version", 0)) == SaveManager.SAVE_VERSION,
			"迁移后版本号已提升")


func _test_backup() -> void:
	SaveManager.save_game(0)
	SaveManager.save_game(0)
	_assert(FileAccess.file_exists("user://saves/slot_0.json.bak"), "已生成上一版本备份")
	_assert(not FileAccess.file_exists("user://saves/slot_0.json.tmp"), "临时文件已清理")


## 战斗闭环：装备 → 射箭 → 命中 → 敌人受伤死亡 → 掉落 → 拾取。
func _test_combat() -> void:
	_assert(_inventory.has_item(&"bow"), "出发时带着弓")
	_assert(_inventory.count_item(&"arrow") >= 10, "出发时带着箭矢（实际 %d）" % _inventory.count_item(&"arrow"))

	# 真实发射路径：箭必须按世界坐标落在射手手边。
	# 这里把主场景整体横移 5m：如果箭是按父节点的局部坐标定位的，
	# 它会跟着偏移 5m（父节点在原点时看不出来，所以普通断言抓不到）。
	var main_node := _main as Node3D
	var origin_backup := Vector3.ZERO
	if main_node != null:
		origin_backup = main_node.position
		main_node.position = Vector3(5.0, 0.0, 0.0)
		await get_tree().process_frame

	var bow := _player.get_node_or_null("Bow") as Bow
	_assert(bow != null, "玩家身上挂着弓节点")
	if bow != null:
		var camera := _player.get_node_or_null("Head/Camera3D") as Camera3D
		bow.spawn_arrow(1.0)
		await get_tree().process_frame
		var spawned := _find_arrow()
		_assert(spawned != null, "弓能生成箭矢实体")
		if spawned != null and camera != null:
			var forward := -camera.global_transform.basis.z
			var muzzle := camera.global_position + forward * 0.6 - camera.global_transform.basis.y * 0.15
			var offset := spawned.global_position.distance_to(muzzle)
			_assert(offset < 0.2, "箭矢按世界坐标落在射手手边（偏差 %.2f m）" % offset)
			_assert(spawned.velocity.length() > 0.0, "箭矢带有飞行速度")
			spawned.queue_free()

	if main_node != null:
		main_node.position = origin_backup
		await get_tree().process_frame

	var wolf := _find_enemy(&"wolf_01")
	_assert(wolf != null, "场景里有林狼")
	if wolf == null:
		return

	# 冻结林狼，保证命中判定可复现
	wolf.set_physics_process(false)
	var health_before := wolf.get_health()

	# 从林狼正前方射一支箭
	var target_point: Vector3 = wolf.global_position + Vector3(0.0, 0.45, 0.0)
	var start_point: Vector3 = target_point + Vector3(0.0, 0.0, -4.0)
	var arrow := ArrowProjectile.new()
	add_child(arrow)
	arrow.global_position = start_point
	arrow.launch((target_point - start_point).normalized(), 1.0)

	for i in 40:
		await get_tree().physics_frame

	_assert(wolf.get_health() < health_before,
		"箭矢命中林狼造成伤害（%.0f → %.0f）" % [health_before, wolf.get_health()])
	_assert(is_equal_approx(wolf.get_health(), health_before - arrow.damage),
		"普通伤害按弓的基础伤害结算")

	# 弱点判定：命中点高于阈值算弱点，伤害翻倍
	var weak_point: Vector3 = wolf.global_position + Vector3(0.0, wolf.weak_point_height + 0.1, 0.0)
	_assert(wolf.is_weak_point(weak_point), "头部高度判定为弱点")
	_assert(not wolf.is_weak_point(wolf.global_position + Vector3(0.0, 0.2, 0.0)),
		"腿部高度不算弱点")

	# 击杀并检查掉落
	var health_now := wolf.get_health()
	wolf.apply_damage(health_now + 10.0)
	_assert(not wolf.is_alive(), "林狼被击杀")
	await get_tree().process_frame

	var drop := _find_drop(&"arrow")
	_assert(drop != null, "林狼死亡掉落箭矢")
	if drop != null:
		var arrows_before := _inventory.count_item(&"arrow")
		drop.interact(_player)
		_assert(_inventory.count_item(&"arrow") > arrows_before, "掉落物可以被拾取")
		_assert(not drop.can_interact(_player), "拾取后掉落物不再可交互")


## 敌人感知：玩家靠近后，林狼应从巡逻转入警戒或追逐。
func _test_enemy_perception() -> void:
	var wolf := _find_enemy(&"wolf_01")
	if wolf == null:
		return

	wolf.set_physics_process(true)
	var start_state := wolf.state

	# 把玩家挪到林狼面前
	_player.global_position = wolf.global_position + Vector3(0.0, 0.0, -3.0)
	for i in 30:
		await get_tree().physics_frame

	_assert(wolf.state != start_state or wolf.is_threatening(),
		"林狼发现靠近的玩家（状态 %s）" % wolf.state_name_text())
	_player.global_position = Vector3(0.0, 0.05, 7.5)
	_player.heal(_player.tuning.max_health)


# ------------------------------------------------------------------ 工具

func _find_interactable(object_id: StringName) -> Node:
	for node in get_tree().get_nodes_in_group(&"interactable"):
		var interactable := node as Interactable
		if interactable != null and interactable.stable_id == object_id:
			return interactable
	return null


## 按稳定 ID 找敌人。
func _find_enemy(enemy_id: StringName) -> EnemyBase:
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as EnemyBase
		if enemy != null and enemy.stable_id == enemy_id:
			return enemy
	return null


## 找掉落物。
func _find_drop(item_id: StringName) -> PickupInteractable:
	for node in get_tree().get_nodes_in_group(&"interactable"):
		var pickup := node as PickupInteractable
		if pickup != null and pickup.item_id == item_id:
			return pickup
	return null


## 找玩家身边刚生成的箭矢。
func _find_arrow() -> ArrowProjectile:
	var parent := _player.get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is ArrowProjectile:
			return child as ArrowProjectile
	return null


func _assert(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL  %s" % message)


func _fail(message: String) -> void:
	_checks += 1
	_failures.append(message)
	push_error("  FAIL  %s" % message)


func _finish() -> void:
	print("")
	print("── 冒烟测试结果 ──")
	print("检查项：%d    失败：%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("结果：全部通过")
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("  - %s" % failure)
		print("结果：存在失败项")
		get_tree().quit(1)
