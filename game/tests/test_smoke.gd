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

	# 流式加载：走远后营地卸载、脚下加载。
	# 先把敌人冻住，免得它们追着瞬移的玩家跑出营地，影响后续感知测试。
	var enemies := get_tree().get_nodes_in_group(&"enemy")
	for enemy in enemies:
		(enemy as Node).set_physics_process(false)

	var saved_position := _player.global_position
	_player.set_physics_process(false)
	_player.global_position = Vector3(460.0, world.height_at(460.0, 460.0) + 2.0, 460.0)
	for i in 240:
		await get_tree().process_frame

	var far_coord := world.world_to_chunk(_player.global_position)
	_assert(world.is_chunk_loaded(far_coord), "远处脚下的区块已流式加载")
	_assert(not world.is_chunk_loaded(camp_coord), "离开后营地区块已卸载")
	_assert(world.loaded_chunk_count() <= chunk_bound, "流式加载后区块数仍有界")

	_player.global_position = saved_position
	_player.set_physics_process(true)
	for enemy in enemies:
		(enemy as Node).set_physics_process(true)
	for i in 240:
		await get_tree().process_frame
	_assert(world.is_chunk_loaded(camp_coord), "回到营地后区块重新加载")


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

	# 蓄力时右手必须把弦往后拉（而不是一只静态的手）
	_player.capture_mouse()
	Input.action_press("aim")
	for i in 3:
		await get_tree().process_frame
	var rest := right_hand.position
	Input.action_press("fire")
	for i in 20:
		await get_tree().process_frame
	var drawn := right_hand.position
	Input.action_release("fire")
	Input.action_release("aim")
	_player.release_mouse()
	_assert(drawn.distance_to(rest) > 0.02,
		"蓄力时右手把弦拉开（位移 %.3f m）" % drawn.distance_to(rest))
	_assert(drawn.z > rest.z, "拉弦方向朝向后（弦心后移）")

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
		# 生成后立刻取位置：箭速 42 m/s，等一帧就已经飞出去 0.7 m 了
		var spawned := _find_arrow()
		_assert(spawned != null, "弓能生成箭矢实体")
		if spawned != null and camera != null:
			var forward := -camera.global_transform.basis.z
			var muzzle := camera.global_position + forward * 0.6 - camera.global_transform.basis.y * 0.15
			var offset := spawned.global_position.distance_to(muzzle)
			_assert(offset < 0.2, "箭矢按世界坐标落在射手手边（偏差 %.2f m）" % offset)
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
