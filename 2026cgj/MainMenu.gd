extends Control
## ============================================================
## MainMenu — 标题页
## 纯代码构建所有 UI 元素，不依赖外部素材
## 含不可控漂浮飞船背景动效
## ============================================================

# ==================== 字体 ====================
var _font: Font

# ==================== 背景动效 ====================
var _ship_pos: Vector2 = Vector2.ZERO       # 飞船坐标
var _ship_angle: float = 0.0                # 飞船旋转角度
var _ship_t: float = 0.0                    # Lissajous 参数 t
var _title_label: Label = null
var _trail_points: Array[Vector2] = []      # 飞船尾迹点（最多 40 个）
const MAX_TRAIL: int = 40

# 搜索圈参数
var _zone_centers: Array[Vector2] = []       # 3 个搜索圈中心
var _zone_velocities: Array[Vector2] = []     # 每个圈的速度
var _zone_radius: float = 180.0
var _zone_alpha: float = 0.0                 # 搜索圈闪烁相位
const ZONE_SPEED: float = 25.0               # 搜索圈移动速度 (px/s)

# 状态文本参数
var _status_texts: Array[String] = ["巡航中", "引擎过热（43%）", "动力限制中", "信号锁定"]
var _status_index: int = 0
var _status_hold: float = 0.0                # 当前状态停留时间
var _status_flash: float = 0.0               # 文本闪烁相位
var _status_label: Label = null              # 状态文本子节点
var _tooltip_label: Label = null             # 搜索圈悬停提示
var _inside_circle: int = -1                 # 当前悬停在哪个圈上（-1=无）


# ==================== _ready — 构建主菜单 ====================
func _ready() -> void:
	# 全屏铺满
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	# 加载项目字体
	_font = load("res://YuFanDanQingSong.otf") as Font

	# 初始化飞船位置（屏幕中间偏右）
	var vs := get_viewport().get_visible_rect().size
	_ship_pos = Vector2(vs.x * 0.55, vs.y * 0.55)
	_ship_t = randf_range(0.0, TAU)

	# 生成 3 个搜索圈随机位置（避开标题/按钮区域）
	for i: int in range(3):
		_zone_centers.append(Vector2(
			randf_range(vs.x * 0.15, vs.x * 0.85),
			randf_range(vs.y * 0.12, vs.y * 0.55)
		))
		var ang: float = randf_range(0.0, TAU)
		_zone_velocities.append(Vector2(cos(ang), sin(ang)) * ZONE_SPEED)

	_status_index = randi_range(0, _status_texts.size() - 1)

	set_process(true)

	# ---- 游戏标题 ----
	var title := Label.new()
	title.name = "Title"
	title.text = "Blind Flight Rescue"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0, 1.0))
	title.add_theme_font_override("font", _font)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-400, 240)
	title.size = Vector2(800, 100)
	add_child(title)
	_title_label = title

	# ---- 副标题 ----
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "盲飞救援"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 36)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9, 0.7))
	subtitle.add_theme_font_override("font", _font)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	subtitle.position = Vector2(-400, 380)
	subtitle.size = Vector2(800, 60)
	add_child(subtitle)

	# ---- "开始游戏" 按钮 ----
	var start_btn := _make_button("开始游戏", _on_start_game)
	start_btn.position = Vector2(
		(get_viewport().get_visible_rect().size.x - 320) / 2.0,
		640.0
	)
	add_child(start_btn)

	# ---- 搜索圈悬停提示 ----
	_tooltip_label = Label.new()
	_tooltip_label.name = "TooltipLabel"
	_tooltip_label.text = ""
	_tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip_label.add_theme_font_size_override("font_size", 24)
	_tooltip_label.add_theme_font_override("font", _font)
	_tooltip_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0, 1.0))
	_tooltip_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_tooltip_label.position = Vector2(-300, 560)
	_tooltip_label.size = Vector2(600, 30)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tooltip_label)

	# ---- 状态文本指示器 ----
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 28)
	_status_label.add_theme_font_override("font", _font)
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_status_label.position = Vector2(-300, -50)
	_status_label.size = Vector2(600, 30)
	add_child(_status_label)

	# ---- "退出游戏" 按钮 ----
	var exit_btn := _make_button("退出游戏", _on_exit_game)
	exit_btn.position = Vector2(
		(get_viewport().get_visible_rect().size.x - 320) / 2.0,
		740.0
	)
	exit_btn.modulate = Color(0.8, 0.6, 0.6, 1.0)
	add_child(exit_btn)

	# 背景音乐（原版曲目，主菜单专用）
	_build_menu_bgm()


# ============================================================
# _process — 驱动飞船动效
# ============================================================
func _process(delta: float) -> void:
	# 标题呼吸
	if _title_label != null:
		var breath: float = sin(Time.get_ticks_msec() * 0.001) * 0.06 + 0.94
		_title_label.modulate.a = breath

	# Lissajous 飞船轨迹
	var vs := get_viewport().get_visible_rect().size
	var cx: float = vs.x * 0.5
	var cy: float = vs.y * 0.45
	var rx: float = vs.x * 0.32
	var ry: float = vs.y * 0.28
	_ship_t += delta * 0.35  # 缓慢移动

	_ship_pos = Vector2(cx + cos(_ship_t * 1.3) * rx, cy + sin(_ship_t) * ry)
	_ship_angle = atan2(-cos(_ship_t * 1.3) * rx, cos(_ship_t) * ry * 1.3)

	# 尾迹记录
	_trail_points.append(_ship_pos)
	while _trail_points.size() > MAX_TRAIL:
		_trail_points.pop_front()

	# 搜索圈呼吸 + 移动
	_zone_alpha += delta * 0.6
	if _zone_alpha > TAU:
		_zone_alpha -= TAU

	# 移动每个搜索圈（在边界内反弹）
	var vs2 := get_viewport().get_visible_rect().size
	var margin: float = _zone_radius + 20.0
	for i: int in range(_zone_centers.size()):
		var pos: Vector2 = _zone_centers[i]
		var vel: Vector2 = _zone_velocities[i]
		pos += vel * delta
		# 边界反弹
		if pos.x < margin:
			pos.x = margin
			vel.x = absf(vel.x)
		elif pos.x > vs2.x - margin:
			pos.x = vs2.x - margin
			vel.x = -absf(vel.x)
		if pos.y < margin:
			pos.y = margin
			vel.y = absf(vel.y)
		elif pos.y > vs2.y - margin:
			pos.y = vs2.y - margin
			vel.y = -absf(vel.y)
		_zone_centers[i] = pos
		_zone_velocities[i] = vel

	# 状态文本切换 + 闪烁
	_status_hold -= delta
	if _status_hold <= 0.0:
		_status_index = (_status_index + 1) % _status_texts.size()
		_status_hold = randf_range(2.0, 3.5)

	# 更新状态文本 Label
	if _status_label != null:
		var st: String = _status_texts[_status_index]
		_status_label.text = st
		var flash_a: float = absf(sin(_status_flash)) * 0.4 + 0.3
		_status_flash += delta * 5.0

		if st == "巡航中":
			_status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5, flash_a))
		elif st == "引擎过热（43%）":
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.1, flash_a))
		elif st == "动力限制中":
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1, flash_a))
		elif st == "信号锁定":
			_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, flash_a))

	# 检测鼠标是否在某个搜索圈内
	_inside_circle = -1
	var mp: Vector2 = get_local_mouse_position()
	for i: int in range(_zone_centers.size()):
		if mp.distance_to(_zone_centers[i]) < _zone_radius:
			_inside_circle = i
			break

	# 更新悬停提示
	if _tooltip_label != null:
		if _inside_circle >= 0:
			const TIPS: Array[String] = [
				"进入信号搜索区后，按住 W 键进行扫描。",
				"搜索圈中有概率发现遇险信标的坐标。",
				"扫描完毕若为空，声呐雷达将自动报告。",
			]
			_tooltip_label.text = TIPS[_inside_circle]
			_tooltip_label.visible = true
		else:
			_tooltip_label.visible = false

	queue_redraw()


func _draw() -> void:
	# 纯黑背景（必须在 _draw 中绘制，避免遮盖飞船）
	var vs2 := get_viewport().get_visible_rect().size
	draw_rect(Rect2(0, 0, vs2.x, vs2.y), Color.BLACK)

	# 绘制星空背景（静态）
	var t: float = Time.get_ticks_msec() * 0.001
	for i: int in range(40):
		var sx: float = hash(float(i)) * 1600.0
		var sy: float = hash(float(i + 100)) * 1000.0
		var flicker: float = absf(sin(t * 0.5 + float(i))) * 0.3 + 0.4
		draw_circle(Vector2(sx, sy), 1.2, Color(0.6, 0.75, 1.0, flicker * 0.4))

	# 绘制尾迹
	for idx: int in range(_trail_points.size()):
		var pt: Vector2 = _trail_points[idx]
		var alpha: float = float(idx) / float(MAX_TRAIL) * 0.12
		draw_circle(pt, 2.0 + alpha * 6.0, Color(0.2, 0.4, 0.8, alpha))

	# 绘制飞船（白色三角形 + 淡蓝尾焰）
	var s := _ship_pos
	var a := _ship_angle
	var fwd := Vector2(cos(a), sin(a))
	var side := Vector2(-sin(a), cos(a))

	var pts := PackedVector2Array([
		s + fwd * 18.0,
		s - fwd * 10.0 + side * 9.0,
		s - fwd * 6.0,
		s - fwd * 10.0 - side * 9.0,
	])
	draw_colored_polygon(pts, Color(0.85, 0.92, 1.0, 0.9))

	# 尾焰
	var flame_pts := PackedVector2Array([
		s - fwd * 10.0,
		s - fwd * 24.0 + side * 5.0,
		s - fwd * 24.0 - side * 5.0,
	])
	draw_colored_polygon(flame_pts, Color(1.0, 0.5, 0.1, 0.55))

	# ---- 绘制搜索圈（半透明蓝色圆环） ----
	for i: int in range(_zone_centers.size()):
		var zc: Vector2 = _zone_centers[i]
		var pulse: float = sin(_zone_alpha + float(i) * 1.7) * 0.07 + 0.07
		const SEG := 64
		var ring_pts := PackedVector2Array()
		for j: int in range(SEG + 1):
			var ra: float = TAU * float(j) / float(SEG)
			ring_pts.append(zc + Vector2(cos(ra), sin(ra)) * _zone_radius)

		draw_colored_polygon(ring_pts, Color(0.1, 0.4, 0.8, 0.04 + pulse))
		draw_polyline(ring_pts + PackedVector2Array([Vector2(cos(0), sin(0)) * _zone_radius]), Color(0.2, 0.6, 1.0, 0.25 + pulse * 2.0), 1.5)

	# ---- 绘制闪烁状态文本 ----
	_status_flash += 0.02
	var st: String = _status_texts[_status_index]
	var flash_a: float = absf(sin(_status_flash)) * 0.4 + 0.3
	var st_color: Color = Color(0.3, 0.9, 0.5, flash_a)
	if st == "引擎过热（43%）":
		st_color = Color(1.0, 0.7, 0.1, flash_a)
	elif st == "动力限制中":
		st_color = Color(1.0, 0.2, 0.1, flash_a)
	elif st == "信号锁定":
		st_color = Color(0.3, 1.0, 0.4, flash_a)

	# 用简单方式绘制文本（_draw 不支持文字，用 Control 的Label 更合适）
	# 改用子节点 Label 来实现——在 _ready 中创建并在 _process 中更新
	# 这里仅绘制一个底部提示色条
	var bar_y: float = vs2.y - 46
	draw_rect(Rect2(0, bar_y, vs2.x, 2), Color(0.15, 0.35, 0.7, 0.2))


func hash(v: float) -> float:
	return fmod(absf(v * 2654435761.0), 1.0)


# ============================================================
# 按钮工厂
# ============================================================
func _make_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size = Vector2(320, 64)
	btn.add_theme_font_size_override("font_size", 32)
	btn.add_theme_font_override("font", _font)
	btn.add_theme_color_override("font_color", Color.WHITE)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.08, 0.12, 0.22, 0.9)
	normal_style.border_width_left = 2
	normal_style.border_width_right = 2
	normal_style.border_width_top = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = Color(0.3, 0.7, 1.0, 0.6)
	normal_style.corner_radius_top_left = 8
	normal_style.corner_radius_top_right = 8
	normal_style.corner_radius_bottom_left = 8
	normal_style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.12, 0.18, 0.32, 0.95)
	hover_style.border_color = Color(0.5, 0.9, 1.0, 0.9)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.2, 0.3, 0.45, 0.95)
	pressed_style.border_color = Color(0.2, 0.5, 0.8, 0.7)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.pressed.connect(callback)
	return btn


func _on_start_game() -> void:
	GameManager.change_scene("LevelSelect")


func _on_exit_game() -> void:
	get_tree().quit()


func _build_menu_bgm() -> void:
	if not ResourceLoader.exists("res://stage1(dm).ogg"):
		return
	var bgm := AudioStreamPlayer.new()
	bgm.name = "MenuBGM"
	bgm.bus = "Master"
	bgm.volume_db = -6.0
	bgm.stream = load("res://stage1(dm).ogg")
	bgm.finished.connect(bgm.play)
	add_child(bgm)
	bgm.play()