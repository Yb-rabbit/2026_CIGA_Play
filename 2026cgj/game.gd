extends Node2D
## ============================================================
## Blind Flight Rescue — 盲飞救援
## 单脚本 Godot 4 游戏 | 纯代码构建所有视觉元素
## ============================================================

# ==================== 游戏状态 ====================
var fuel: float = 100.0
var fuel_max: float = 100.0
const FUEL_BURN: float = 12.0             # W 键每秒油耗
const FUEL_REFILL: float = 55.0            # 救援成功回油量
var score: int = 0
var rescue_count: int = 0
var game_over: bool = false
var rescuing: bool = false       # 正在播放救援缩放动画

# ==================== 风场 ====================
var wind_vector: Vector2 = Vector2(50.0, -30.0)  # 初始微风
const BASE_WIND: float = 60.0              # 基础风力

# ==================== 飞行参数 ====================
const THRUST: float = 320.0                # 推进力
const BRAKE: float = 200.0                 # S 键减速力（不耗油）
const ROT_ACCEL: float = 20.0              # 旋转加速度
const ROT_DRAG: float = 0.80               # 旋转惯性衰减
const LIN_DRAG: float = 0.992              # 线性惯性
const MAX_SPD: float = 420.0               # 最大速度

# ==================== 节点 ====================
var player: CharacterBody2D
var body_poly: Polygon2D
var flame_poly: Polygon2D
var anchor: Area2D
var hex_poly: Polygon2D          # 六边形填充（呼吸动效用）
var hex_border: Line2D           # 六边形边框（呼吸动效用）
var rescue_ring: Line2D          # 救援范围圈（可视化）
var camera: Camera2D
var angular_velocity: float = 0.0

# 速度矢量虚线系统
const DASH_COUNT := 8
const DASH_LEN := 10.0
const DASH_GAP := 14.0
const DASH_MAX := 180.0
const DASH_FLOW_SPEED := 90.0   # 流量速率，不随速度变化
var dash_offset: float = 0.0
var trail_node: Node2D

# UI
var compass_needle: Sprite2D
var compass_ripple: Sprite2D     # 罗盘水纹涟漪
var fuel_fill: ColorRect
var score_label: Label
var dist_label: Label
var hint_label: Label
var game_over_label: Label
var signal_label: Label           # 就近信号报告


# ============================================================
# _ready — 构建一切
# ============================================================
func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.02, 0.04, 0.16, 1.0))

	# 创建轨迹绘制节点
	trail_node = Node2D.new()
	trail_node.name = "TrailNode"
	add_child(trail_node)
	trail_node.draw.connect(_draw_trail)

	_build_player()
	_build_camera()
	_build_anchor()
	_build_ui()
	_spawn_anchor()


# ============================================================
# 玩家 (CharacterBody2D + 白色三角 Polygon2D)
# ============================================================
func _build_player() -> void:
	player = CharacterBody2D.new()
	player.name = "Player"
	player.position = Vector2.ZERO
	add_child(player)

	var col_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	col_shape.shape = circle
	player.add_child(col_shape)

	body_poly = Polygon2D.new()
	body_poly.name = "Body"
	body_poly.polygon = PackedVector2Array([
		Vector2(16, 0),
		Vector2(-10, -9),
		Vector2(-6, 0),
		Vector2(-10, 9),
	])
	body_poly.color = Color(0.9, 0.95, 1.0)
	player.add_child(body_poly)

	flame_poly = Polygon2D.new()
	flame_poly.name = "Flame"
	flame_poly.polygon = PackedVector2Array([
		Vector2(-10, -5),
		Vector2(-28, 0),
		Vector2(-10, 5),
	])
	flame_poly.color = Color(1.0, 0.55, 0.1, 0.8)
	flame_poly.visible = false
	player.add_child(flame_poly)


# ============================================================
# 相机 — 跟位置不跟旋转
# ============================================================
func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.enabled = true
	add_child(camera)


# ============================================================
# 信标 (Area2D + 红色六边 Polygon2D + Line2D 框)
# ============================================================
func _build_anchor() -> void:
	anchor = Area2D.new()
	anchor.name = "Anchor"
	add_child(anchor)

	var col_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 48.0
	col_shape.shape = circle
	anchor.add_child(col_shape)

	hex_poly = Polygon2D.new()
	hex_poly.name = "HexBody"
	const R := 22.0
	var pts := PackedVector2Array()
	for i: int in range(6):
		var a: float = i * TAU / 6.0 - PI / 2.0
		pts.append(Vector2(cos(a), sin(a)) * R)
	hex_poly.polygon = pts
	hex_poly.color = Color(1.0, 0.25, 0.2, 0.9)
	anchor.add_child(hex_poly)

	hex_border = Line2D.new()
	hex_border.name = "HexBorder"
	hex_border.width = 1.5
	hex_border.default_color = Color(1.0, 0.9, 0.9, 0.7)
	hex_border.closed = true
	var bpts := PackedVector2Array()
	for i: int in range(7):
		var a: float = (i % 6) * TAU / 6.0 - PI / 2.0
		bpts.append(Vector2(cos(a), sin(a)) * R)
	hex_border.points = bpts
	anchor.add_child(hex_border)

	# 救援范围可视化圈（半径 48，匹配碰撞体，淡蓝色半透明）
	rescue_ring = Line2D.new()
	rescue_ring.name = "RescueRing"
	rescue_ring.width = 1.2
	rescue_ring.default_color = Color(0.3, 0.8, 1.0, 0.35)
	rescue_ring.closed = true
	const SEG := 64
	var rpts := PackedVector2Array()
	for i: int in range(SEG + 1):
		var ra: float = TAU * float(i) / float(SEG)
		rpts.append(Vector2(cos(ra), sin(ra)) * 48.0)
	rescue_ring.points = rpts
	anchor.add_child(rescue_ring)

	anchor.body_entered.connect(_on_rescue)


# ============================================================
# UI (CanvasLayer)
# ============================================================
func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	# ---- 罗盘 (右上) ----
	var cc := Control.new()
	cc.name = "Compass"
	cc.position = Vector2(1280 - 190, 14)
	cc.size = Vector2(190, 190)
	ui.add_child(cc)

	var face := Sprite2D.new()
	face.position = Vector2(95, 95)
	face.texture = _make_compass_tex()
	face.scale = Vector2(1.25, 1.25)
	cc.add_child(face)

	compass_needle = Sprite2D.new()
	compass_needle.position = Vector2(95, 95)
	compass_needle.texture = _make_needle_tex()
	cc.add_child(compass_needle)

	# 水纹涟漪环（搜索动效）
	compass_ripple = Sprite2D.new()
	compass_ripple.name = "Ripple"
	compass_ripple.position = Vector2(95, 95)
	compass_ripple.texture = _make_ripple_tex()
	compass_ripple.visible = false
	cc.add_child(compass_ripple)

	# ---- 油量条 (左上) ----
	var bg := ColorRect.new()
	bg.position = Vector2(20, 20)
	bg.size = Vector2(240, 28)
	bg.color = Color(0.1, 0.1, 0.15, 0.85)
	ui.add_child(bg)

	fuel_fill = ColorRect.new()
	fuel_fill.position = Vector2(24, 24)
	fuel_fill.size = Vector2(232, 20)
	fuel_fill.color = Color(0.2, 0.85, 0.5, 0.9)
	ui.add_child(fuel_fill)

	var fl := Label.new()
	fl.position = Vector2(20, 56)
	fl.text = "FUEL"
	fl.add_theme_font_size_override("font_size", 20)
	fl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.9, 0.8))
	ui.add_child(fl)

	# ---- 分数 ----
	score_label = Label.new()
	score_label.position = Vector2(20, 78)
	score_label.text = "救援: 0"
	score_label.add_theme_font_size_override("font_size", 32)
	score_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 0.9))
	ui.add_child(score_label)

	# ---- 距离 (罗盘下方) ----
	dist_label = Label.new()
	dist_label.position = Vector2(1280 - 190, 210)
	dist_label.size = Vector2(190, 28)
	dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_label.add_theme_font_size_override("font_size", 22)
	dist_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 0.7))
	ui.add_child(dist_label)

	# ---- 就近信号报告 (罗盘下方第二条) ----
	signal_label = Label.new()
	signal_label.position = Vector2(1280 - 190, 240)
	signal_label.size = Vector2(190, 32)
	signal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	signal_label.add_theme_font_size_override("font_size", 24)
	signal_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 0.0))
	signal_label.text = "搜索中..."
	ui.add_child(signal_label)

	# ---- 操作提示 ----
	hint_label = Label.new()
	hint_label.anchors_preset = Control.PRESET_CENTER_BOTTOM
	hint_label.position = Vector2(-280, -36)
	hint_label.size = Vector2(560, 30)
	hint_label.text = "A/D 旋转 | W 加速 | S 减速 | 指针指上 = 对准目标"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 24)
	hint_label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.9, 0.7))
	ui.add_child(hint_label)

	# ---- Game Over ----
	game_over_label = Label.new()
	game_over_label.visible = false
	game_over_label.text = "燃料耗尽...\n按 R 重新开始"
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_label.add_theme_font_size_override("font_size", 64)
	game_over_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	game_over_label.set_anchors_preset(Control.PRESET_CENTER)
	ui.add_child(game_over_label)


# ============================================================
# 程序化纹理
# ============================================================
func _make_compass_tex() -> ImageTexture:
	var s := 150
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(s / 2.0, s / 2.0)
	var r := float(s / 2.0) - 4.0

	for y: int in range(s):
		for x: int in range(s):
			var d: float = Vector2(x, y).distance_to(c)
			if d <= r + 2.0 and d >= r - 3.0:
				img.set_pixel(x, y, Color(0.2, 0.8, 1.0, 0.9))
			elif d < r - 3.0 and d > 5.0:
				img.set_pixel(x, y, Color(0.06, 0.08, 0.16, 0.85))

	var tc := Color(0.3, 0.9, 1.0, 0.95)
	for i: int in range(4):
		var a: float = i * PI / 2.0 - PI / 2.0
		var d := Vector2(cos(a), sin(a))
		_draw_line_on_img(img, c + d * (r - 18.0), c + d * (r - 2.0), 2.5, tc)

	return ImageTexture.create_from_image(img)


func _make_needle_tex() -> ImageTexture:
	const W := 6
	const H := 64
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y: int in range(H):
		for x: int in range(W):
			var rel: float = float(y) / float(H)
			var hw: float = (1.0 - rel) * float(W) / 2.0
			if abs(float(x) - float(W) / 2.0) <= hw:
				var alpha := 1.0 if y < H * 0.92 else 0.3
				img.set_pixel(x, y, Color(1.0, 0.2, 0.15, alpha))
	return ImageTexture.create_from_image(img)


func _make_ripple_tex() -> ImageTexture:
	## 水纹涟漪纹理：透明圆形环，用于搜索雷达扫描
	const S := 180
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(S / 2.0, S / 2.0)
	# 绘制波纹状半透明圆环
	for y: int in range(S):
		for x: int in range(S):
			var d: float = Vector2(x, y).distance_to(c)
			# 外圈粗线
			if d >= 84.0 and d <= 88.0:
				img.set_pixel(x, y, Color(0.2, 0.7, 1.0, 0.4))
	return ImageTexture.create_from_image(img)


func _draw_line_on_img(img: Image, f: Vector2, t: Vector2, th: float, col: Color) -> void:
	var dir := (t - f).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var steps: int = int((t - f).length())
	for i: int in range(steps + 1):
		var p := f + dir * float(i)
		for w: int in range(-int(th), int(th) + 1):
			var px: int = int(p.x + perp.x * float(w))
			var py: int = int(p.y + perp.y * float(w))
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				img.set_pixel(px, py, col)


# ============================================================
# 信标生成
# ============================================================
func _spawn_anchor() -> void:
	var a: float = randf_range(0.0, TAU)
	var d: float = randf_range(300.0, 550.0)
	anchor.global_position = player.global_position + Vector2.RIGHT.rotated(a) * d
	hex_poly.scale = Vector2.ONE
	hex_border.scale = Vector2.ONE
	rescue_ring.scale = Vector2.ONE


# ============================================================
# 救援成功
# ============================================================
func _on_rescue(_b: Node2D) -> void:
	if game_over or rescuing:
		return
	rescuing = true
	rescue_count += 1
	score += int(100 + rescue_count * 15)
	fuel = minf(fuel_max, fuel + FUEL_REFILL)
	score_label.text = "救援: %d" % score

	var na: float = randf_range(0.0, TAU)
	var ns: float = BASE_WIND + float(rescue_count) * 25.0
	wind_vector = Vector2.RIGHT.rotated(na) * ns

	# 缩放消失动画：六边形+边框+救援圈 同时向中心缩至零
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(hex_poly, "scale", Vector2.ZERO, 0.35).set_ease(Tween.EASE_IN)
	tw.tween_property(hex_border, "scale", Vector2.ZERO, 0.35).set_ease(Tween.EASE_IN)
	tw.tween_property(rescue_ring, "scale", Vector2.ZERO, 0.35).set_ease(Tween.EASE_IN)

	# 分数闪烁
	var tw2 := create_tween()
	tw2.tween_property(score_label, "modulate", Color.WHITE, 0.08)
	tw2.tween_property(score_label, "modulate", Color(1.0, 0.9, 0.3, 0.9), 0.25)

	# 动画完成后生成新信标
	tw.finished.connect(_on_rescue_done)


# ============================================================
# Game Over / Restart
# ============================================================
func _game_over() -> void:
	game_over = true
	game_over_label.visible = true
	hint_label.text = "按 R 重新开始"
	flame_poly.visible = false


func _restart() -> void:
	game_over = false
	fuel = fuel_max
	score = 0
	rescue_count = 0
	wind_vector = Vector2(50.0, -30.0)
	player.position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	angular_velocity = 0.0
	player.rotation = 0.0
	score_label.text = "救援: 0"
	game_over_label.visible = false
	hint_label.text = "A/D 旋转 | W 加速 | S 减速 | 指针指上 = 对准目标"
	fuel_fill.color = Color(0.2, 0.85, 0.5, 0.9)
	_spawn_anchor()


# ============================================================
# 主循环
# ============================================================
func _physics_process(delta: float) -> void:
	if game_over:
		_update_compass()
		return

	var ri: float = Input.get_axis("ui_left", "ui_right")
	angular_velocity += ri * ROT_ACCEL * delta
	angular_velocity *= ROT_DRAG
	player.rotation += angular_velocity * delta

	var thrusting: bool = Input.is_action_pressed("ui_up") and fuel > 0.0
	if thrusting:
		player.velocity += Vector2.RIGHT.rotated(player.rotation) * THRUST * delta
		fuel = maxf(0.0, fuel - FUEL_BURN * delta)
		if fuel <= 0.0:
			_game_over()

	if Input.is_action_pressed("ui_down"):
		var spd: float = player.velocity.length()
		if spd > 0.0:
			var force: float = minf(BRAKE * delta, spd)
			player.velocity -= player.velocity.normalized() * force

	player.velocity += wind_vector * delta
	player.velocity *= LIN_DRAG

	var sp: float = player.velocity.length()
	if sp > MAX_SPD:
		player.velocity = player.velocity * (MAX_SPD / sp)

	_animate_hexagon()
	player.move_and_slide()
	_wrap(player)

	flame_poly.visible = thrusting
	if thrusting:
		_anim_flame()

	camera.global_position = player.global_position

	# 速度虚线流动偏移
	dash_offset += DASH_FLOW_SPEED * delta
	if dash_offset > DASH_GAP + DASH_LEN:
		dash_offset -= DASH_GAP + DASH_LEN

	trail_node.queue_redraw()

	_update_compass()
	_update_fuel()


func _process(_delta: float) -> void:
	if Input.is_key_pressed(KEY_R) and game_over:
		_restart()


# ============================================================
# 罗盘更新
# ============================================================
func _update_compass() -> void:
	var to: Vector2 = anchor.global_position - player.global_position
	var dist: float = to.length()
	dist_label.text = "最近距离: %.0f pc" % dist

	if dist > 0.5:
		compass_needle.rotation = to.angle() - player.rotation

	var t: float = clampi(int(dist), 0, 500) / 500.0
	compass_needle.modulate = Color(
		lerpf(0.25, 1.0, 1.0 - t),
		lerpf(0.15, 0.9, 1.0 - t),
		lerpf(0.8, 0.15, 1.0 - t),
		0.95
	)
	var blink: float = sin(Time.get_ticks_msec() * 0.003 * lerpf(0.8, 6.0, 1.0 - t)) * 0.25 + 0.75
	compass_needle.modulate.a *= blink

	# 水纹涟漪：距离越近 → 涟漪越大、透明度越低
	compass_ripple.visible = true
	var ripple_scale: float = lerpf(0.3, 1.1, 1.0 - t)  # 远=小圈, 近=大圈扩展
	var ripple_alpha: float = lerpf(0.05, 0.5, 1.0 - t)  # 远=极淡, 近=清晰
	compass_ripple.scale = Vector2(ripple_scale, ripple_scale)
	compass_ripple.modulate.a = ripple_alpha
	# 缓慢旋转涟漪
	compass_ripple.rotation += 0.008

	_update_signal_report(dist)


# ============================================================
# 油量条
# ============================================================
func _update_fuel() -> void:
	var r: float = fuel / fuel_max
	fuel_fill.size.x = 232.0 * r
	if r > 0.4:
		fuel_fill.color = Color(0.2, 0.85, 0.5, 0.9)
	elif r > 0.15:
		fuel_fill.color = Color(1.0, 0.7, 0.1, 0.9)
	else:
		fuel_fill.color = Color(1.0, 0.15, 0.1, 0.9)


# ============================================================
# 就近信号报告
# ============================================================
func _update_signal_report(dist: float) -> void:
	if dist > 500.0:
		signal_label.text = "搜索中..."
		signal_label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.8, 0.4))
	elif dist > 250.0:
		signal_label.text = "信号微弱"
		signal_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9, 0.6))
	elif dist > 120.0:
		signal_label.text = "信号增强"
		var pulse: float = sin(Time.get_ticks_msec() * 0.005) * 0.15 + 0.85
		signal_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, pulse))
	elif dist > 40.0:
		signal_label.text = "信号强烈!"
		var pulse: float = sin(Time.get_ticks_msec() * 0.01) * 0.3 + 0.7
		signal_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5, pulse))
	else:
		signal_label.text = ">>> 已到达 <<<"
		var flash: float = sin(Time.get_ticks_msec() * 0.015) * 0.5 + 0.5
		signal_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 0.7 + flash * 0.3))


# ============================================================
# 速度矢量虚线 — 从飞机尾部沿实际运动方向绘制流动虚线
# 帮助玩家可视化"风偏后我实际在往哪飞"
# ============================================================
func _draw_trail() -> void:
	if game_over or player.velocity.length() < 5.0:
		return

	# 速度方向（世界坐标）— 飞机实际的运动方向
	var vel_dir: Vector2 = player.velocity.normalized()
	var vel_len: float = player.velocity.length()
	# 轨迹长度与速度成正比（快=远，慢=近）
	var trail_len: float = clamp(vel_len * 0.45, 30.0, DASH_MAX)

	# 颜色：青色荧光，速度越快越亮
	var alpha: float = clamp(vel_len / 180.0, 0.1, 0.55)
	var dash_color := Color(0.1, 0.95, 1.0, alpha)

	# 从飞机前方开始，沿速度方向画出流动虚线
	var start_pos: Vector2 = player.global_position + vel_dir * 6.0
	var offset: float = dash_offset

	var pos: float = 0.0
	var drawing := true
	while pos < trail_len:
		var seg_end: float = minf(pos + (DASH_LEN if drawing else DASH_GAP), trail_len)
		if drawing:
			var from: Vector2 = start_pos + vel_dir * pos
			var to: Vector2 = start_pos + vel_dir * seg_end
			# offset 实现虚线向飞机方向流动
			from -= vel_dir * offset
			to -= vel_dir * offset
			# 越远处越淡，营造渐隐效果
			var fade: float = 1.0 - (pos / trail_len)
			var col := Color(dash_color, dash_color.a * fade)
			trail_node.draw_line(from, to, col, 1.3)
		pos = seg_end
		drawing = not drawing

# ============================================================
func _on_rescue_done() -> void:
	## 缩放动画结束后重新生成信标并恢复状态
	_spawn_anchor()
	rescuing = false

# ============================================================
# 六边形呼吸动效 + 救援圈同步（救援动画期间跳过）
# ============================================================
func _animate_hexagon() -> void:
	if rescuing:
		return
	var breath: float = sin(Time.get_ticks_msec() * 0.0015) * 0.08 + 1.0
	hex_poly.scale = Vector2(breath, breath)
	hex_border.scale = Vector2(breath, breath)
	rescue_ring.scale = Vector2(breath, breath)
	rescue_ring.default_color.a = 0.2 + breath * 0.2

	var bright: float = 0.75 + breath * 0.25
	hex_poly.color = Color(1.0 * bright, 0.25 * bright, 0.2 * bright, 0.9)


# ============================================================
# 尾焰动画
# ============================================================
func _anim_flame() -> void:
	var rng: float = randf_range(-3.0, 3.0)
	flame_poly.polygon = PackedVector2Array([
		Vector2(-10, -5 + rng),
		Vector2(-22 - randf_range(0.0, 8.0), 0.0),
		Vector2(-10, 5 - rng),
	])
	flame_poly.color = Color(1.0, 0.45 + randf_range(0.0, 0.25), 0.05, 0.7 + randf_range(0.0, 0.3))


# ============================================================
# 边界
# ============================================================
func _wrap(n: Node2D) -> void:
	const W := 1280.0
	const H := 900.0
	if n.global_position.x > W / 2.0:
		n.global_position.x -= W
	elif n.global_position.x < -W / 2.0:
		n.global_position.x += W
	if n.global_position.y > H / 2.0:
		n.global_position.y -= H
	elif n.global_position.y < -H / 2.0:
		n.global_position.y += H