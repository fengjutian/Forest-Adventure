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
	"aim", "fire", "toggle_help",
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
	await _test_chunked_world()
	await _test_first_person_motion()
	_test_hud_key_hints()
	_test_quest_definition()
	_test_quest_chain()
	_test_inventory()
	await _test_enemy_perception()
	await _test_combat()
	await _test_arrows()
	_test_save_keys()
	_test_save_load_round_trip()
	_test_migration()
	_test_backup()
	await _test_m2_content()

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

	var terrain := get_tree().get_first_node_in_group(&"terrain") as Node3D
	_assert(terrain != null, "地形已注册到 terrain 分组")
	if terrain != null:
		var ground := float(terrain.call("height_at", _player.global_position.x, _player.global_position.z))
		_assert(absf(_player.global_position.y - ground) < 1.0,
			"玩家高度贴近地面（y=%.2f 地面=%.2f）" % [_player.global_position.y, ground])


## 分块世界：1 km 范围、跨块无缝、流式加载、可重复生成（docs/open-world-design.md §1）。
func _test_chunked_world() -> void:
	var world := _find_world()
	_assert(world != null, "分块世界已加载")
	if world == null:
		return

	_assert(is_equal_approx(world.world_size, 1024.0), "世界边长 1 km（实际 %.0f）" % world.world_size)
	_assert(is_equal_approx(world.chunk_size, 64.0), "区块边长 64 m（实际 %.0f）" % world.chunk_size)
	_assert(world.loaded_chunk_count() > 0, "启动即加载了出生点附近的区块")
	var chunk_bound := (2 * world.terrain_radius_chunks + 1) * (2 * world.terrain_radius_chunks + 1)
	_assert(world.loaded_chunk_count() <= chunk_bound,
		"同时存在的区块数有上界（%d / %d）" % [world.loaded_chunk_count(), chunk_bound])

	_assert(absf(world.height_at(0.0, 0.0)) < 0.05,
		"营地中心被压平（高度 %.3f）" % world.height_at(0.0, 0.0))
	_assert(world.height_at(11.0, 40.0) < -1.0,
		"溪谷贯穿营地之外（河床 %.2f）" % world.height_at(11.0, 40.0))

	# 跨块连续：边界两侧的场值必须几乎相等
	var max_jump := 0.0
	for z in [-200.0, -64.0, 0.0, 16.0, 64.0, 200.0]:
		max_jump = maxf(max_jump, absf(world.height_at(-0.01, z) - world.height_at(0.01, z)))
	_assert(max_jump < 0.1, "高度场跨区块边界连续（最大跳变 %.3f m）" % max_jump)

	# 网格接缝：相邻两块在共享边界上的顶点高度必须完全一致
	var camp_coord := world.world_to_chunk(Vector3(0.0, 0.0, 8.0))
	_assert(camp_coord == Vector2i(8, 8), "营地所在区块为 (8,8)（实际 %s）" % camp_coord)
	var camp := world.get_chunk(camp_coord)
	var west := world.get_chunk(Vector2i(7, 8))
	_assert(camp != null and west != null, "营地与西侧相邻区块都已加载")
	if camp == null or west == null:
		return

	var camp_edge := _mesh_height(camp, 0.0, 16.0)
	var west_edge := _mesh_height(west, world.chunk_size, 16.0)
	_assert(absf(camp_edge - world.height_at(0.0, 16.0)) < 0.01,
		"区块网格顶点取自同一高度场（%.3f）" % camp_edge)
	_assert(is_equal_approx(camp_edge, west_edge),
		"相邻区块共享边界高度一致（%.3f / %.3f）" % [camp_edge, west_edge])

	# 确定性：同一块重建后植被逐实例一致
	var signature := camp.signature()
	_assert(not signature.is_empty(), "营地区块有植被")
	world.rebuild_chunk(camp_coord)
	var rebuilt := world.get_chunk(camp_coord)
	_assert(rebuilt != null, "区块可以立即重建")
	if rebuilt != null:
		_assert(signature == rebuilt.signature(), "同一区块重建后植被逐实例一致")

	# 流式加载：走远后远端区块卸载、脚下加载。
	# 先把敌人冻住，免得它们追着瞬移的玩家跑出营地，影响后续感知测试。
	var enemies := get_tree().get_nodes_in_group(&"enemy")
	for enemy in enemies:
		(enemy as Node).set_physics_process(false)

	var remote_coord := Vector2i(1, 1)
	# 流式加载是逐帧铺开的：等远端区块被队列轮到
	for i in 300:
		if world.is_chunk_loaded(remote_coord):
			break
		await get_tree().process_frame
	_assert(world.is_chunk_loaded(remote_coord), "远端区块在出生点的流式半径内已加载")

	var saved_position := _player.global_position
	_player.set_physics_process(false)
	_player.global_position = Vector3(460.0, world.height_at(460.0, 460.0) + 2.0, 460.0)
	for i in 240:
		await get_tree().process_frame

	var far_coord := world.world_to_chunk(_player.global_position)
	_assert(world.is_chunk_loaded(far_coord), "远处脚下的区块已流式加载")
	_assert(not world.is_chunk_loaded(remote_coord), "远离后远端区块已卸载")
	_assert(world.loaded_chunk_count() <= chunk_bound, "流式加载后区块数仍有界")

	# 回到营地。
	#
	# 这里不能「瞬移回去就立刻开物理」：远行时营地所在的区块已经被卸载，
	# 碰撞还没重建，玩家会在虚空里一路加速下落（实测 ——53 m/s），
	# 之后所有依赖「站在地上」的断言都会连带失败（走路镜头起伏、感知距离……）。
	# 先把区块等回来、把玩家贴回地面，再开物理。
	_player.global_position = saved_position
	for i in 600:
		if world.is_chunk_loaded(camp_coord):
			break
		await get_tree().process_frame
	_assert(world.is_chunk_loaded(camp_coord), "回到营地后区块重新加载")

	# 区块标记为已加载不等于碰撞已经进物理空间，多给几帧再落地
	for i in 8:
		await get_tree().process_frame
	_player.global_position = Vector3(
		saved_position.x,
		world.height_at(saved_position.x, saved_position.z) + 0.05,
		saved_position.z)
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(true)
	for i in 120:
		if _player.is_on_floor():
			break
		await get_tree().physics_frame
	_assert(_player.is_on_floor(), "回到营地后玩家重新站到地面")

	for enemy in enemies:
		(enemy as Node).set_physics_process(true)


## 第一人称表现：手、手臂、拉弦与走路起伏必须真的在动，而不是一把浮空的弓。
func _test_first_person_motion() -> void:
	var bow := _player.get_node_or_null("Bow") as Bow
	_assert(bow != null, "玩家身上挂着弓节点（第一人称表现）")
	if bow == null:
		return

	var camera := _player.camera
	_assert(camera != null, "玩家有第一人称相机")
	if camera == null:
		return
	var view := camera.get_node_or_null("BowViewModel") as Node3D
	_assert(view != null, "第一人称持弓挂在相机下")
	if view == null:
		return
	var pivot := view.get_node_or_null("BowPivot") as Node3D
	_assert(pivot != null, "弓有单独的抬放枢轴")
	if pivot == null:
		return
	# 手挂在弓身上，和弓共用缩放：缩小后的弓配真人尺寸的手会立刻穿帮
	var left_hand := pivot.get_node_or_null("LeftHand") as Node3D
	var right_hand := pivot.get_node_or_null("RightHand") as Node3D
	_assert(left_hand != null and right_hand != null, "有左手和右手（挂在弓身上）")
	_assert(view.get_node_or_null("BowPivot/StringTop") != null
		and view.get_node_or_null("BowPivot/StringBottom") != null, "弓弦是两段可拉开的折线")
	if right_hand == null:
		return

	# 蓄力时右手必须把弦往后拉（而不是一只静态的手）。
	# 用 charge 而不是帧数等待：无头模式帧率不稳定，按帧等会等不够。
	_player.capture_mouse()
	Input.action_press("aim")
	for i in 3:
		await get_tree().process_frame
	var rest := right_hand.position
	Input.action_press("fire")
	var guard := 0
	while bow.get_charge() < 0.5 and guard < 900:
		await get_tree().process_frame
		guard += 1
	var drawn := right_hand.position
	Input.action_release("fire")
	Input.action_release("aim")
	_player.release_mouse()
	_assert(drawn.distance_to(rest) > 0.003,
		"蓄力时右手把弦拉开（位移 %.3f）" % drawn.distance_to(rest))
	_assert(drawn.z > rest.z, "拉弦方向朝向后（弦心后移）")

	# 蓄到一半松手会真的射出一支箭：等它生成后清掉，别干扰后面的射击断言
	await get_tree().process_frame
	await get_tree().process_frame
	var arrow_parent := _player.get_parent()
	if arrow_parent != null:
		for child in arrow_parent.get_children():
			if child is ArrowProjectile:
				child.queue_free()
	await get_tree().process_frame

	# 走起来镜头要有起伏；站定时回到静止位置
	Input.action_press("move_forward")
	var max_offset := 0.0
	for i in 40:
		await get_tree().process_frame
		max_offset = maxf(max_offset, camera.position.length())
	Input.action_release("move_forward")
	_assert(max_offset > 0.002, "走路时镜头有起伏（峰值 %.3f m）" % max_offset)


## HUD 按键提示：面板、H 开关、交互提示带按键。
func _test_hud_key_hints() -> void:
	var hud := _main.get_node_or_null("UI") as HUD
	_assert(hud != null, "HUD 已实例化")
	if hud == null:
		return
	var hint := hud.get_node_or_null("ControlsHint")
	_assert(hint != null, "HUD 有按键提示层")
	if hint == null:
		return
	var panel := hint.get_node_or_null("ControlsPanel") as Control
	_assert(panel != null, "按键提示面板已创建")
	if panel == null:
		return
	_assert(panel.visible, "进游戏先自动显示按键提示")

	var toggle := hint.get_node_or_null("ToggleHint") as Control
	hud.toggle_controls_hint()
	_assert(not panel.visible, "H 可以收起按键提示")
	_assert(toggle != null and toggle.visible, "收起后角落保留 H 角标")
	hud.toggle_controls_hint()
	_assert(panel.visible, "再按 H 能重新打开按键提示")

	# 交互提示要带当前按键：拾取时显示「[E] 拾取」
	var crate := _find_interactable(&"supply_crate")
	_assert(crate != null, "找到可交互的物资箱（按键提示测试）")
	if crate == null:
		return
	EventBus.interaction_target_changed.emit(crate)
	var prompt := (hud.get_node("InteractionPrompt") as Label).text
	_assert(prompt.begins_with("[") and prompt.contains("]"), "交互提示带按键前缀（%s）" % prompt)
	EventBus.interaction_target_changed.emit(null)


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

	# 用 anomaly_core 做纯背包操作测试：
	# 箭矢已经无限供应，不再作为背包里的常规物品出现。
	var before := _inventory.count_item(&"anomaly_core")
	_inventory.add_item(&"anomaly_core", 3)
	_assert(_inventory.count_item(&"anomaly_core") == before + 3, "物品数量已增加")
	_assert(_inventory.remove_item(&"anomaly_core", 2), "物品已移除")
	_assert(_inventory.count_item(&"anomaly_core") == before + 1, "移除物品数量正确")
	_assert(not _inventory.remove_item(&"anomaly_core", 999), "数量不足时移除被正确拒绝")


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

	# 分块世界：种子与改动区块必须进存档，否则换机器读档会生成另一张地图
	var chunked: Dictionary = data.get("chunked_world", {})
	_assert(not chunked.is_empty(), "存档含 chunked_world 字段")
	var world := _find_world()
	if world != null:
		_assert(int(chunked.get("seed", 0)) == world.field.world_seed,
			"存档记录世界种子（%d）" % int(chunked.get("seed", 0)))
		_assert(chunked.get("modifications", null) is Dictionary, "存档记录区块改动表")


func _test_save_load_round_trip() -> void:
	# 存档后破坏状态，再读档验证恢复
	_inventory.add_item(&"test_marker", 3)
	GameState.set_flag(&"test_flag", true)
	var world := _find_world()
	var modified_coord := Vector2i(9, 9)
	if world != null:
		world.mark_chunk_modified(modified_coord, {"no_vegetation": true})
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

	# 区块改动应恢复：存档里被清空植被的区块，读档后重建仍是空的
	_assert(GameState.get_chunk_modification(modified_coord).get("no_vegetation", false),
		"读档后区块改动已恢复")
	if world != null:
		var chunk := world.get_chunk(modified_coord)
		_assert(chunk != null and chunk.instance_count() == 0,
			"读档后被改动区块按存档重建（植被实例 %d）" % (chunk.instance_count() if chunk != null else -1))


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
	_assert(_inventory.count_item(&"arrow") == 0, "出发时不携带箭矢（无限供应）")

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
		var fired := bow.spawn_arrow(1.0)
		# 生成后立刻取位置：箭速 42 m/s，等一帧就已经飞出去 0.7 m 了
		var spawned := fired if fired != null else _find_arrow()
		_assert(spawned != null, "弓能生成箭矢实体")
		if spawned != null and camera != null:
			var forward := -camera.global_transform.basis.z
			var to_arrow := spawned.global_position - camera.global_position
			# 出膛点是弦心（约 1.2 m 外），不是屏幕中央；主场景横移 5 m 后
			# 如果这里算出来还是 5 m 左右，说明箭是按父节点局部坐标定位的。
			_assert(to_arrow.length() < 1.8,
				"箭矢出膛点在射手手边（离相机 %.2f m）" % to_arrow.length())
			_assert(to_arrow.dot(forward) > 0.5,
				"箭矢出膛点在射手前方（前方投影 %.2f m）" % to_arrow.dot(forward))
			var nocked := camera.get_node_or_null("BowViewModel/NockedArrow") as Node3D
			if nocked != null:
				var nock_gap := spawned.global_position.distance_to(nocked.global_position)
				_assert(nock_gap < 0.3, "箭从弦上射出（距弦心 %.2f m）" % nock_gap)
			_assert(spawned.velocity.length() > 0.0, "箭矢带有飞行速度")

			# 箭矢网格的箭头必须朝 -Z，才能用 look_at 对齐飞行方向
			var mesh := spawned.get_node_or_null("ArrowMesh") as MeshInstance3D
			_assert(mesh != null, "箭矢带网格")
			if mesh != null and mesh.mesh != null:
				var bounds := mesh.mesh.get_aabb()
				_assert(bounds.size.z > bounds.size.x,
					"箭矢网格朝向 -Z（Z 边 %.2f > X 边 %.2f）" % [bounds.size.z, bounds.size.x])
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

	# 从林狼正面射一支箭。
	#
	# 起点不能随便取：箭是逐帧射线检测，撞上地形就停在半路，
	# 林狼一滴血都不会掉。林狼会到处走，4 米外的地面高低会跟着变，
	# 固定朝一个方向射，这一项测试就是靠运气——实测十轮里会偶发失败。
	# 所以沿八个方向采样地形高度，挑一条地面低于胸口的弹道。
	var target_point: Vector3 = wolf.global_position + Vector3(0.0, 0.45, 0.0)
	var route := _clear_shot_route(wolf.global_position, target_point.y)
	var shot_dir: Vector3 = route[0]
	var shot_distance: float = route[1]
	var start_point: Vector3 = target_point + shot_dir * shot_distance
	var arrow := ArrowProjectile.new()
	add_child(arrow)
	arrow.global_position = start_point
	arrow.launch((target_point - start_point).normalized(), 1.0)

	for i in 40:
		await get_tree().physics_frame

	_assert(wolf.get_health() < health_before,
		"箭矢命中林狼造成伤害（%.0f → %.0f；起点 %s，方向 %s，距离 %.1f m）" % [
			health_before, wolf.get_health(), str(start_point.round()), str(shot_dir.round()), shot_distance
		])
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

	var drop := _find_drop(&"ration")
	_assert(drop != null, "林狼死亡掉落口粮")
	if drop != null:
		var food_before := _inventory.count_item(&"ration")
		drop.interact(_player)
		_assert(_inventory.count_item(&"ration") > food_before, "掉落物可以被拾取")
		_assert(not drop.can_interact(_player), "拾取后掉落物不再可交互")


## 箭矢无限供应与永久留痕（docs/archery-and-realism.md §2、§3）。
func _test_arrows() -> void:
	var player := _main.get("player") as Player
	if player == null:
		return
	var bow := player.get_node_or_null("Bow") as Bow
	var world := get_tree().get_first_node_in_group(&"terrain") as ChunkedWorld
	if bow == null or world == null or world.field == null:
		return

	# 1) 射箭不消耗任何东西
	var arrows_before := _inventory.count_item(&"arrow")
	var fired := bow.spawn_arrow(1.0)
	await get_tree().physics_frame
	_assert(_inventory.count_item(&"arrow") == arrows_before,
		"射箭不消耗箭矢（无限供应）")
	if fired != null:
		fired.queue_free()

	# 2) 命中地面后箭留在世界里，不自动消失
	var ground := world.field.height_at(6.0, 6.0)
	var arrow := ArrowProjectile.new()
	add_child(arrow)
	arrow.global_position = Vector3(6.0, ground + 3.0, 6.0)
	arrow.launch(Vector3.DOWN, 0.2)
	for i in 60:
		await get_tree().physics_frame
		if arrow.is_stuck():
			break
	_assert(arrow.is_stuck(), "箭命中地面后钉住")
	_assert(is_instance_valid(arrow) and not arrow.is_queued_for_deletion(),
		"插在地上的箭留在世界里，不会自动消失")

	# 3) 场上箭矢数量上限：超出时最早的那支消失
	var spawned: Array[ArrowProjectile] = []
	for i in ArrowProjectile.MAX_STUCK_ARROWS + 5:
		var extra := ArrowProjectile.new()
		add_child(extra)
		extra.global_position = Vector3(24.0 + float(i) * 0.25, ground + 2.0, 12.0)
		extra._stick(extra.global_position, Vector3.UP)
		spawned.append(extra)
		await get_tree().process_frame
	var stuck_count := ArrowProjectile.count_stuck(get_tree())
	_assert(stuck_count <= ArrowProjectile.MAX_STUCK_ARROWS,
		"场上插着的箭不超过上限 %d（实际 %d）" % [ArrowProjectile.MAX_STUCK_ARROWS, stuck_count])

	for extra in spawned:
		if is_instance_valid(extra):
			extra.queue_free()
	await get_tree().process_frame


## 敌人感知：玩家靠近后，林狼应从巡逻转入警戒或追逐。
func _test_enemy_perception() -> void:
	var wolf := _find_enemy(&"wolf_01")
	if wolf == null:
		return

	wolf.set_physics_process(true)
	var start_state := wolf.state

	# 把玩家挪到林狼正视方向的前方
	var facing := -wolf.global_transform.basis.z
	_player.global_position = wolf.global_position + facing * 3.0
	for i in 30:
		await get_tree().physics_frame

	_assert(wolf.state != start_state or wolf.is_threatening(),
		"林狼发现靠近的玩家（状态 %s）" % wolf.state_name_text())
	_player.global_position = Vector3(0.0, 0.05, 7.5)
	_player.heal(_player.tuning.max_health)


# ------------------------------------------------------------------ 工具

func _find_world() -> ChunkedWorld:
	return get_tree().get_first_node_in_group(&"chunked_world") as ChunkedWorld


## 挑一条不会被地形挡住的射击路线。
##
## 箭的命中判定是逐帧射线，撞上地形就停在半路，敌人一点血都不会掉。
## 林狼会走动，它身前 4 米的地面高低随之变化，固定朝一个方向射就是靠运气。
## 这里沿八个方向、五个距离采样地形高度，取「地面最高点低于胸口」的最长一条。
## 返回 [方向, 距离]。
func _clear_shot_route(origin: Vector3, chest_y: float) -> Array:
	var world := _find_world()
	if world == null:
		return [Vector3(0.0, 0.0, -1.0), 4.0]

	var distances := [4.0, 3.0, 2.0, 1.5, 1.0]
	# 兜底：八个方向都找不到干净弹道时，贴脸打——
	# 1 米内的地面基本不可能高过胸口 0.45 m
	var fallback := [Vector3(0.0, 0.0, -1.0), 1.0]
	var fallback_ridge := INF

	for i in 8:
		var dir := Vector3(sin(float(i) * PI * 0.25), 0.0, cos(float(i) * PI * 0.25))
		for distance in distances:
			if _ridge_along(world, origin, dir, distance) < chest_y - 0.12:
				return [dir, distance]
		var near_ridge := _ridge_along(world, origin, dir, 1.0)
		if near_ridge < fallback_ridge:
			fallback_ridge = near_ridge
			fallback = [dir, 1.0]

	return fallback


## 沿某个方向采样地形高度，返回这条线上的最高点。
func _ridge_along(world: ChunkedWorld, origin: Vector3, dir: Vector3, distance: float) -> float:
	var ridge := -INF
	for k in range(1, int(distance) + 1):
		var p := origin + dir * float(k)
		ridge = maxf(ridge, world.height_at(p.x, p.z))
	return ridge


## 取区块网格上某个局部坐标处的顶点高度，用来验证接缝。
func _mesh_height(chunk: WorldChunk, local_x: float, local_z: float) -> float:
	var mesh_instance := chunk.get_node_or_null("TerrainMesh") as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return NAN
	var cell := chunk.chunk_size / float(chunk.resolution)
	var i := int(round(local_x / cell))
	var j := int(round(local_z / cell))
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index := j * (chunk.resolution + 1) + i
	if index < 0 or index >= vertices.size():
		return NAN
	return vertices[index].y


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


## M2 收尾内容：异常守护者、隐藏地点、两个世界事件。
## 见 docs/vertical-slice-completion.md。
##
## 放在所有存档测试之后：这里会改 GameState 的时间、天气和事件状态，
## 也会往背包里发隐藏地点的奖励，放最后就不会污染前面的断言。
func _test_m2_content() -> void:
	await _test_guardian()
	await _test_hidden_location()
	await _test_world_events()
	_test_m2_save_fields()


## 异常守护者：与林狼的差异、弱点观察机制、掉落。
func _test_guardian() -> void:
	var guardian := _find_enemy(&"guardian_01")
	_assert(guardian != null, "场景里有异常守护者")
	if guardian == null:
		return

	# 贴地：守护者的 y 应该等于脚下的地形高度。
	#
	# 容差 0.25 m 不是随便给的：守护者守的涌泉在离营地 3 圈远，
	# 那一圈的区块还没建碰撞（碰撞只做玩家附近 2 圈），
	# 它会自由落体一小段再被 lerp 拉回，因此稳定悬在地面下约 0.1 m。
	# 玩家走近到 2 圈内、区块碰撞建好后就严丝合缝了。
	var world := get_tree().get_first_node_in_group(&"terrain") as ChunkedWorld
	if world != null and world.field != null:
		var ground := world.field.height_at(guardian.global_position.x, guardian.global_position.z)
		_assert(absf(guardian.global_position.y - ground) < 0.25,
			"守护者贴在地面上（%.2f vs %.2f @ %s）" % [
				guardian.global_position.y, ground, str(guardian.global_position.round())])

	# 与林狼的关键差异：慢、不逃、前摇长、不追远
	_assert(not guardian.can_flee, "守护者不会逃跑")
	_assert(guardian.chase_speed < 7.0,
		"守护者追不上玩家奔跑速度（%.1f < 7.0）" % guardian.chase_speed)
	_assert(guardian.attack_windup >= 1.0,
		"守护者攻击前摇明显（%.2f s）" % guardian.attack_windup)
	_assert(guardian.leash_radius <= 20.0,
		"守护者不追远（leash %.0f m）" % guardian.leash_radius)
	_assert(guardian.weak_point_requires_discovery, "守护者弱点需要被观察")
	_assert(guardian.weak_point_requires_behind, "守护者弱点在背面")

	# 林狼不受新机制影响
	var wolf := _find_enemy(&"wolf_01")
	if wolf != null:
		_assert(wolf.can_flee, "林狼仍会在血量过低时逃跑")
		_assert(not wolf.weak_point_requires_discovery, "林狼弱点不受观察机制影响")

	# 弱点：未观察时不生效
	guardian.set_physics_process(false)
	var basis := guardian.global_transform.basis
	var front := guardian.global_position - basis.z * 0.6 \
		+ Vector3(0.0, guardian.weak_point_height + 0.2, 0.0)
	var back := guardian.global_position + basis.z * 0.6 \
		+ Vector3(0.0, guardian.weak_point_height + 0.2, 0.0)

	_assert(not guardian.is_weak_point(front), "未观察时弱点不生效")
	_assert(not guardian.is_weak_point(back), "未观察时背面也不算弱点")

	# 命中 3 次普通伤害后解锁
	guardian.apply_damage(5.0, EnemyBase.DamageKind.NORMAL, front)
	_assert(not guardian.is_weak_point_unlocked(), "命中 1 次还没解锁弱点")
	guardian.apply_damage(5.0, EnemyBase.DamageKind.NORMAL, front)
	guardian.apply_damage(5.0, EnemyBase.DamageKind.NORMAL, front)
	_assert(guardian.is_weak_point_unlocked(), "命中 3 次后弱点被发现")

	# 解锁后仍要方向对：正面不算，背面才算
	_assert(not guardian.is_weak_point(front), "正面上方不是弱点（要绕到背后）")
	_assert(guardian.is_weak_point(back), "背面高位判定为弱点")

	# 掉落
	var drops_core := false
	var drops_med := false
	for drop in guardian.drops:
		var drop_id := StringName(drop.get("id", &""))
		if drop_id == &"anomaly_core":
			drops_core = true
		elif drop_id == &"first_aid":
			drops_med = true
	_assert(drops_core, "守护者掉落异常结晶")
	_assert(drops_med, "守护者掉落急救包")

	# 击败后进入死亡状态，存档键是稳定 ID
	guardian.apply_damage(9999.0, EnemyBase.DamageKind.NORMAL)
	_assert(not guardian.is_alive(), "守护者可以被打死")
	_assert(guardian.stable_id == &"guardian_01", "守护者使用稳定 ID 作存档键")


## 隐藏地点：发现流程、奖励只发一次。
func _test_hidden_location() -> void:
	var trigger := _find_location(&"ranger_camp")
	_assert(trigger != null, "场景里有猎人营地遗址")
	if trigger == null:
		return
	_assert(trigger.discoverable, "猎人营地遗址是可发现的隐藏地点")

	var notes_before := _inventory.count_item(&"ranger_note")
	trigger._discover()

	_assert(GameState.is_location_discovered(&"ranger_camp"), "地点已记录为发现")
	_assert(_inventory.count_item(&"ranger_note") == notes_before + 1, "发现后拿到猎人笔记")
	_assert(_inventory.count_item(&"charm_ward") >= 1, "发现后拿到护身符")

	# 重复进入不重复发放
	var notes_now := _inventory.count_item(&"ranger_note")
	trigger._discover()
	_assert(_inventory.count_item(&"ranger_note") == notes_now, "重复进入不重复发放奖励")


## 两个世界事件：条件求值、表现开关、存档。
func _test_world_events() -> void:
	var manager := get_tree().get_first_node_in_group(&"world_event_manager") as WorldEventManager
	_assert(manager != null, "世界事件管理器已挂载")
	if manager == null:
		return

	# --- 夜间发光 ---
	GameState.set_time_of_day(22.0 * 60.0)
	GameState.weather_id = &"clear"
	EventBus.location_entered.emit(&"creek_upper")
	_assert(manager.conditions_met_for(&"night_bloom"),
		"夜间 + 晴天 + 玩家在溪谷上游 → 满足夜间发光条件")

	GameState.set_time_of_day(12.0 * 60.0)
	_assert(not manager.conditions_met_for(&"night_bloom"), "白天不满足夜间发光条件")

	GameState.weather_id = &"rain"
	_assert(not manager.conditions_met_for(&"night_bloom"), "下雨天不满足夜间发光条件")
	GameState.weather_id = &"clear"

	var bloom := _find_night_bloom()
	_assert(bloom != null, "场景里有夜间发光植物带")
	if bloom != null:
		manager.force_start(&"night_bloom")
		await get_tree().process_frame
		await get_tree().process_frame
		_assert(bloom.is_lit(), "夜间发光事件点亮植物带")
		manager.force_end(&"night_bloom")
		# 淡出是渐变的：目标强度立刻归零，实际亮度再慢慢降下去
		_assert(is_zero_approx(bloom.target_glow()), "事件结束后植物带开始淡出")
		for i in 120:
			await get_tree().process_frame
			if not bloom.is_lit():
				break
		_assert(not bloom.is_lit(), "事件结束后植物带熄灭")

	# --- 雨后涨水 ---
	EventBus.location_exited.emit(&"creek_upper")
	GameState.weather_id = &"rain"
	EventBus.weather_changed.emit(&"rain")
	_assert(not manager.conditions_met_for(&"creek_surge"), "刚下雨不满 3 分钟不触发涨水")

	manager.shift_weather_start(200.0)
	_assert(manager.conditions_met_for(&"creek_surge"), "连续下雨超过 3 分钟触发涨水")

	var water := _find_creek_water()
	_assert(water != null, "场景里有溪流水面")
	if water != null:
		_assert(not water.is_surging(), "初始没有涨水")
		_assert(not water.is_crossing_blocked(), "初始涉水点可以通行")

		manager.force_start(&"creek_surge")
		await get_tree().process_frame
		await get_tree().process_frame
		_assert(water.is_surging(), "涨水事件让水位上升")
		_assert(water.is_crossing_blocked(), "涨水时涉水点被挡住")

		manager.force_end(&"creek_surge")
		await get_tree().process_frame
		await get_tree().process_frame
		_assert(not water.is_surging(), "退水后水位回落")
		_assert(not water.is_crossing_blocked(), "退水后涉水点恢复通行")

	# 主线不受涨水影响：营地到守林站的路不经过涉水点
	var cache := _find_interactable_by_id(&"east_bank_cache")
	_assert(cache != null, "东岸的猎人补给堆在场景里（涨水关掉的捷径终点）")


## 新增的两段存档字段。
func _test_m2_save_fields() -> void:
	var data := GameState.to_dict()
	_assert(data.has("discovered_locations"), "存档含已发现地点段")
	_assert(data.has("world_events"), "存档含世界事件段")

	GameState.set_world_event_state(&"night_bloom", {"state": 1, "active_since": 123.0})
	var saved := GameState.to_dict()
	GameState.world_events.clear()
	GameState.from_dict(saved)
	_assert(int(GameState.get_world_event_state(&"night_bloom").get("state", -1)) == 1,
		"世界事件状态可存可读")

	# 旧存档缺这两段时按空处理，不能读崩
	GameState.from_dict({"world_flags": {}, "changed_objects": {}})
	_assert(GameState.discovered_locations.is_empty(), "旧存档缺少已发现地点段时按空处理")
	_assert(GameState.world_events.is_empty(), "旧存档缺少世界事件段时按空处理")


# ------------------------------------------------------------------ 查找辅助


## 按 location_id 找区域触发器。
func _find_location(location_id: StringName) -> LocationTrigger:
	for node in get_tree().get_nodes_in_group(&"location_trigger"):
		var trigger := node as LocationTrigger
		if trigger != null and trigger.location_id == location_id:
			return trigger
	return null


## 按稳定 ID 找可交互物。
func _find_interactable_by_id(object_id: StringName) -> Interactable:
	for node in get_tree().get_nodes_in_group(&"interactable"):
		var interactable := node as Interactable
		if interactable != null and interactable.stable_id == object_id:
			return interactable
	return null


## 找溪流水面。
func _find_creek_water() -> CreekWater:
	for node in get_tree().get_nodes_in_group(&"world_event_effect"):
		var water := node as CreekWater
		if water != null:
			return water
	return null


## 找夜间发光植物带。
func _find_night_bloom() -> NightBloom:
	for node in get_tree().get_nodes_in_group(&"world_event_effect"):
		var bloom := node as NightBloom
		if bloom != null:
			return bloom
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
		await _teardown()
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("  - %s" % failure)
		print("结果：存在失败项")
		await _teardown()
		get_tree().quit(1)


## 退出前主动拆掉场景树。
##
## Godot 关闭阶段的资源释放顺序不稳定：任务系统里绑定了 Callable 的存档提供者
## 会让 quest_state.gd 的脚本资源在退出时仍未释放，偶尔触发访问冲突，
## 表现为测试明明全部通过、退出码却是 0xC0000005。
## 先把场景清干净再退出，可以避开这段不确定的清理过程。
func _teardown() -> void:
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
		_main = null
	await get_tree().process_frame
	await get_tree().process_frame
