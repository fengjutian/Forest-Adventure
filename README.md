# Forest Adventure

第一人称开放世界深林冒险。Godot 4.x + Blender + 程序化生成，单人开发，Windows PC 首发。

完整设计见 [`docs/README.md`](./docs/README.md)。

## 当前状态

**M0 工程基础已完成，M1 灰盒任务链可玩，M2 战斗垂直切片（弓箭 + 林狼）已跑通。**

- 7 篇设计文档（见 `docs/`）
- Godot 4 工程：输入映射、第一人称控制器、统一交互接口、背包、任务系统、版本化存档
- 灰盒营地场景 + 三阶段任务链（拾取保险丝 → 修复无线电 → 返回营火）
- 程序化营地：噪声地形、溪谷、松林、灌木、地被草丛，人工地标（木屋 / 物资棚 / 发电机 / 靶场 / 帐篷 / 灯柱 / 柴堆 / 路牌 / 营火）
- 战斗闭环：弓箭（瞄准 / 蓄力 / 发射 / 命中 / 弱点）与林狼（成群示警 / 听觉优先 / 包围 / 畏火光）完整可玩
- 无头冒烟测试 130 项，全部通过
- M2 剩余的「异常守护者」敌人、M3 的 AI→Blender 管线尚未开始

### 场景生成分工

| 模块 | 职责 |
|---|---|
| `scripts/world/proc_terrain.gd` | FastNoiseLite 高度场 + 营地平整区 + 溪谷下切；顶点色按高度/坡度/区域着色；凹多边形碰撞 |
| `scripts/world/vegetation_scatter.gd` | MultiMesh 散布松林、桦树、枯立木、倒木、树桩、岩石、灌木、草丛；噪声调密度，营地/溪流/主路径排除，陡坡不生长 |
| `scripts/world/camp_builder.gd` | 人工地标：木屋、物资棚、发电机、训练靶场、倒木、路牌、帐篷、灯柱、柴堆、木桶、溪流水面、远景山体 |
| `scripts/world/prop_kit.gd` | 程序化网格与材质库（顶点色即反照率），正式美术资产到位后只替换这里 |
| `scripts/world/camp_scene.gd` | 装配编排：地形 → 地标 → 贴地 → 植被 |

> **同一个 seed 必得同一个场景**（`proc_terrain.terrain_seed` / `vegetation_scatter.scatter_seed` / `camp_builder.camp_seed`）。
> 地形碰撞与渲染网格的三角形绕向必须一致（`(v00, v10, v01)` 朝上），
> 写反了地形会被背面剔除、角色也会直接穿过地面。

### 树木

- 每棵树都是独立生成的形态：**5 个松树变体 + 2 个桦树变体**，层数、半径、层间偏移都随 seed 变化，森林里没有两棵完全一样的树
- 混交林：桦树占乔木 22%，另有枯立木、倒木、树桩提供林下层次
- 树冠用顶点着色器**随风轻摆**（`PropKit.swaying_material()`）：高度加权，越高摆得越多；每棵树的相位写在 MultiMesh 实例自定义数据里，整片林子不会齐刷刷一起晃
- 被测层不投影：看不出来却要多走一遍阴影 pass，关掉后每帧三角形数从 1.5M 降到 0.9M

### 战斗系统

垂直切片只做**弓箭**这一种主武器和**林狼**一种敌人（`docs/combat-and-progression.md §1、§4`）。

**弓箭**

| 操作 | 效果 |
|---|---|
| 鼠标右键（按住） | 瞄准：视野 75° → 55°，鼠标灵敏度 ×0.45，准星张开 |
| 鼠标左键（按住 → 松开） | 蓄力射击：蓄满 1.1s，基础伤害 32，箭速 16→42 m/s |
| 蓄力 | 持续消耗体力（14/s）；体力不足时蓄得更慢，体力耗尽就完全蓄不满 |
| 发射 | 箭矢从背包扣除，右下角显示余量；射箭产生 1.2s 噪声，会暴露位置 |

- 弓常驻在第一人称画面右下，瞄准时抬到屏幕中心，弓弦正对屏幕中心
- 弓是**「人」的动作**而不是一把浮空的弓：左手扣握把、右手捏弦，双手直接挂在弓身上（和弓共用缩放，比例不会走形）；蓄力时弓弦折成 V 形、箭随之后移；走路与冲刺有持弓摆动，站定时有呼吸起伏，转视角有惯性滞后
- 箭矢是**手动积分 + 射线检测**（`Node3D` 而非 `RigidBody3D`）：42 m/s 下物理帧之间会穿过去，手动射线还能精确取命中点判断弱点
- 命中判定取自命中点高度，高于狼的 `weak_point_height` 算弱点，**弱点伤害 ×2**
- 命中敌人扣血并显示命中标记；命中环境则钉在表面 6 秒后消失

**林狼**

- **成群示警**：一只狼进入追逐时，30m 内的同伴一起转入追逐
- **听觉优先**：听觉 22m > 视觉 24m 但触发更直接——听到动静直接扑过来，看到目标先怀疑再确认
- **包围**：不去抢同一个落点，按稳定 ID 派生固定包抄侧，几只狼从不同方向围上来
- **畏火光**：靠近营火 7m 内会绕开
- **对角小跑**：4 条腿按对角步态摆动，速度越快步频越快
- 感知用射线遮挡检查，保证「敌人不能隔墙发现或攻击玩家」；`leash_radius` 之外脱离战斗返回

**伤害模型**：普通伤害 / 弱点伤害（×2）/ 火焰伤害 / 环境伤害。命中后有硬直，生命低于 25% 转入逃跑。

**敌人状态存档**：已击败的敌人通过稳定 ID 记进 `changed_objects`（如 `wolf_01_drop_arrow`），读档后不会复活；绝不使用运行时实例 ID。

> **切片范围裁剪**：文档 §2 有「专注」资源，但 `game-design.md:184` 的切片范围不含专注，
> 因此蓄力消耗改用体力。这是为了在切片范围内自洽，不是对文档的裁决。

### 战斗模块

| 模块 | 职责 |
|---|---|
| `scripts/combat/enemy_base.gd` | 分层敌人基类：感知层 / 决策层 / 动作层 / 状态层四层分离，伤害、硬直、死亡、掉落与存档 |
| `scripts/combat/wolf_enemy.gd` | 林狼：成群示警、听觉优先、侧翼包围、畏火光、对角小跑步态 |
| `scripts/combat/arrow_projectile.gd` | 箭矢：手动积分 + 射线检测，命中敌人扣血并取命中点判弱点，命中环境钉住后消失 |
| `scripts/gameplay/bow.gd` | 弓箭：瞄准收窄视野、蓄力耗体力、松开发射、第一人称弓模型 |
| `scenes/enemies/wolf.tscn` | 林狼场景：碰撞层 `enemy`、胶囊碰撞体、掉落配置 |

## 仓库结构

```
Forest-Adventure/
├── docs/                    设计文档（7 篇）
├── game/                    Godot 4 工程
│   ├── autoload/            EventBus / GameState / SettingsManager / SaveManager
│   ├── scenes/
│   │   ├── main/            主场景
│   │   ├── player/          玩家
│   │   ├── world/           灰盒场景
│   │   ├── enemies/         敌人场景
│   │   ├── interactables/   可交互物
│   │   └── ui/              HUD
│   ├── scripts/
│   │   ├── core/            结构化日志
│   │   ├── gameplay/        玩家、背包、任务、物品、弓箭
│   │   ├── combat/          敌人基类、林狼、箭矢投射物
│   │   ├── interaction/     交互契约与射线系统
│   │   ├── ui/              HUD、准星
│   │   └── world/           昼夜、天气、区块、出生点、音频
│   ├── resources/
│   │   ├── items/           物品定义（.tres）
│   │   └── quests/          任务定义（.tres）
│   ├── assets/              generated / authored / third_party
│   ├── tests/               无头冒烟测试 + 截图工具
│   ├── project.godot
│   └── export_presets.cfg
├── tools/
│   ├── run.ps1              一键启动
│   ├── build_windows.ps1    导入 → 测试 → 导出
│   └── forest_generator/    AI → Blender 管线（M3 启动，当前为空壳）
├── build/                   构建产物（不入库）
└── README.md
```

## 环境要求

| 依赖 | 版本 | 说明 |
|---|---|---|
| Godot | 4.6 stable | 默认查找 `C:\Godot_v4.6-stable_win64.exe\` |
| Export Templates | 4.6 stable | **仅导出发布版时需要**，用 Godot 管理器安装 |
| Python | 3.12 | 生成器，M3 起需要 |
| Blender | 5.x | 生成器，M3 起需要 |

用 `GODOT_EXE` / `BLENDER_EXE` 环境变量或 `-GodotExe` 参数覆盖默认路径。

## 常用命令

```powershell
# 一条命令启动（自动定位 Godot，必要时先导入资源）
.\tools\run.ps1

# 用 Godot 编辑器打开工程
.\tools\run.ps1 -Editor

# 运行游戏（等价于 tools\run.ps1，但需要自己处理首次导入）
& $env:GODOT_EXE --path game

# 导入资源（新克隆后必须先跑一次，生成全局类缓存）
& $env:GODOT_EXE --headless --path game --import

# 无头冒烟测试（130 项检查）
& $env:GODOT_EXE --headless --path game res://tests/test_smoke.tscn

# 抓取渲染帧（需要图形后端，不能 --headless）
& $env:GODOT_EXE --path game res://tests/capture_screenshot.tscn

# 抓取战斗画面（林狼 / 举弓瞄准 / 营地俯视）
& $env:GODOT_EXE --path game res://tests/capture_combat.tscn

# 完整构建（导入 → 测试 → 导出）；无导出模板时用 -SkipExport
.\tools\build_windows.ps1
.\tools\build_windows.ps1 -SkipExport
```

> **首次运行必须先导入。** Godot 依赖 `.godot/global_script_class_cache.cfg` 解析
> `class_name` 声明的脚本。新克隆的仓库没有这个缓存，直接 `--path game` 会报
> `Identifier "GameLog" not declared in the current scope`。
> `tools\run.ps1` 会自动判断并补做导入；用编辑器打开时 Godot 也会自动导入。

## 操作

| 动作 | 键位 | 动作 | 键位 |
|---|---|---|---|
| 移动 | WASD | 交互 | E |
| 视角 | 鼠标（**先点击画面**激活） | 手电筒 | F |
| 冲刺 | Shift | 背包 | Tab |
| 下蹲 | Ctrl | 地图 | M |
| 跳跃 | Space | 指南针 | C |
| 瞄准 | 鼠标右键 | 射击 | 鼠标左键 |
| 释放鼠标 | Esc | 快速保存 / 读取 | F5 / F9 |
| 按键提示 | H | | |

> **鼠标不会被自动锁定。** 启动后光标仍在系统里，屏幕中央提示「点击画面控制视角 · Esc 释放鼠标」。
> 点击画面才进入视角控制，Esc 随时归还鼠标，切到别的程序时也会自动释放。

> **按键提示**：进游戏先在右侧弹出按键表，9 秒后自动收起；之后按 H 随时开关，
> 收起时右上角保留「H 按键提示」角标。面板内容直接读输入映射，改键后不用同步改 UI；
> 交互提示同样带键位，例如「[E] 拾取备用保险丝」。

## 里程碑

M0 工程基础 → M1 灰盒可玩链路 → M2 探索与战斗垂直切片 → M3 程序化森林管线 → M4 内容替换与打磨 → M5 开放世界扩展

详见 [`docs/development-plan.md`](./docs/development-plan.md)。

## 已知待裁决事项

主线任务的保险丝与信号装置流程在文档中存在两种互斥读法：

- `docs/game-design.md:158,203` — 在**山脊信号装置**修复并获得回应
- `docs/first-scene-design.md:100,151-160` — 在**营地无线电**装保险丝并获得信号

当前 M1 灰盒任务链取两者交集（拾取保险丝 → 修复设备 → 返回营地），
不预设最终裁决结果。裁决后需要同步修改 `docs/game-design.md`、
`docs/first-scene-design.md` 与 `docs/development-plan.md:43`。
