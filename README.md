# Forest Adventure

第一人称开放世界深林冒险。Godot 4.x + Blender + 程序化生成，单人开发，Windows PC 首发。

完整设计见 [`docs/README.md`](./docs/README.md)。

## 当前状态

**M0 工程基础已完成，M1 灰盒任务链可玩。**

- 7 篇设计文档（见 `docs/`）
- Godot 4 工程：输入映射、第一人称控制器、统一交互接口、背包、任务系统、版本化存档
- 灰盒营地场景 + 三阶段任务链（拾取保险丝 → 修复无线电 → 返回营火）
- 无头冒烟测试 79 项，全部通过
- M2 及之后的战斗、天气、流式加载、AI→Blender 管线尚未开始

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
# 运行游戏
& $env:GODOT_EXE --path game

# 导入资源（新克隆后必须先跑一次，生成全局类缓存）
& $env:GODOT_EXE --headless --path game --import

# 无头冒烟测试（79 项检查）
& $env:GODOT_EXE --headless --path game res://tests/test_smoke.tscn

# 抓取渲染帧（需要图形后端，不能 --headless）
& $env:GODOT_EXE --path game res://tests/capture_screenshot.tscn

# 完整构建（导入 → 测试 → 导出）；无导出模板时用 -SkipExport
.\tools\build_windows.ps1
.\tools\build_windows.ps1 -SkipExport
```

## 操作

| 动作 | 键位 | 动作 | 键位 |
|---|---|---|---|
| 移动 | WASD | 交互 | E |
| 视角 | 鼠标 | 手电筒 | F |
| 冲刺 | Shift | 背包 | Tab |
| 下蹲 | Ctrl | 地图 | M |
| 跳跃 | Space | 指南针 | C |
| 暂停（释放鼠标） | Esc | 快速保存 / 读取 | F5 / F9 |

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
