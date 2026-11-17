# 垂直切片收尾设计（M2 剩余项）

- 文档版本：V1.0
- 适用阶段：M2 探索与战斗垂直切片
- 覆盖范围：异常守护者、两个世界事件、一个隐藏地点
- 前置：`development-plan.md` M2 退出条件、`game-design.md` §9.1 必须完成清单、`open-world-design.md` §8 动态世界

---

## 1. 这三项为什么必须一起做

`game-design.md` §9.1 要求垂直切片必须完成「一项包含三个步骤的主任务、**两个世界事件**和一个**隐藏地点**」以及「**两类敌人**」。
当前状态：

| 项 | 状态 | 缺口 |
|---|---|---|
| 主任务 | ✅ `camp_comm_radio` 三阶段任务链已跑通 | — |
| 两类敌人 | 🟡 只有林狼 | 缺第二类 |
| 两个世界事件 | ❌ 无实现 | 全缺 |
| 一个隐藏地点 | 🟡 只有 `LocationTrigger` 空壳基类 | 无玩法 |

这三项**不是三个孤立功能，而是一条闭环的三段**：

```text
   夜间发光事件 (night_bloom)
   夜间 · 溪谷上游 · 发光植物带指向东北
                    │
                    │  指引方向
                    ▼
   隐藏地点：猎人营地遗址
   松木林深处 · 猎人笔记提示「绕到背后」 + 独特物品
                    │
                    │  给出绕后动机
                    ▼
   异常守护者：守在涌泉
   命中 3 次后背部结晶暴露 → 弱点解锁，弱点伤害 ×2
```

外加一条独立的：

```text
   雨后涨水事件 (creek_surge)
   下雨 3 分钟后溪流上涨 → 关闭通往东岸的浅滩捷径
   不影响主线（主路不经该点），雨停 3 分钟后恢复
```

两个事件的原型都不是新造的：`open-world-design.md` §8 的示例里已经写着
「**夜间出现发光植物，引导隐藏入口**」和「**雨后溪流上涨，原路线被封闭**」。
本设计是把文档里已有的例子落成可实现的具体规则。

---

## 2. 异常守护者

### 2.1 定位

守在**溪谷上游的涌泉**处。涌泉本身是一个 B 级局部记忆点（`open-world-design.md` §4），
远看是一处凹陷泉眼，靠近能听到水声，地面有异常结晶。

选择涌泉而不是守林站或山脊，是为了**不与主线待裁决事项耦合**：
主线"保险丝 + 信号装置"目前在 `game-design.md` §7（叙事框架）与 §10（垂直切片验收场景）
与 `first-scene-design.md` §4.6（无线电：开启主任务）之间有两种互斥读法，
异常守护者不能押在其中一种上。涌泉是独立地点，裁决结果不影响本设计。

具体坐标：**世界坐标 (18, -130)**，溪流东岸 7 m 处。

选点不是拍脑袋定的，是用 `TerrainField` 实测出来的（一次性探针脚本量完就删）：

| 指标 | 实测值 | 说明 |
|---|---|---|
| 地面高度 | 1.79 m | |
| 坡度 `slope_at` | 0.025 | 几乎平地 |
| 离溪流 | 7.0 m | 在水边但不在过水区 |
| 离营地 | 131 m | 远离营火安全区 |
| 植被密度 | 0.123 | 泉眼周围稀疏，符合「异常点」的观感 |

同样被实测否决的候选点：`(14, -118)` 坡度 0.25 太陡；`(30, -160)` 离溪流 19 m 太远。

守护者守的这个位置落在区块 (8, 5)，离营地 3 圈——**地形碰撞只做玩家附近 2 圈**，
所以玩家没走近时那一块还没碰撞，守护者会靠 lerp 悬在地面下约 0.1 m。
玩家进到 2 圈内、区块碰撞建好后就严丝合缝了。

### 2.2 与林狼的差异对照

数值全部以 `game/scenes/enemies/wolf.tscn` 的实际导出值为基线：

| 参数 | 林狼 | 异常守护者 | 设计意图 |
|---|---|---|---|
| `max_health` | 55 | **240** | 单体高生命，需要约 6 箭满蓄力 |
| `move_speed` | 2.8 | **1.5** | 慢，接近它就是主动送死 |
| `chase_speed` | 5.8 | **3.0** | 追不上玩家 → 可以拉开距离绕后 |
| `attack_range` | 1.7 | **2.6** | 横扫，比狼远 |
| `attack_damage` | 9 | **24** | 一次挨打接近四分之一的血量 |
| `attack_windup` | 0.4 | **1.15** | **明显前摇**：有躲避窗口，也能被打断 |
| `attack_interval` | 1.5 | **2.6** | 惩罚贪刀：躲开后有喘息窗口 |
| `sight_range` | 24 | **34** | 守株待兔型，视野远但移速慢 |
| `sight_angle_deg` | 75 | **95** | 视野宽，难从正面溜过去 |
| `hearing_range` | 22 | **16** | 听觉迟钝，不靠声音发现你 |
| `leash_radius` | 34 | **20** | 守卫型，不追远，必回岗位 |
| `patrol_radius` | 10 | **5.5** | 岗位极小，活动范围可预期 |
| `weak_point_height` | 0.72 | **1.55** | 背部结晶的高度 |
| `can_flee` | true（0.25 血量触发） | **false** | **它不会逃**，必须正面处理 |
| 畏火光 | 绕开 7 m 内火源 | **不绕开** | 火驱不散它，迫使玩家绕后或用弓箭 |
| 掉落 | `arrow` ×2 | `anomaly_core` ×1、`first_aid` ×1 | 合成材料 + 补给 |

碰撞体：胶囊 `radius = 0.55`、`height = 2.6`，节点 `transform.y = 1.3`（与狼的 0.58 同构）。

### 2.3 弱点：观察解锁

`combat-and-progression.md` §4 要求「弱点需要观察环境线索发现」。
本设计把它落成**战斗中观察**而非拾取道具：

1. 守护者的**背部**有一簇发光结晶。默认不判定为弱点。
2. 玩家用**普通部位**命中它 3 次后，命中反馈里出现一句提示：
   > 「你注意到它背脊上的结晶在随着呼吸明灭。」
3. 弱点从此解锁。解锁后命中背部结晶 → `DamageKind.WEAKPOINT` → 伤害 ×2（`EnemyBase.apply_damage` 已实现）。
4. 提示语**只在首次解锁时出现一次**，此后 HUD 用命中标记区分「结晶」与「躯干」。

位置判定为**高度 + 方向**双重条件：

- 高度：`hit_point.y - global_position.y >= weak_point_height`（1.55 m）
- 方向：命中点相对敌人朝向的水平 dot < -0.3，即打在**背面**

两者同时满足才算弱点。玩家需要绕到背后，并从站立高度（眼高约 1.7 m）斜射背部结晶。

### 2.4 基类改动（最小侵入）

异常守护者的行为差异**尽可能用导出属性表达**，避免子类覆盖基类逻辑：

| 新增导出属性（`EnemyBase`） | 默认值 | 作用 |
|---|---|---|
| `can_flee: bool` | `true` | 为 false 时不进入 `State.FLEE` |
| `weak_point_requires_discovery: bool` | `false` | 为 true 时需先满足解锁条件 |
| `weak_point_hits_to_unlock: int` | `3` | 累计普通命中多少次后解锁 |
| `weak_point_requires_behind: bool` | `false` | 为 true 时额外要求命中点在背面 |

基类内新增一个私有计数 `_hits_taken`，在 `apply_damage()` 里累加并触发解锁。
解锁时发一次 `EventBus` 信号供 HUD 使用。

`is_weak_point()` 的判定顺序：`解锁条件 → 高度 → 方向`（方向判定在 `weak_point_requires_behind` 为 true 时才执行）。

### 2.5 子类实现要点

`game/scripts/combat/guardian_enemy.gd`，继承 `EnemyBase`：

- `_build_visual()`：躯干 + 背部结晶（结晶用 `PropKit.glow_material()` 的自发光材质）。
- `_decide()`：基类逻辑之上加一条——离开岗位半径后**主动返回涌泉**，而不是原地巡逻。
  基类的 `_clamp_to_home()` 只做贴地，返回岗位需要子类覆写 `_act()` 实现。
- `_steer_direction()`：**不覆写**。基类实现不绕火源 → 守护者无视火光。
- 不实现群体系（`EnemyBase` 无此逻辑，天然单体）。
- `drops` 在 `.tscn` 里配置。

### 2.6 新增物品

| 物品 ID | 名称 | 用途 |
|---|---|---|
| `anomaly_core` | 异常结晶 | M4 制作材料；垂直切片内作为护身符的兑换物（M4 再细化） |

物品资源：`game/resources/items/anomaly_core.tres`，遵循 `ItemDefinition` 的现有字段。

---

## 3. 隐藏地点

### 3.1 地点

**猎人营地遗址**：松木林深处一处猎人留下的废弃营地。

具体坐标：**世界坐标 (142, -168)**。同样由 `TerrainField` 实测定点：

| 指标 | 实测值 | 说明 |
|---|---|---|
| 地面高度 | 15.83 m | 比营地高 15 m，有「爬进林子深处」的感觉 |
| 坡度 `slope_at` | 0.021 | 几乎平地，营地能平整地铺开 |
| 植被密度 | 0.533 | 全图偏高的地带，符合「松木林深处」 |
| 离溪流 | 131 m | 不在溪谷边上 |
| 离营地 | 219 m | 走过去要花点时间 |

它和守护者的涌泉相距 129 m——两个不同的地点，不是同一处。

- 场景内容：倒塌的帐篷骨架、翻倒的捕兽夹、熄灭已久的火塘、一只背包、插在地上的标箭。
- 视觉线索：从远处看是几根支棱的杆子，走近才发现是营地残骸。
- 世界观文本（发现时展示一行）：
  > 「有人在这里住过很久，留下的东西却像是昨天才丢下的。」

### 3.2 发现与奖励

- 进入 `LocationTrigger` 的 `Area3D` 即**发现**（不需要额外交互）。
- 发现奖励：
  - `ranger_note` —— **猎人笔记**（唯一物品）。内容提示守护者的弱点在背部：
    > 「它只转过身时背脊才会亮。从侧面等，别正对着它。」
  - `charm_ward` —— **护身符**（独特物品，装饰性 + M4 制作入口）。
- 奖励只发一次，已发现地点重复进入不再发放。

### 3.3 `LocationTrigger` 扩展

现有 `game/scripts/world/location_trigger.gd` 只有一个 `location_id`，
是纯进出通知器。扩展为：

| 新增导出属性 | 类型 | 作用 |
|---|---|---|
| `display_name: String` | String | 发现时显示的地点名 |
| `discoverable: bool` | bool | true = 隐藏地点，进入即发现 |
| `reward_items: Array[Dictionary]` | Array | `[{id, amount}]`，发现时一次性发放 |
| `discovery_text: String` | String | 世界观文本 |

扩展后 `location_trigger.gd` 仍保持"进出通知 + 可选发现"两职：
普通区域触发器只设 `location_id`，不设 `discoverable`，行为与现在完全一致。

### 3.4 存档

`GameState` 新增：

```gdscript
## 隐藏地点是否已发现。location_id → bool。
var discovered_locations: Dictionary = {}
```

发现过的地点写入 `changed_objects` 之外**独立的一段**，
因为「已发现」与「已拾取」是两种状态（玩家发现地点但可能没来得及捡笔记）。

`to_dict()` / `from_dict()` 各加一段 `discovered_locations`，
旧存档缺该字段时按空字典处理（沿用 `from_dict()` 现有的缺字段兼容写法）。

---

## 4. 世界事件

### 4.1 架构

新增两个类：

| 类 | 位置 | 职责 |
|---|---|---|
| `WorldEventDefinition` | `game/scripts/world/world_event_definition.gd` | 事件定义（Resource），描述触发条件与参数 |
| `WorldEventManager` | `game/scripts/world/world_event_manager.gd` | 事件管理器（Node），求值条件、驱动状态、存档 |

`WorldEventManager` 挂在 `main.tscn` 的 `WorldManager` 下（不是 autoload——
它依赖场景树里的时间与天气节点）。

定义资源：`game/resources/events/night_bloom.tres`、`creek_surge.tres`。

### 4.2 条件模型

`open-world-design.md` §8 给出触发公式：

```text
触发条件 = 时间 + 天气 + 区域状态 + 玩家进度 + 冷却时间
```

落地为条件数组，每项是 `{"type": ..., ...}`：

| type | 参数 | 含义 |
|---|---|---|
| `time_window` | `from` / `to`（分钟，0..1440，可跨零点） | 当前时间在窗口内 |
| `weather` | `allow: [StringName]` | 当前天气在允许列表内 |
| `weather_duration` | `weather` / `minutes` | 某种天气已持续够久 |
| `player_in_region` | `region: StringName` | 玩家在指定区域触发器内 |
| `quest` | `quest_id` / `state` | 任务处于指定状态 |
| `world_flag` | `flag` / `value` | 世界标记为指定值 |

求值节奏：**每 0.5 秒**一次，外加**天气切换**后 3 秒内加快到 0.1 秒一次。
0.5 秒的间隔是为了让"夜间开始"这类窗口切换在体感上及时，
又不至于每帧求值；天气变化则要立刻响应——「下雨满 3 分钟」这类条件
不该等满一个周期才生效。

**表现节点通过分组自注册，不走节点路径。**
效果节点加入 `world_event_effect` 分组并声明自己响应的 `event_id`，
管理器在事件开始与结束时按 `event_id` 找到它们并调用 `apply_world_event(event_id, active)`。
这样事件定义和表现节点之间没有硬编码路径，换场景不用改代码。

### 4.3 状态机

```text
IDLE ──条件满足──> ACTIVE ──条件不再满足 / 超时──> COOLDOWN ──冷却结束──> IDLE
                                        │
                                        └──一次性事件──> COMPLETED（终态）
```

- `ACTIVE` 期间事件表现生效。
- `COOLDOWN` 期间不再触发（防止反复进出区域反复触发）。
- `COMPLETED` 是终态，一次性事件完成后不再重复。

### 4.4 事件 A：夜间发光 `night_bloom`

| 项 | 值 |
|---|---|
| 类型 | 重复型（每晚可再触发） |
| 条件 | `time_window` 21:00–04:00（跨零点）；`weather` allow = `[clear, cloudy, fog]`；`player_in_region` = `creek_upper` |
| 冷却 | 8 小时（日间自然满足不了时间窗口，冷却只是兜底） |
| 持续 | 整夜；玩家离开 `creek_upper` 区域 60 秒后淡出 |
| 可恢复 | 读档后按存档里的 `active_since` 重算，夜间继续 |

**表现**：溪谷上游沿岸生成一丛发光植物，沿溪流向东北（涌泉方向）排列，
形成一条可见的视觉引导线。用 MultiMesh 单批渲染，与 `world_chunk.gd` 的植被同法。
发光材质偏冷（青白），与暖色营火区分。

具体坐标：植物带从 **(2, -104)** 排到 **(15, -128)**，共 48 丛，
横向抖动 ±2.6 m，指向涌泉 (18, -130)。整条带子落在 `creek_upper` 区域内，
玩家进区域时事件才可能触发。

**淡出而不是硬切**：事件结束时自发光强度从 2.0 渐变到 0（1.6 / 秒，约 1.25 秒）。
硬切会让正在看它的玩家眼前一闪。

**引导强度**：植物带本身指向东北，但不显示任何 UI 箭头
（`open-world-design.md` §7「不用大量 UI 箭头取代环境引导」）。
玩家到达引导带末端时，HUD 给一行氛围提示：
> 「空气里有股不属于这条溪谷的味道。」

### 4.5 事件 B：雨后涨水 `creek_surge`

| 项 | 值 |
|---|---|
| 类型 | 重复型 |
| 条件 | `weather_duration`：连续下雨 ≥ 3 分钟 |
| 持续 | 下雨期间持续；条件失效后再撑 3 分钟才退水（`linger_minutes`） |
| 冷却 | 2 小时 |
| 影响 | 溪流水位从 -1.0 抬到 **+0.15**；**踩石过河点被挡住** |

**通路是人工的，不是天然的。** 这一点是被实测推翻后改的：

原设计打算让涨水淹没天然浅滩。但实测溪流横断面后发现，
河床全程是平的 -1.15，而 z ∈ [30, 66] 段的岸高在 **1.7～4.0 m**——
那是崖壁，本来就过不去。0.55 m 的涨幅根本淹不到任何能走的岸边。

所以改用**猎人铺的踩石**作为过河通路：

| 高度 | 数值 | 状态 |
|---|---|---|
| 河床 | -1.15 | 石头底面 |
| 平常水面 | -0.94 | 石头露出 0.52 m，踩着能过 |
| 涨水后水面 | +0.15 | 石头没入水下 0.57 m，路断了 |

踩石一排 8 块，横在营地东南方 z = 22 的溪流上，从西岸 x ≈ 5.6 通到东岸 x ≈ 17.4。
东岸尽头是**猎人补给堆**（`ration` ×2），那才是涨水事件关掉的捷径的终点。

**水不挡路，路断靠碰撞体。** 水面网格没有碰撞——踩进水里只是"湿了"。
所以涨水时 `CreekWater` 会启用一道 `StaticBody3D` 挡住涉水点，
退水时再关掉。只抬水面而不挡路，事件就等于没发生。

**不影响主线**：主线路径在营地南侧与溪谷西岸，不经过踩石。
关掉的只是一条**捷径**——别处仍能过溪，只是远得多。
这条设计的验收点是"玩家在雨中发现捷径走不通，但主线照常推进"，
`open-world-design.md` §8 的硬要求：**事件必须可中断、可恢复，不得把关键主线永久锁死**。

**退水必须可逆**：雨停 3 分钟后水位回落到 -1.0，踩石重新露出，碰撞体关闭。

### 4.6 存档

`GameState` 新增：

```gdscript
## 世界事件状态。event_id → {state, active_since, cooldown_until, completed}
var world_events: Dictionary = {}
```

写入 `to_dict()` / `from_dict()`，旧存档缺字段按空字典处理。

读档恢复规则：

- `ACTIVE` 的事件：重新求值条件。若读档后条件仍满足 → 恢复 ACTIVE 并重建表现；
  不满足 → 转入 COOLDOWN。
- `COOLDOWN` 的事件：按 `cooldown_until` 继续冷却。

`cooldown_until` 存的是 **Unix 时间戳（秒）**，不是"绝对分钟数"。
用墙钟时间戳而不是管理器自己的计时器，是为了让冷却跨读档保持有效——
管理器的计时器在读档后会归零，拿它比就会立刻解除冷却。

### 4.7 EventBus 新增信号

```gdscript
signal world_event_started(event_id: StringName)
signal world_event_ended(event_id: StringName, reason: StringName)
signal location_discovered(location_id: StringName, display_name: String)
signal location_reward_claimed(location_id: StringName, item_id: StringName)
signal weak_point_discovered(enemy_name: String)
signal weather_changed(new_weather: StringName)
```

`weak_point_discovered` 属于 §2.4 的弱点观察机制：解锁时发一次，HUD 提示
「你注意到它背脊上的结晶在随着呼吸明灭」。

`weather_changed` 原先只挂在 `WeatherController` 上。世界事件的条件依赖它，
所以补到全局总线上——天气切换是领域事件，不是控制器内部的实现细节。

命名沿用 `technical-design.md` §4.4 的 `域.谓词` 约定。

### 4.8 HUD 提示

事件不给常驻 UI。触发时用一行短暂的顶部提示（沿用现有 HUD 的提示行机制），
不遮挡准星，不暂停游戏。

---

## 5. 接口变更汇总

开发前需要确认的改动清单，全部是**新增**，不改动现有行为：

| 文件 | 改动 |
|---|---|
| `game/scripts/combat/enemy_base.gd` | 新增 4 个导出属性 + `_hits_taken` + 解锁逻辑 |
| `game/scripts/combat/guardian_enemy.gd` | **新增** |
| `game/scenes/enemies/guardian.tscn` | **新增** |
| `game/scripts/world/location_trigger.gd` | 新增 4 个导出属性 + 发现流程 |
| `game/scripts/world/world_event_definition.gd` | **新增** |
| `game/scripts/world/world_event_manager.gd` | **新增** |
| `game/scripts/world/creek_water.gd` | **新增**（水位 + 涉水点阻挡，供 `creek_surge` 驱动） |
| `game/scripts/world/night_bloom.gd` | **新增**（发光植物带，供 `night_bloom` 驱动） |
| `game/scripts/world/ranger_camp.gd` | **新增**（隐藏地点装配：贴地 + 建道具） |
| `game/scripts/world/ranger_camp_builder.gd` | **新增**（遗址道具） |
| `game/scenes/world/ranger_camp.tscn` | **新增** |
| `game/resources/events/*.tres` | **新增** 2 个事件定义 |
| `game/resources/items/anomaly_core.tres` | **新增** |
| `game/resources/items/ranger_note.tres` | **新增** |
| `game/resources/items/charm_ward.tres` | **新增** |
| `game/autoload/event_bus.gd` | 新增 6 个信号 |
| `game/autoload/game_state.gd` | 新增 `world_events` / `discovered_locations` 两段 + 存档读写 |
| `game/scripts/combat/enemy_base.gd` | 新增 4 个导出属性 + 弱点解锁 + 补上从未实现的 leash 判定 |
| `game/scripts/gameplay/inventory.gd` | 注册 `inventory` 分组（隐藏地点发奖励要找它） |
| `game/scripts/world/prop_kit.gd` | 新增守护者、遗址道具、踩石、发光的芽共 9 个构造函数 |
| `game/scripts/world/camp_builder.gd` | 溪流水面换成 `CreekWater`，新增踩石与东岸补给堆 |
| `game/scripts/world/camp_site.gd` | 水面动画移交 `CreekWater` |
| `game/scripts/world/weather_controller.gd` | 补发 `EventBus.weather_changed` |
| `game/scenes/world/pine_valley.tscn` | 接入隐藏地点、守护者、发光带、溪谷上游区域触发器 |
| `game/scenes/main/main.tscn` | 挂载 `WorldEventManager` |
| `game/scripts/main.gd` | 物品定义表增加 3 件新物品 |
| `game/tests/test_smoke.gd` | 扩充断言（见 §6） |

---

## 6. 验收标准

沿用 `combat-and-progression.md` §9 与 `open-world-design.md` §10，并补充本设计特有的项：

### 异常守护者

- 守护者不会逃跑：血量降到 25% 以下仍持续攻击。
- 守护者无视火光：站在营火旁不会绕开。
- 前摇期间被打断则本次攻击不生效。
- 普通部位命中 3 次后出现弱点提示；此后背面结晶命中伤害为普通伤害的 2 倍。
- 正面命中结晶**不算**弱点。
- 守护者离开岗位 20 m 后返回涌泉，不会追到营地。
- 击败后掉落 `anomaly_core` ×1 与 `first_aid` ×1，且**读档后不复活**。

### 世界事件

- 夜间在溪谷上游触发 `night_bloom`，出现发光植物带；白天不出现；下雨天不出现。
- 下雨满 3 分钟触发 `creek_surge`，水位上升且**踩石过河点被挡住**；
  雨停 3 分钟后水位回落、通路恢复。
- **两个事件都不阻断主线推进**：涨水期间主线路径全程可走。
- 读档后事件状态正确恢复（不重复发奖励、不丢失 ACTIVE 事件）。
- 旧存档缺少 `world_events` / `discovered_locations` 两段时按空处理，不读崩。

### 隐藏地点

- 进入猎人营地遗址即触发发现提示，发放 `ranger_note` 与 `charm_ward`。
- 重复进入不重复发放。
- 读档后地点保持已发现，奖励不重复。

### 整体

- 冒烟测试全绿，新增断言覆盖上述各项。
- 首次玩家仍能在 20～30 分钟内完成主线（`development-plan.md` M2 退出条件）。

---

## 7. 实现顺序

按"每一步都能独立验证"排列，避免同时改基类、事件、存档三处后难以定位问题：

1. **`EnemyBase` 扩展** + 单测：新属性不改变林狼现有行为（林狼保持 `can_flee = true`、
   `weak_point_requires_discovery = false`）。
2. **异常守护者**：脚本 + 场景 + 掉落物品。这是独立于事件与地点的一块，先做完能单独测。
3. **存档与事件总线扩展**：`GameState` 两个新字段 + 6 个信号 + 旧存档兼容测试。
4. **隐藏地点**：`LocationTrigger` 扩展 + 场景 + 两个奖励物品。
5. **世界事件框架**：`WorldEventDefinition` + `WorldEventManager` + 条件求值 + 存档。
6. **两个事件的表现**：发光植物带、溪流水位与涉水点阻挡。
7. **冒烟测试扩充 + 退出条件实测**：跑一遍完整主线，计时确认 20～30 分钟。

> 第 1～7 步已实现。冒烟测试从 155 项扩到 **207 项**，全部通过。
> 剩下的只有第 7 步的后半段：**真人跑一遍主线计时**，确认 20～30 分钟。
> 这项没法用无头测试代替——它是 M2 退出条件里唯一需要人参与的。

---

## 8. 与既有文档的关系

| 文档 | 关系 |
|---|---|
| `combat-and-progression.md` §4 | 「异常守护者」的 4 行描述（单体、慢速、高生命 / 守卫特定地点 / 攻击前摇明显 / 弱点需要观察环境线索发现）由本文 §2 展开为可实现规格 |
| `combat-and-progression.md` §8 | 垂直切片范围「两种敌人」由本文满足 |
| `open-world-design.md` §8 | 两个示例事件（夜间发光植物、雨后溪流上涨）由本文 §4 落成具体规则 |
| `open-world-design.md` §2 | 「猎人营地」由本文 §3 定为隐藏地点 |
| `game-design.md` §9.1 | 「两个世界事件和一个隐藏地点」「两类敌人」由本文覆盖 |
| `development-plan.md` M2 | 退出条件「首次玩家 20～30 分钟完成主线」在本文 §7 列为收尾验收项 |

> 本设计**不裁决**主线"保险丝 + 信号装置"两种互斥读法
> （`game-design.md` §7 与 §10，对 `first-scene-design.md` §4.6），
> 异常守护者的放置已刻意避开该分歧。
