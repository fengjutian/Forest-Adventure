#!/usr/bin/env python3
"""森林生成管线命令行入口，对应 docs/forest-pipeline-spec.md §6 / §10（M3-1）。

用法::

    python tools/forest_generator/main.py --validate <spec.json>      # 校验 SceneSpec
    python tools/forest_generator/main.py --keys                       # 打印 29 键表（含接缝）
    python tools/forest_generator/main.py --derive-seeds <base_seed>   # 打印派生种子
    python tools/forest_generator/main.py --emit-golden                # 重新生成黄金向量
    python tools/forest_generator/main.py --check-golden               # 比对黄金向量
    python tools/forest_generator/main.py --build --build-keys pine_0  # 构建资产（M3-2）

退出码：0 成功；1 校验失败；2 用法或 IO 错误。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# 允许从任意工作目录调用本脚本
sys.path.insert(0, str(Path(__file__).resolve().parent))

# 工具链的所有输出统一走 UTF-8（Windows 控制台默认代码页不是 UTF-8）
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):  # pragma: no cover - 老解释器或被替换的流
        pass

from lib import asset_keys, seed  # noqa: E402
from lib.spec import format_issue, load_spec, validate_spec  # noqa: E402

#: 仓库根目录（tools/forest_generator/main.py → 上溯两级）
REPO_ROOT = Path(__file__).resolve().parents[2]
#: 黄金向量文件（Python 与 GDScript 两侧共用的契约）
GOLDEN_PATH = REPO_ROOT / "game" / "tests" / "fixtures" / "seed_golden.json"

#: §3.4 的工具提示：world 段在 v1 不参与生成
WORLD_HINT = "提示：world 段在 v1 不参与生成（§3.4），改动其数值不会影响运行时地形。"


def _cmd_validate(path_text: str) -> int:
    """校验 SceneSpec：合法退出 0 并打印 OK，非法退出 1 并逐条打印 error/warning。"""
    path = Path(path_text)
    try:
        spec = load_spec(path)
    except OSError as exc:
        print(f"[error] 读取失败：{path}：{exc}", file=sys.stderr)
        return 2
    except json.JSONDecodeError as exc:
        print(f"[error] JSON 解析失败：{path}：{exc}", file=sys.stderr)
        return 2

    issues = validate_spec(spec)
    errors = [issue for issue in issues if issue["level"] == "error"]
    warnings = [issue for issue in issues if issue["level"] == "warning"]

    if errors:
        for issue in errors:
            print(format_issue(issue))
        for issue in warnings:
            print(format_issue(issue))
        print(f"FAILED: {len(errors)} error(s), {len(warnings)} warning(s)")
        return 1

    print("OK")
    for issue in warnings:
        print(format_issue(issue))
    print(WORLD_HINT)
    return 0


def _cmd_keys() -> int:
    """打印 §4.1 的 29 键表（含运行时接缝）。"""
    header = ("键", "类别", "接缝", "变体")
    rows = [
        (
            key,
            asset_keys.KEY_INFO[key]["category"],
            asset_keys.KEY_INFO[key]["seam"],
            asset_keys.KEY_INFO[key]["variant"],
        )
        for key in asset_keys.ASSET_KEYS
    ]
    widths = [
        max(len(str(cell)) for cell in column)
        for column in zip(header, *rows)
    ]
    print("  ".join(cell.ljust(width) for cell, width in zip(header, widths)))
    print("  ".join("-" * width for width in widths))
    for row in rows:
        print("  ".join(str(cell).ljust(width) for cell, width in zip(row, widths)))
    print(f"共 {len(asset_keys.ASSET_KEYS)} 个键：植被 {len(asset_keys.VEGETATION_KEYS)} 个 + "
          f"道具 {len(asset_keys.PROP_KEYS)} 个")
    print(f"接缝分布：mesh_for {len(asset_keys.keys_by_seam(asset_keys.SEAM_MESH_FOR))} 个 / "
          f"make_prop {len(asset_keys.keys_by_seam(asset_keys.SEAM_MAKE_PROP))} 个")
    return 0


def _cmd_derive_seeds(base_seed: int) -> int:
    """打印所有键的派生种子（§5.2）。"""
    print(f"base_seed = {base_seed}")
    for key in asset_keys.ASSET_KEYS:
        print(f"{key:<14} {seed.derive_seed(base_seed, key)}")
    return 0


def _cmd_emit_golden() -> int:
    """重新生成黄金向量文件（与既有 fixture 逐字节一致）。"""
    payload = seed.golden_bytes()
    tmp = GOLDEN_PATH.with_name(GOLDEN_PATH.name + ".tmp")
    try:
        with open(tmp, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, GOLDEN_PATH)
    except BaseException:
        if tmp.exists():
            tmp.unlink()
        raise
    print(f"已写出 {GOLDEN_PATH}（{len(payload)} 字节）")
    return 0


def _cmd_check_golden() -> int:
    """比对黄金向量文件与 Python 侧的派生结果。"""
    try:
        actual = GOLDEN_PATH.read_bytes()
    except OSError as exc:
        print(f"[error] 读取失败：{GOLDEN_PATH}：{exc}", file=sys.stderr)
        return 2

    expected = seed.golden_bytes()
    if actual == expected:
        print("OK")
        print(f"黄金向量一致：{GOLDEN_PATH}")
        return 0

    print("[error] 黄金向量与 Python 侧的派生结果不一致", file=sys.stderr)
    try:
        expected_doc = json.loads(expected.decode("utf-8"))
        actual_doc = json.loads(actual.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        print(f"[error] 无法解析 JSON：{exc}", file=sys.stderr)
        return 1
    for field in ("algorithm", "formula", "base_seeds"):
        if expected_doc.get(field) != actual_doc.get(field):
            print(f"[error] 字段 {field} 不一致", file=sys.stderr)
    for field in ("asset_keys", "vegetation_keys", "prop_keys"):
        if expected_doc.get(field) != actual_doc.get(field):
            print(f"[error] 字段 {field} 不一致", file=sys.stderr)
    for field in ("vectors", "edge_cases"):
        exp_list = expected_doc.get(field) or []
        act_list = actual_doc.get(field) or []
        if exp_list == act_list:
            continue
        print(f"[error] 字段 {field} 不一致：期望 {len(exp_list)} 条，实际 {len(act_list)} 条",
              file=sys.stderr)
        for index, (exp_item, act_item) in enumerate(zip(exp_list, act_list)):
            if exp_item != act_item:
                print(f"[error]   第 {index} 条：期望 {exp_item}，实际 {act_item}", file=sys.stderr)
                break
    return 1


def _cmd_build(
    spec_path_text: str,
    keys_text: str | None,
    out_text: str | None,
    generated_at: str | None,
) -> int:
    """构建资产：SceneSpec → 形态参数 → Blender → GLB → manifest。

    产物先落在 tools/forest_generator/output/ 的暂存目录，全部成功后才装进
    game/assets/generated/，并且 manifest 最后写——中途失败不会破坏上一版有效产物。
    """
    from datetime import datetime, timezone

    from lib import build as build_lib

    spec_path = Path(spec_path_text)
    try:
        spec = load_spec(spec_path)
    except OSError as exc:
        print(f"[error] 读取失败：{spec_path}：{exc}", file=sys.stderr)
        return 2
    except json.JSONDecodeError as exc:
        print(f"[error] JSON 解析失败：{spec_path}：{exc}", file=sys.stderr)
        return 2

    issues = validate_spec(spec)
    errors = [issue for issue in issues if issue["level"] == "error"]
    if errors:
        for issue in errors:
            print(format_issue(issue))
        print(f"FAILED: SceneSpec 有 {len(errors)} 个 error，不构建", file=sys.stderr)
        return 1

    if keys_text:
        wanted = [k.strip() for k in keys_text.split(",") if k.strip()]
    else:
        wanted = [k for k in asset_keys.ASSET_KEYS if k.startswith("pine_")]

    region_id = spec.get("region", {}).get("id", "region")
    if out_text:
        target = Path(out_text)
    else:
        target = REPO_ROOT / "game" / "assets" / "generated" / region_id
    staging = REPO_ROOT / "tools" / "forest_generator" / "output" / region_id / "staging"

    try:
        blender = build_lib.find_blender()
    except build_lib.BuildError as exc:
        print(f"[error] {exc}", file=sys.stderr)
        return 2

    stamp = generated_at or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"Blender：{blender}")
    print(f"构建资产：{', '.join(wanted)}")

    try:
        manifest = build_lib.build_assets(
            spec=spec,
            keys=wanted,
            blender=blender,
            staging=staging,
            target=target,
            generated_at=stamp,
        )
    except build_lib.BuildError as exc:
        print(f"[error] {exc}", file=sys.stderr)
        return 1

    totals = manifest["totals"]
    print(
        f"完成：{totals['assets']} 个资产 / {totals['files']} 个文件 / "
        f"{totals['bytes']} 字节 / LOD0 三角面 {totals['tris_lod0']}"
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    """命令行参数解析器。"""
    parser = argparse.ArgumentParser(
        prog="forest_generator",
        description="森林生成管线工具链（M3）",
    )
    parser.add_argument("--validate", metavar="SPEC", help="校验 SceneSpec 文件")
    parser.add_argument("--keys", action="store_true", help="打印 29 个资产键及其运行时接缝")
    parser.add_argument(
        "--derive-seeds", metavar="BASE_SEED", type=int, help="打印所有键的派生种子"
    )
    parser.add_argument(
        "--emit-golden", action="store_true", help="重新生成黄金向量文件"
    )
    parser.add_argument(
        "--check-golden", action="store_true", help="比对黄金向量文件（自检）"
    )
    parser.add_argument(
        "--build",
        action="store_true",
        help="构建资产：SceneSpec → Blender → GLB → manifest（M3-2）",
    )
    parser.add_argument(
        "--spec",
        metavar="SPEC",
        default=str(REPO_ROOT / "tools" / "forest_generator" / "presets" / "pine_valley.json"),
        help="--build 使用的 SceneSpec（默认 pine_valley.json）",
    )
    parser.add_argument(
        "--build-keys",
        metavar="KEYS",
        default=None,
        help="--build 要构建的资产键，逗号分隔（默认全部 pine_*）",
    )
    parser.add_argument(
        "--out",
        metavar="DIR",
        default=None,
        help="--build 的产物目录（默认 game/assets/generated/<region_id>）",
    )
    parser.add_argument(
        "--generated-at",
        metavar="ISO",
        default=None,
        help="--build 写入 manifest 的时间戳（默认当前 UTC 时间）",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """命令行入口。"""
    parser = build_parser()
    args = parser.parse_args(argv)

    handled = False
    exit_code = 0
    if args.validate:
        handled = True
        exit_code = _cmd_validate(args.validate)
    if args.keys:
        handled = True
        exit_code = _cmd_keys() or exit_code
    if args.derive_seeds is not None:
        handled = True
        exit_code = _cmd_derive_seeds(args.derive_seeds) or exit_code
    if args.emit_golden:
        handled = True
        exit_code = _cmd_emit_golden() or exit_code
    if args.check_golden:
        handled = True
        exit_code = _cmd_check_golden() or exit_code
    if args.build:
        handled = True
        exit_code = _cmd_build(
            args.spec, args.build_keys, args.out, args.generated_at
        ) or exit_code

    if not handled:
        parser.print_help()
        return 2
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
