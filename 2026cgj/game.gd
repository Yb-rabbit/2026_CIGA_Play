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
var camera: Camera2D
var angular_velocity: float = 0.0

# UI
var compass_needle: Sprite2D
var fuel_fill: ColorRect
var score_label: Label
var dist_label: Label
var hint_label: Label
var game_over_label: Label


# ============================================================
# _ready — 构建一切
# ============================================================
func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.02, 0.04, 0.16, 1.0))

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

	# 碰撞体
	var col_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	col_shape.shape = circle
	player.add_child(col_shape)

	# 飞机机身 — 白色三角形
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

	# 尾焰 — 加速时可见
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
	add_child(camera)  # 挂根节点，不继承 Player 旋转


# ============================================================
# 信标 (Area2D + 红色六边 Polygon2D + Line2D 框)
# ============================================================
func _build_anchor() -> void:
	anchor = Area2D.new()
	anchor.name = "Anchor"
	add_child(anchor)

	# 碰撞区域
	var col_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 28.0
	col_shape.shape = circle
	anchor.add_child(col_shape)

	# 六边形 — 红色填充（赋值给成员变量 hex_poly，用于动效）
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

	# 六边形边框 — 白色（赋值给成员变量 hex_border）
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

	# 碰撞信号
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
	cc.position = Vector2(1280 - 170, 14)
	cc.size = Vector2(150, 150)
	ui.add_child(cc)

	# 罗盘底盘
	var face := Sprite2D.new()
	face.position = Vector2(75, 75)
	face.texture = _make_compass_tex()
	cc.add_child(face)

	# 指针
	compass_needle = Sprite2D.new()
	compass_needle.position = Vector2(75, 75)
	compass_needle.texture = _make_needle_tex()
	cc.add_child(compass_needle)

	# ---- 油量条 (左上) ----
	var bg := ColorRect.new()
	bg.position = Vector2(20, 20)
	bg.size = Vector2(180, 22)
	bg.color = Color(0.1, 0.1, 0.15, 0.85)
	ui.add_child(bg)

	fuel_fill = ColorRect.new()
	fuel_fill.position = Vector2(22, 22)
	fuel_fill.size = Vector2(176, 18)
	fuel_fill.color = Color(0.2, 0.85, 0.5, 0.9)
	ui.add_child(fuel_fill)

	var fl := Label.new()
	fl.position = Vector2(20, 46)
	fl.text = "FUEL"
	fl.add_theme_font_size_override("font_size", 10)
	fl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.9, 0.8))
	ui.add_child(fl)

	# ---- 分数 ----
	score_label = Label.new()
	score_label.position = Vector2(20, 62)
	score_label.text = "救援: 0"
	score_label.add_theme_font_size_override("font_size", 16)
	score_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 0.9))
	ui.add_child(score_label)

	# ---- 距离 (罗盘下方) ----
	dist_label = Label.new()
	dist_label.position = Vector2(1280 - 170, 168)
	dist_label.size = Vector2(150, 24)
	dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_label.add_theme_font_size_override("font_size", 11)
	dist_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 0.7))
	ui.add_child(dist_label)

	# ---- 操作提示 ----
	hint_label = Label.new()
	hint_label.anchors_preset = Control.PRESET_CENTER_BOTTOM
	hint_label.position = Vector2(-230, -30)
	hint_label.size = Vector2(460, 24)
	hint_label.text = "A/D 旋转 | W 加速 | S 减速 | 指针指上 = 对准目标"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.9, 0.7))
	ui.add_child(hint_label)

	# ---- Game Over ----
	game_over_label = Label.new()
	game_over_label.visible = false
	game_over_label.text = "燃料耗尽\n按 R 重新开始"
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_label.add_theme_font_size_override("font_size", 36)
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

	# 四个刻度
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
	# 新信标重置缩放
	hex_poly.scale = Vector2.ONE
	hex_border.scale = Vector2.ONE


# ============================================================
# 救援成功
# ============================================================
func _on_rescue(_b: Node2D) -> void:
	if game_over:
		return
	rescue_count += 1
	score += int(100 + rescue_count * 15)
	fuel = minf(fuel_max, fuel + FUEL_REFILL)
	score_label.text = "救援: %d" % score

	# 难度递增
	var na: float = randf_range(0.0, TAU)
	var ns: float = BASE_WIND + float(rescue_count) * 25.0
	wind_vector = Vector2.RIGHT.rotated(na) * ns

	_spawn_anchor()

	# 闪烁反馈
	var tw := create_tween()
	tw.tween_property(score_label, "modulate", Color.WHITE, 0.08)
	tw.tween_property(score_label, "modulate", Color(1.0, 0.9, 0.3, 0.9), 0.25)


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

	# 1. 旋转（带角动量惯性）
	var ri: float = Input.get_axis("ui_left", "ui_right")
	angular_velocity += ri * ROT_ACCEL * delta
	angular_velocity *= ROT_DRAG
	player.rotation += angular_velocity * delta

	# 2. 推进 + 油耗
	var thrusting: bool = Input.is_action_pressed("ui_up") and fuel > 0.0
	if thrusting:
		player.velocity += Vector2.RIGHT.rotated(player.rotation) * THRUST * delta
		fuel = maxf(0.0, fuel - FUEL_BURN * delta)
		if fuel <= 0.0:
			_game_over()

	# 2.5. S 键减速
	if Input.is_action_pressed("ui_down"):
		var spd: float = player.velocity.length()
		if spd > 0.0:
			var force: float = minf(BRAKE * delta, spd)
			player.velocity -= player.velocity.normalized() * force

	# 3. 风场
	player.velocity += wind_vector * delta

	# 4. 惯性
	player.velocity *= LIN_DRAG

	# 5. 限速
	var sp: float = player.velocity.length()
	if sp > MAX_SPD:
		player.velocity = player.velocity * (MAX_SPD / sp)

	# 5.5 六边形呼吸动效
	_animate_hexagon()

	# 6. 移动
	player.move_and_slide()

	# 7. 边界
	_wrap(player)

	# 8. 尾焰
	flame_poly.visible = thrusting
	if thrusting:
		_anim_flame()

	# 9. 相机
	camera.global_position = player.global_position

	# 10. UI
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
	dist_label.text = "距离: %.0f px" % dist

	if dist > 0.5:
		# relative_bearing = world_angle_to_target - player_facing_angle
		# 指针纹理天生朝上 → rotation=0 时指针指向上方
		compass_needle.rotation = to.angle() - player.rotation

	# 距离反馈: 近→绿+快闪, 远→红+慢闪
	var t: float = clampi(int(dist), 0, 500) / 500.0
	compass_needle.modulate = Color(
		lerpf(0.25, 1.0, 1.0 - t),
		lerpf(0.15, 0.9, 1.0 - t),
		lerpf(0.8, 0.15, 1.0 - t),
		0.95
	)
	var blink: float = sin(Time.get_ticks_msec() * 0.003 * lerpf(0.8, 6.0, 1.0 - t)) * 0.25 + 0.75
	compass_needle.modulate.a *= blink


# ============================================================
# 油量条
# ============================================================
func _update_fuel() -> void:
	var r: float = fuel / fuel_max
	fuel_fill.size.x = 176.0 * r
	if r > 0.4:
		fuel_fill.color = Color(0.2, 0.85, 0.5, 0.9)
	elif r > 0.15:
		fuel_fill.color = Color(1.0, 0.7, 0.1, 0.9)
	else:
		fuel_fill.color = Color(1.0, 0.15, 0.1, 0.9)


# ============================================================
# 六边形呼吸动效 — 缓慢缩放 + 颜色脉动
# 给予玩家直观的"靠近它"的感觉
# ============================================================
func _animate_hexagon() -> void:
	# 呼吸周期约 2 秒，缩放范围 0.92 ~ 1.08
	var breath: float = sin(Time.get_ticks_msec() * 0.0015) * 0.08 + 1.0
	hex_poly.scale = Vector2(breath, breath)
	hex_border.scale = Vector2(breath, breath)

	# 颜色亮度随呼吸微调
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