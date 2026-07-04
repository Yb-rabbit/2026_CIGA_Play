extends Node
## ============================================================
## OnboardSystem — 飞船飞控电脑
## 挂载于 OnboardSystem 场景节点，负责：
##   1. 油门持续监测 → 过热警告 / 保底推力限制
##   2. 状态指示灯（status_label）
##   3. 信号广播：overheat_warning / thrust_limited
## ============================================================

# ==================== 信号 ====================
## 过热警告信号：is_overheating=true 表示进入警告，false 表示解除
signal overheat_warning(is_overheating: bool)
## 推力限制信号：is_limited=true 表示推力被强制衰减，false 表示恢复正常
signal thrust_limited(is_limited: bool)

# ==================== 导出节点引用 ====================
## 状态指示灯 Label，由场景中拖入或脚本赋值
@export var status_label: Label = null

# ==================== 过热保护常量 ====================
const OVERHEAT_WARN_TIME: float = 1.5         ## 持续按住 W 超过此秒数 → 触发过热警告
const OVERHEAT_LIMIT_TIME: float = 2.5        ## 持续按住 W 超过此秒数 → 触发保底推力限制
const COOLDOWN_TIME: float = 0.5              ## 松开 W 后恢复正常的冷却秒数
const LIMITED_THRUST_RATIO: float = 0.6       ## 限制期间推力衰减至 60%
const LIMITED_FUEL_BURN_RATIO: float = 1.2    ## 限制期间油耗提升至 120%（模拟引擎低效空转）

# ==================== 内部状态 ====================
var _w_held_time: float = 0.0                 ## W 键累计按住时间（秒）
var _cooldown_timer: float = 0.0              ## 松开 W 后冷却计时器
var _is_warning: bool = false                 ## 当前是否处于过热警告状态
var _is_limited: bool = false                 ## 当前是否处于推力限制状态
var _was_held_last_frame: bool = false        ## 上一帧是否按住 W

# ==================== 公开属性（GameScene 每帧查询） ====================
## 当前推力倍率（GameScene 中用 THRUST * thrust_multiplier 得到实际推力）
var thrust_multiplier: float = 1.0
## 当前油耗倍率（GameScene 中用 FUEL_BURN * fuel_burn_multiplier 得到实际油耗）
var fuel_burn_multiplier: float = 1.0


# ============================================================
# _ready
# ============================================================
func _ready() -> void:
	# 确保此节点参与物理帧处理
	set_physics_process(true)
	_update_status_label()


# ============================================================
# _physics_process — 每物理帧检测油门状态
# ============================================================
func _physics_process(delta: float) -> void:
	var w_held: bool = Input.is_action_pressed("ui_up")

	if w_held:
		# ---- W 键按住中 ----
		# 如果上一帧未按住（刚按下），重置冷却计时器
		if not _was_held_last_frame:
			_cooldown_timer = 0.0

		# 累计按住时间
		_w_held_time += delta

		# 阶段 A：持续按住 ≥ 3 秒 → 触发过热警告
		if _w_held_time >= OVERHEAT_WARN_TIME and not _is_warning:
			_is_warning = true
			overheat_warning.emit(true)

		# 阶段 B：持续按住 ≥ 5 秒 → 触发保底推力限制
		if _w_held_time >= OVERHEAT_LIMIT_TIME and not _is_limited:
			_is_limited = true
			thrust_multiplier = LIMITED_THRUST_RATIO
			fuel_burn_multiplier = LIMITED_FUEL_BURN_RATIO
			thrust_limited.emit(true)

	else:
		# ---- W 键松开中 ----
		if _was_held_last_frame or _w_held_time > 0.0:
			# 从按住变为松开，或之前有累计时间 → 进入冷却倒计时
			_cooldown_timer += delta

			# 冷却完成（松开 ≥ 0.5 秒）→ 全部复位
			if _cooldown_timer >= COOLDOWN_TIME:
				_reset_overheat()

	_was_held_last_frame = w_held

	_update_status_label()


# ============================================================
# 复位所有过热状态
# ============================================================
func _reset_overheat() -> void:
	_w_held_time = 0.0
	_cooldown_timer = 0.0

	# 如果之前处于限制状态，发送解除信号并恢复倍率
	if _is_limited:
		_is_limited = false
		thrust_multiplier = 1.0
		fuel_burn_multiplier = 1.0
		thrust_limited.emit(false)

	# 如果之前处于警告状态，发送解除信号
	if _is_warning:
		_is_warning = false
		overheat_warning.emit(false)


# ============================================================
# 状态指示灯
# ============================================================
func _update_status_label() -> void:
	if status_label == null:
		return

	if _is_limited:
		# 推力限制中 — 红色警告
		status_label.text = "动力限制中"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1, 1.0))

	elif _is_warning:
		# 引擎过热警告 — 显示当前热度百分比（相对 5 秒上限）
		var pct: int = int(clampf(_w_held_time / OVERHEAT_LIMIT_TIME, 0.0, 1.0) * 100.0)
		status_label.text = "引擎过热（%d%%）" % pct
		status_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.1, 1.0))

	else:
		# 正常巡航
		status_label.text = "巡航中"
		status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5, 1.0))