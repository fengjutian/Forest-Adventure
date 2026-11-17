# Forest Adventure

第一人称开放世界深林冒险。Godot 4.x + Blender + 程序化生成，单人开发，Windows PC 首发。

完整设计见 [`docs/README.md`](./docs/README.md)。

## 当前状态

**M0 工程基础已完成，M1 灰盒任务链可玩，场景已程序化生成。**

- 7 篇设计文档（见 `docs/`）
- Godot 4 工程：输入映射、第一人称控制器、统一交互接口、背包、任务系统、版本化存档
- 灰盒营地场景 + 三阶段任务链（拾取保险丝 → 修复无线电 → 返回营火）
- 程序化营地：噪声地形、溪谷、松林、灌木、地被草丛，人工地标（木屋 / 物资棚 / 发电机 / 靶场 / 帐篷 / 灯柱 / 柴堆 / 路牌 / 营火）
- 无头冒烟测试 88 项，全部通过
- M2 及之后的战斗、天气、流式加载、AI→Blender 管线尚未开始

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
│   │   ├── interactables/   可交互物
│   │   └── ui/              HUD
│   ├── scripts/
│   │   ├── core/            结构化日志
│   │   ├── gameplay/        玩家、背包、任务、物品
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

# 无头冒烟测试（88 项检查）
& $env:GODOT_EXE --headless --path game res://tests/test_smoke.tscn

# 抓取渲染帧（需要图形后端，不能 --headless）
& $env:GODOT_EXE --path game res://tests/capture_screenshot.tscn

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
| 释放鼠标 | Esc | 快速保存 / 读取 | F5 / F9 |

> **鼠标不会被自动锁定。** 启动后光标仍在系统里，屏幕中央提示「点击画面控制视角 · Esc 释放鼠标」。
> 点击画面才进入视角控制，Esc 随时归还鼠标，切到别的程序时也会自动释放。

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
