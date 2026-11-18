class_name SeedUtil
extends RefCounted
## 种子派生（FNV-1a 32 位），对应 docs/forest-pipeline-spec.md §5.2。
##
## 与 tools/forest_generator/lib/seed.py 是同一算法的两份实现，
## 黄金向量在 game/tests/fixtures/seed_golden.json，两侧各自复现它。
## 改了这里的算法，必须同步改 Python 侧并重新生成黄金向量。
##
## 确定性要求：同一 base_seed + 同一 key → 永远同一个种子。
## 资产形态的随机数一律从这里派生，不依赖遍历顺序或任何隐式状态。

const FNV_OFFSET := 16777619
const MASK := 0xFFFFFFFF
const MOD := 2147483647


## 从世界种子与资产键派生该资产的形态种子。
##
## base_seed 会被当作无符号 32 位处理，key 按 UTF-8 逐字节参与运算。
## 返回值落在 [1, 2147483647]，避免 0 与负数。
static func derive_seed(base_seed: int, key: String) -> int:
	var state := base_seed & MASK
	for b in key.to_utf8_buffer():
		state = ((state ^ b) * FNV_OFFSET) & MASK
	return (state % MOD) + 1


## 批量派生，返回 {key: seed} 字典。
static func derive_seeds(base_seed: int, keys: PackedStringArray) -> Dictionary:
	var result := {}
	for key in keys:
		result[key] = derive_seed(base_seed, key)
	return result
