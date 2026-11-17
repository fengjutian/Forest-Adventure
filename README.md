# Forest Adventure

第一人称开放世界深林冒险。Godot 4.x + Blender + 程序化生成，单人开发，Windows PC 首发。

完整设计见 [`docs/README.md`](./docs/README.md)。

## 当前状态

处于 **M0 工程基础** 阶段。仓库结构：

```
Forest-Adventure/
├── docs/                    设计文档（7 篇，见 docs/README.md）
├── game/                    Godot 4 工程
│   ├── autoload/            EventBus / GameState / SettingsManager / SaveManager
│   ├── scenes/              main / player / world / interactables / ui
│   ├── scripts/             core / gameplay / interaction / world / ai
│   ├── resources/           items / quests / weather / audio
│   ├── assets/              generated / authored / third_party
│   └── tests/               无头冒烟测试
├── tools/
│   └── forest_generator/    AI → Blender 内容生产管线（M3 启动，当前为空壳）
├── build/                   Windows 导出产物（不入库）
└── docs/
```

## 环境要求

- Godot 4.6 stable（`C:\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe`）
- Python 3.12（生成器，M3 起需要）
- Blender 5.x（生成器，M3 起需要）

用 `BLENDER_EXE` / `GODOT_EXE` 环境变量覆盖默认路径。

## 常用命令

```powershell
# 运行游戏
& $env:GODOT_EXE --path game

# 无头冒烟测试（脚本解析 + 自动加载 + 存读档 + 任务推进）
& $env:GODOT_EXE --headless --path game --script res://tests/test_smoke.gd

# 无头启动主场景，捕获运行期错误
& $env:GODOT_EXE --headless --path game --quit-after 180

# Windows 发布构建
.\tools\build_windows.ps1
```

## 里程碑

M0 工程基础 → M1 灰盒可玩链路 → M2 探索与战斗垂直切片 → M3 程序化森林管线 → M4 内容替换与打磨 → M5 开放世界扩展

详见 [`docs/development-plan.md`](./docs/development-plan.md)。

## 已知待裁决事项

主线任务的保险丝与信号装置流程在文档中存在两种互斥读法，见
[`docs/game-design.md`](./docs/game-design.md) 与
[`docs/first-scene-design.md`](./docs/first-scene-design.md)。
当前 M1 灰盒任务链取两者交集（拾取保险丝 → 修复设备 → 返回营地），
不预设最终裁决结果。
