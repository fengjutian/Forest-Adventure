class_name TerrainField
extends RefCounted
## 全局地形高度场（docs/technical-design.md §5.1）。
##
## 整片 1 km × 1 km 区域由**同一个高度函数**描述：
## 分块网格、植被落地、玩家贴地、敌人落地全部调用 height_at()，
## 因此相邻区块在边界上取到的是同一组采样点，接缝不可能裂开。
##
## 地形由四层叠加：
##  - 基础起伏（中频噪声，森林的缓坡）
##  - 大尺度地貌（低频噪声，远处的山体）
##  - 主山脊（北侧一条东西向长山脊，全图的方位地标）
##  - 细节（高频噪声，脚感）
## 然后在溪谷处下切、在营地处压平。

## 默认世界种子。存档里记录实际使用的种子。
const DEFAULT_SEED := 20261117
const DEFAULT_SIZE := 1024.0

var world_seed: int = DEFAULT_SEED
var world_size: float = DEFAULT_SIZE

## 基础起伏：森林里的缓坡。
var amplitude: float = 7.0
## 大尺度地貌：远处山体的高度。
var macro_amplitude: float = 26.0
## 细节起伏。
var detail_amplitude: float = 1.4

## 主山脊：z = ridge_center_z 附近的一条东西向长脊。
var ridge_center_z: float = -390.0
var ridge_width: float = 150.0
var ridge_height: float = 52.0
## 西侧次峰，用来打破东南西北的单调。
var hill_center: Vector2 = Vector2(-330.0, -140.0)
var hill_height: float = 34.0
var hill_width: float = 120.0

## 溪谷：沿 Z 方向贯穿全图，营地里那条溪就是它的一段。
var creek_center_x: float = 11.0
var creek_half_width: float = 2.4
var creek_depth: float = -1.15

## 营地平整区：以原点为中心的圆形平台。
var camp_flat_radius: float = 15.0
var camp_blend_radius: float = 24.0
var camp_height: float = 0.0

var _base_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _macro_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _density_noise: FastNoiseLite


func _init(seed_value: int = DEFAULT_SEED, size: float = DEFAULT_SIZE) -> void:
	world_seed = seed_value
	world_size = size
	set_seed(seed_value)


## 换种子：所有噪声重新初始化。换种子后必须重建全部区块。
func set_seed(seed_value: int) -> void:
	world_seed = seed_value

	_base_noise = FastNoiseLite.new()
	_base_noise.seed = world_seed
	_base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_base_noise.frequency = 0.012
	_base_noise.fractal_octaves = 4
	_base_noise.fractal_lacunarity = 2.0

	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = world_seed + 977
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail_noise.frequency = 0.055
	_detail_noise.fractal_octaves = 3

	_macro_noise = FastNoiseLite.new()
	_macro_noise.seed = world_seed + 4211
	_macro_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_macro_noise.frequency = 0.0028
	_macro_noise.fractal_octaves = 3

	_ridge_noise = FastNoiseLite.new()
	_ridge_noise.seed = world_seed + 7331
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge_noise.frequency = 0.006
	_ridge_noise.fractal_octaves = 2

	# 植被密度的低频噪声：跨区块共享，密度才不会在块边界突变
	_density_noise = FastNoiseLite.new()
	_density_noise.seed = world_seed + 313
	_density_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_density_noise.frequency = 0.035
	_density_noise.fractal_octaves = 3


## 世界坐标处的地面高度。这是全局唯一的高度真相。
func height_at(x: float, z: float) -> float:
	var h := _base_noise.get_noise_2d(x, z) * amplitude
	h += _detail_noise.get_noise_2d(x, z) * detail_amplitude

	# 溪谷两侧 30 m 内不抬升地貌：河谷是一条贯穿全图的平缓走廊，
	# 远处山体只在离开河谷后升起。没有这道门，溪流会变成一条深峡谷。
	var gate := smoothstep(creek_center_x + 30.0, creek_center_x + 150.0, absf(x - creek_center_x))

	if gate > 0.0:
		var macro := _macro_noise.get_noise_2d(x, z) * macro_amplitude
		# 主山脊：沿 X 方向延伸，山脊线本身有噪声起伏，不是一条直线
		var ridge_d := z - ridge_center_z
		var ridge := ridge_height * exp(-(ridge_d * ridge_d) / (2.0 * ridge_width * ridge_width))
		ridge *= 0.75 + 0.25 * _ridge_noise.get_noise_2d(x, z)
		# 西侧次峰
		var hill_d := Vector2(x, z) - hill_center
		var hill := hill_height * exp(-(hill_d.length_squared()) / (2.0 * hill_width * hill_width))
		h += (macro + ridge + hill) * gate

	# 溪谷下切：横断面平滑衰减，河床取固定高度
	var creek_distance := absf(x - creek_center_x)
	if creek_distance < creek_half_width * 2.2:
		var t := 1.0 - clampf(creek_distance / (creek_half_width * 2.2), 0.0, 1.0)
		h = lerpf(h, creek_depth, t * t * (3.0 - 2.0 * t))

	# 营地平整：中心完全水平，向外平滑过渡
	var camp_distance := Vector2(x, z).length()
	if camp_distance < camp_blend_radius:
		var t := 1.0 - clampf(
			(camp_distance - camp_flat_radius) / maxf(camp_blend_radius - camp_flat_radius, 0.001),
			0.0, 1.0
		)
		h = lerpf(h, camp_height, t * t * (3.0 - 2.0 * t))

	return h


## 用中心差分求法线。step 与网格步长一致时，结果与网格法线一致。
func normal_at(x: float, z: float, step: float = 1.0) -> Vector3:
	var h_left := height_at(x - step, z)
	var h_right := height_at(x + step, z)
	var h_down := height_at(x, z - step)
	var h_up := height_at(x, z + step)
	return Vector3(h_left - h_right, 2.0 * step, h_down - h_up).normalized()


## 坡度：0 为水平，1 为垂直。
func slope_at(x: float, z: float, step: float = 1.2) -> float:
	return 1.0 - normal_at(x, z, step).y


## 地形顶点色：高度、坡度、溪谷与营地共同决定。
func color_at(x: float, z: float, height: float, slope: float) -> Color:
	var grass := Color(0.19, 0.29, 0.15)
	var deep_grass := Color(0.12, 0.2, 0.11)
	var dirt := Color(0.34, 0.27, 0.18)
	var gravel := Color(0.4, 0.38, 0.34)
	var rock := Color(0.38, 0.38, 0.36)

	# 高处林线更深沉
	var color := grass.lerp(deep_grass, clampf(height / (amplitude * 0.8), 0.0, 1.0))

	# 溪谷河床常年被水冲刷，露土露砂。
	# 只对溪流附近生效：1 km 世界里大量低洼地是正常林地，不能一律染成河床。
	var creek_distance := absf(x - creek_center_x)
	var creek_mask := 1.0 - smoothstep(creek_half_width * 0.5, creek_half_width * 2.8, creek_distance)
	if height < -0.35 and creek_mask > 0.0:
		var gravel_amount := clampf((-height - 0.35) / 0.8, 0.0, 1.0) * creek_mask
		color = color.lerp(gravel, gravel_amount)

	# 高出林线后露岩
	if height > macro_amplitude * 0.55:
		color = color.lerp(rock, clampf((height - macro_amplitude * 0.55) / (macro_amplitude * 0.6), 0.0, 1.0))

	# 营地是被踩实的空地
	var camp_distance := Vector2(x, z).length()
	if camp_distance < camp_flat_radius:
		var wear := 1.0 - camp_distance / camp_flat_radius
		color = color.lerp(dirt, 0.55 * wear * wear)

	# 陡坡露岩
	if slope > 0.35:
		color = color.lerp(rock, clampf((slope - 0.35) / 0.45, 0.0, 1.0))

	return color


## 植被密度。低频噪声 + 靠近世界边缘变稀，跨区块连续。
func vegetation_density(x: float, z: float, max_density: float) -> float:
	var noise := _density_noise.get_noise_2d(x, z) * 0.5 + 0.5
	var half := world_size * 0.5
	var border := clampf(minf(half - absf(x), half - absf(z)) / 60.0, 0.0, 1.0)
	return clampf(max_density * noise * (0.35 + 0.65 * border), 0.0, 1.0)


func is_inside(x: float, z: float) -> bool:
	var half := world_size * 0.5
	return absf(x) <= half and absf(z) <= half
