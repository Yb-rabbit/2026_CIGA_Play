extends Node2D
## ============================================================
## EndlessMode — 无尽深空模式
## 全部通关后解锁，独立于游戏关卡部分
## 特性：无限体力、更大地图、随机内容组合、制作人员通知
## ============================================================

# ==================== 关卡参数 ====================
const FUEL_MAX: float = 100.0
const FUEL_BURN: float = 0.0                # 无尽模式不消耗燃料（无限制推力）
const FUEL_REFILL: float = 100.0            # 每次救援满油

# ==================== 风场 ====================
var wind_vector: Vector2 = Vector2.ZERO
const BASE_WIND: float = 100.0

# ==================== 飞行参数 ====================
const THRUST: float = 320.0
const BRAKE: float = 200.0
const ROT_ACCEL: float = 20.0
const ROT_DRAG: float = 0.80
const LIN_DRAG: float = 0.992
const MAX_SPD: float = 480.0

# ==================== 本地游戏状态 ====================
var _session_score: int = 0
var _rescue_count: int = 0
var _game_over: bool = false
var rescuing: bool = false

# ==================== 节点引用 ====================
var player: CharacterBody2D
var body_poly: Polygon2D
var flame_poly: Polygon2D
var anchor: Area2D
var hex_poly: Polygon2D
var hex_border: Line2D
var rescue_ring: Line2D
var camera: Camera2D
var angular_velocity: float = 0.0

# 速度矢量虚线
const DASH_LEN := 10.0
const DASH_GAP := 14.0
const DASH_MAX := 180.0
const DASH_FLOW_SPEED := 90.0
var dash_offset: float = 0.0
var trail_node: Node2D
var star_node: Node2D

# UI 节点
var _font: Font
var compass_needle: Sprite2D
var compass_ripple: Sprite2D
var fuel_fill: ColorRect
var score_label: Label
var dist_label: Label
var hint_label: Label
var game_over_label: Label
var signal_label: Label
var _scan_progress_bg: ColorRect = null
var _scan_progress_bar: ColorRect = null
var _bgm_player: AudioStreamPlayer = null

# 锚点系统
var anchor_node: Node2D = null
var anchor_active: bool = false
const ANCHOR_RADIUS: float = 180.0
const ANCHOR_FUEL_COST: float = 0.0
var anchor_circle_poly: Polygon2D
var anchor_dash_node: Node2D

# ==================== 灾害系统（全随机） ====================
var _decoy_nodes: Array[Area2D] = []
const DECOY_KNOCKBACK: float = 450.0
var _emi_zones: Array[Dictionary] = []
var _fog_nodes: Array[Area2D] = []
var _in_fog: bool = false
var _fog_draw_node: Node2D
var _emi_draw_node: Node2D = null

# ==================== 搜索圈 ====================
var _search_zones: Array[Dictionary] = []
var _in_search_zone: bool = false
var _current_search_zone: Dictionary = {}
var _beacon_revealed: bool = false
var _scan_timer: float = 0.0
var _scan_duration: float = 0.6
var _sos_blink_dist: float = 250.0
var _anchor_spawn_min: float = 400.0
var _anchor_spawn_max: float = 700.0
var _is_scanning: bool = false
var _compass_locked: bool = false
var _last_scan_pct: int = -1
var _last_w_held: bool = false
var _search_zones_draw_node: Node2D
var _wind_flip_timer: float = 15.0

# 程序化音频
var audio_player: AudioStreamPlayer
var audio_gen: AudioStreamGenerator
var audio_playback: AudioStreamGeneratorPlayback
var beep_timer: float = 0.0
var _beep_samples_left: int = 0
var _beep_freq: float = 0.0
var _anchor_sound_left: int = 0
const AUDIO_SAMPLE_RATE: int = 44100
const AUDIO_BUFFER_LEN: float = 0.3

# 星空
var _stars: PackedVector2Array
var _stars_phase: Array[float]

# ==================== 制作人员名单（机载通讯系统播放） ====================
var _radio: Node = null                           # RadioAdvisor 实例引用
var _credit_messages: Array[Dictionary] = []      # 待播放的制作人员消息队列
var _credit_index: int = 0                        # 当前播放索引
var _credit_timer: float = 0.0                    # 消息间隔计时器
var _credits_finished: bool = false               # 是否已全部播放完毕


# ============================================================
# _ready — 构建无尽深空
# ============================================================
func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.01, 0.02, 0.10, 1.0))

	GameManager.set_game_state(GameManager.GameState.ENDLESS)
	GameManager.fuel = FUEL_MAX

	# 随机风场
	var na: float = randf_range(0.0, TAU)
	wind_vector = Vector2.RIGHT.rotated(na) * BASE_WIND

	# 关卡参数随机
	_scan_duration = randf_range(0.5, 0.9)
	_sos_blink_dist = randf_range(200.0, 300.0)
	_anchor_spawn_min = randf_range(350.0, 550.0)
	_anchor_spawn_max = randf_range(600.0, 850.0)
	_wind_flip_timer = randf_range(10.0, 25.0)

	_build_stars()
	trail_node = Node2D.new()
	trail_node.name = "TrailNode"
	add_child(trail_node)
	trail_node.draw.connect(_draw_trail)

	_build_player()
	_build_camera()
	_build_anchor()
	_spawn_anchor()
	_build_search_zones()
	_build_random_hazards()
	_build_ui()

	_search_zones_draw_node = Node2D.new()
	_search_zones_draw_node.name = "SearchZonesDraw"
	add_child(_search_zones_draw_node)
	_search_zones_draw_node.draw.connect(_draw_search_zones)

	_anchor_set_visible(false)
	_compass_locked = false

	anchor_dash_node = Node2D.new()
	anchor_dash_node.name = "AnchorDash"
	add_child(anchor_dash_node)
	anchor_dash_node.draw.connect(_draw_anchor_dash)

	_fog_draw_node = Node2D.new()
	_fog_draw_node.name = "FogDraw"
	add_child(_fog_draw_node)

	_emi_draw_node = Node2D.new()
	_emi_draw_node.name = "EmiDraw"
	add_child(_emi_draw_node)
	_emi_draw_node.draw.connect(_draw_emi_zones)

	_build_audio()
	score_label.text = "救援: %d" % _session_score
	_update_fuel()

	# 背景音乐
	_build_bgm()

	# 通知系统
	_build_notification_system()
	# RadioAdvisor._ready() 会重新启用 process，需要用 call_deferred 覆盖
	_radio.call_deferred("set_process", false)


# ============================================================
# 开发者工具
# ============================================================
func _open_dev_tools() -> void:
	var DevToolsClass := load("res://DevTools.gd") as GDScript
	var dev_tools: Node = DevToolsClass.new()
	add_child(dev_tools)


func _open_pause_menu() -> void:
	var PauseMenuClass := load("res://PauseMenu.gd") as GDScript
	var pause_menu: Node = PauseMenuClass.new()
	add_child(pause_menu)


# ============================================================
# 背景音乐
# ============================================================
func _build_bgm() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMusic"
	_bgm_player.bus = "Master"
	_bgm_player.volume_db = -8.0
	add_child(_bgm_player)

	if ResourceLoader.exists("res://stage1(2.0).ogg"):
		_bgm_player.stream = load("res://stage1(2.0).ogg")
	elif ResourceLoader.exists("res://stage1(dm).ogg"):
		_bgm_player.stream = load("res://stage1(dm).ogg")

	if _bgm_player.stream != null:
		_bgm_player.finished.connect(_bgm_loop)
		_bgm_player.play()


func _bgm_loop() -> void:
	if _bgm_player != null:
		_bgm_player.play()


# ============================================================
# 通知系统 — 滚动展示制作成员 + 感谢信息
# ============================================================
func _build_notification_system() -> void:
	## 通过机载 RadioAdvisor 系统展示制作人员名单
	var RadioAdvisorClass := load("res://RadioAdvisor.gd") as GDScript
	_radio = RadioAdvisorClass.new()
	_radio.name = "RadioAdvisor"
	_radio.set_process(false)  # 禁用空闲消息定时器，仅用于播放制作人员名单
	add_child(_radio)

	# 制作人员消息队列（sender, msg, color）
	_credit_messages = [
		{ "sender": "[档案]", "msg": "程序：一笔兔", "color": Color(0.3, 0.9, 1.0) },
		{ "sender": "[档案]", "msg": "策划：The昊子", "color": Color(0.3, 0.9, 1.0) },
		{ "sender": "[档案]", "msg": "音频：UMC049", "color": Color(0.3, 0.9, 1.0) },
		{ "sender": "[通讯]", "msg": "感谢你的体验以及助力", "color": Color(1.0, 0.85, 0.2) },
	]

	_credit_index = 0
	_credit_timer = 2.5  # 进入游戏 2.5 秒后开始第一条
	_credits_finished = false


func _play_next_credit() -> void:
	## 通过 RadioAdvisor 播放下一条制作人员消息
	if _credit_index >= _credit_messages.size():
		_credits_finished = true
		return

	var entry: Dictionary = _credit_messages[_credit_index]
	_credit_index += 1

	if _radio != null and _radio.has_method("_show_message"):
		_radio._show_message(entry["sender"], entry["msg"], entry["color"])


# ============================================================
# _input — S 抛锚 / ESC 返回
# ============================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_open_dev_tools()
		return

	if _game_over:
		return

	if event.is_action_pressed("ui_down") and not event.is_echo():
		_do_anchor_drop()

	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_open_pause_menu()
		get_viewport().set_input_as_handled()


# ============================================================
# 玩家构建
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
		Vector2(16, 0), Vector2(-10, -9), Vector2(-6, 0), Vector2(-10, 9),
	])
	body_poly.color = Color(0.9, 0.95, 1.0)
	player.add_child(body_poly)

	flame_poly = Polygon2D.new()
	flame_poly.name = "Flame"
	flame_poly.polygon = PackedVector2Array([
		Vector2(-10, -5), Vector2(-28, 0), Vector2(-10, 5),
	])
	flame_poly.color = Color(1.0, 0.55, 0.1, 0.8)
	flame_poly.visible = false
	player.add_child(flame_poly)


# ============================================================
# 相机
# ============================================================
func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.enabled = true
	add_child(camera)


# ============================================================
# 信标 (Area2D + 红色六边)
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
# 随机灾害 — 所有参数随机组合
# ============================================================
func _build_random_hazards() -> void:
	var decoy_count: int = randi_range(2, 6)
	var emi_count: int = randi_range(1, 4)
	var fog_count: int = randi_range(1, 4)

	for i: int in range(decoy_count):
		var da: float = randf_range(0.0, TAU)
		var dd: float = randf_range(500.0, 1200.0)
		var dpos := player.position + Vector2.RIGHT.rotated(da) * dd
		var decoy := _build_decoy(dpos)
		add_child(decoy)
		_decoy_nodes.append(decoy)

	for i: int in range(emi_count):
		var ea: float = randf_range(0.0, TAU)
		var ed: float = randf_range(400.0, 1200.0)
		_emi_zones.append({
			"pos": player.position + Vector2.RIGHT.rotated(ea) * ed,
			"radius": randf_range(180.0, 400.0),
			"seed": randf_range(0.0, TAU)
		})

	for i: int in range(fog_count):
		var fa: float = randf_range(0.0, TAU)
		var fd: float = randf_range(500.0, 1100.0)
		var fcenter := player.position + Vector2.RIGHT.rotated(fa) * fd
		var fradius: float = randf_range(80.0, 200.0)
		var fog := _build_fog_cloud(fcenter, fradius)
		fog.set_meta("fog_radius", fradius)
		add_child(fog)
		_fog_nodes.append(fog)


func _build_decoy(dpos: Vector2) -> Area2D:
	var da := Area2D.new()
	da.name = "DecoyBeacon"
	da.global_position = dpos

	var col_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 40.0
	col_shape.shape = circle
	da.add_child(col_shape)

	const R := 18.0
	var dpts := PackedVector2Array()
	for i: int in range(6):
		var a: float = i * TAU / 6.0 - PI / 2.0
		dpts.append(Vector2(cos(a), sin(a)) * R)
	var dpoly := Polygon2D.new()
	dpoly.name = "DecoyBody"
	dpoly.polygon = dpts
	dpoly.color = Color(0.6, 0.2, 0.9, 0.7)
	da.add_child(dpoly)

	var dborder := Line2D.new()
	dborder.name = "DecoyBorder"
	dborder.width = 1.2
	dborder.default_color = Color(0.7, 0.3, 0.9, 0.6)
	dborder.closed = true
	var dbpts := PackedVector2Array()
	for i: int in range(7):
		var a: float = (i % 6) * TAU / 6.0 - PI / 2.0
		dbpts.append(Vector2(cos(a), sin(a)) * R)
	dborder.points = dbpts
	da.add_child(dborder)

	var x1 := Line2D.new()
	x1.width = 2.0
	x1.default_color = Color(0.8, 0.3, 0.9, 0.5)
	x1.points = PackedVector2Array([Vector2(-8, -8), Vector2(8, 8)])
	da.add_child(x1)
	var x2 := Line2D.new()
	x2.width = 2.0
	x2.default_color = Color(0.8, 0.3, 0.9, 0.5)
	x2.points = PackedVector2Array([Vector2(8, -8), Vector2(-8, 8)])
	da.add_child(x2)

	da.body_entered.connect(_on_decoy_collision)
	return da


func _build_fog_cloud(center: Vector2, radius: float) -> Area2D:
	var fa := Area2D.new()
	fa.name = "FogCloud"
	fa.global_position = center

	var col_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	col_shape.shape = circle
	fa.add_child(col_shape)

	fa.body_entered.connect(_on_fog_entered)
	fa.body_exited.connect(_on_fog_exited)
	return fa


# ============================================================
# UI
# ============================================================
func _build_ui() -> void:
	_font = load("res://YuFanDanQingSong.otf") as Font

	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	# 罗盘
	var cc := Control.new()
	cc.name = "Compass"
	cc.position = Vector2(1600 - 244, 14)
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

	compass_ripple = Sprite2D.new()
	compass_ripple.name = "Ripple"
	compass_ripple.position = Vector2(95, 95)
	compass_ripple.texture = _make_ripple_tex()
	compass_ripple.visible = false
	cc.add_child(compass_ripple)

	# 油量条（始终满油）
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
	fl.text = "FUEL ∞"
	fl.add_theme_font_size_override("font_size", 20)
	fl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.9, 0.8))
	fl.add_theme_font_override("font", _font)
	ui.add_child(fl)

	# 分数
	score_label = Label.new()
	score_label.position = Vector2(20, 78)
	score_label.text = "救援: 0"
	score_label.add_theme_font_size_override("font_size", 36)
	score_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 0.9))
	score_label.add_theme_font_override("font", _font)
	ui.add_child(score_label)

	# 距离
	dist_label = Label.new()
	dist_label.position = Vector2(1600 - 244, 210)
	dist_label.size = Vector2(190, 28)
	dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_label.add_theme_font_size_override("font_size", 26)
	dist_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 0.7))
	dist_label.add_theme_font_override("font", _font)
	ui.add_child(dist_label)

	# 信号报告
	signal_label = Label.new()
	signal_label.position = Vector2(1600 - 244, 240)
	signal_label.size = Vector2(190, 32)
	signal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	signal_label.add_theme_font_size_override("font_size", 24)
	signal_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 0.0))
	signal_label.add_theme_font_override("font", _font)
	signal_label.text = "搜索中..."
	ui.add_child(signal_label)

	# 扫描进度条
	_scan_progress_bg = ColorRect.new()
	_scan_progress_bg.position = Vector2(1600 - 224 + 8, 276)
	_scan_progress_bg.size = Vector2(174, 8)
	_scan_progress_bg.color = Color(0.05, 0.1, 0.2, 0.8)
	_scan_progress_bg.visible = false
	ui.add_child(_scan_progress_bg)

	_scan_progress_bar = ColorRect.new()
	_scan_progress_bar.position = Vector2(1600 - 224 + 8, 276)
	_scan_progress_bar.size = Vector2(0, 8)
	_scan_progress_bar.color = Color(0.2, 0.9, 0.6, 0.9)
	_scan_progress_bar.visible = false
	ui.add_child(_scan_progress_bar)

	# 操作提示
	hint_label = Label.new()
	hint_label.anchors_preset = Control.PRESET_CENTER_BOTTOM
	hint_label.position = Vector2(-320, -36)
	hint_label.size = Vector2(640, 30)
	hint_label.text = "A/D 旋转 | W 加速（不耗油）| S 抛锚/减速 | Esc 暂停"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 24)
	hint_label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.9, 0.7))
	hint_label.add_theme_font_override("font", _font)
	ui.add_child(hint_label)

	# Game Over（无尽模式下不会真正发生，但保留）
	game_over_label = Label.new()
	game_over_label.visible = false
	game_over_label.text = "信号全失...\n按 R 重新开始\n按 M 返回关卡选择"
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_label.add_theme_font_size_override("font_size", 64)
	game_over_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	game_over_label.add_theme_font_override("font", _font)
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
	for i: int in range(1, 4):
		var a: float = i * PI / 2.0 - PI / 2.0
		var d := Vector2(cos(a), sin(a))
		_draw_line_on_img(img, c + d * (r - 18.0), c + d * (r - 2.0), 2.5, tc)
	var nc := Color(1.0, 0.45, 0.2, 1.0)
	var nd := Vector2.UP
	_draw_line_on_img(img, c + nd * (r - 20.0), c + nd * (r - 2.0), 4.5, nc)
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
	const S := 180
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(S / 2.0, S / 2.0)
	for y: int in range(S):
		for x: int in range(S):
			var d: float = Vector2(x, y).distance_to(c)
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
	var d: float = randf_range(_anchor_spawn_min, _anchor_spawn_max)
	anchor.global_position = player.global_position + Vector2.RIGHT.rotated(a) * d
	_wrap(anchor)
	hex_poly.scale = Vector2.ONE
	hex_border.scale = Vector2.ONE
	rescue_ring.scale = Vector2.ONE


# ============================================================
# 救援成功
# ============================================================
func _on_rescue(_b: Node2D) -> void:
	if _game_over or rescuing:
		return
	rescuing = true
	_rescue_count += 1
	_session_score += int(100 + _rescue_count * 20)

	GameManager.fuel = FUEL_MAX
	if _session_score > GameManager.high_score:
		GameManager.high_score = _session_score

	score_label.text = "救援: %d" % _session_score

	# 随机变换风场
	var na: float = randf_range(0.0, TAU)
	wind_vector = Vector2.RIGHT.rotated(na) * BASE_WIND * (1.0 + float(_rescue_count) * 0.15)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(hex_poly, "scale", Vector2.ZERO, 0.35).set_ease(Tween.EASE_IN)
	tw.tween_property(hex_border, "scale", Vector2.ZERO, 0.35).set_ease(Tween.EASE_IN)
	tw.tween_property(rescue_ring, "scale", Vector2.ZERO, 0.35).set_ease(Tween.EASE_IN)

	var tw2 := create_tween()
	tw2.tween_property(score_label, "modulate", Color.WHITE, 0.08)
	tw2.tween_property(score_label, "modulate", Color(1.0, 0.9, 0.3, 0.9), 0.25)

	tw.finished.connect(_on_rescue_done)


func _on_rescue_done() -> void:
	# 无尽模式：持续生成新信标
	# 先清理旧节点，防止内存泄露
	_cleanup_search_zones()
	_cleanup_hazards()

	_spawn_anchor()
	_anchor_set_visible(false)
	_compass_locked = false
	_beacon_revealed = false
	_build_search_zones()
	_build_random_hazards()
	rescuing = false


# ============================================================
# 虚假信标碰撞
# ============================================================
func _on_decoy_collision(body: Node2D) -> void:
	if body != player or _game_over:
		return
	var away: Vector2 = (player.global_position - body.global_position).normalized()
	if away.length() < 0.1:
		away = Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	player.velocity += away * DECOY_KNOCKBACK

	var player_tw := create_tween()
	player_tw.tween_property(body_poly, "scale", Vector2(0.7, 1.3), 0.08)
	player_tw.tween_property(body_poly, "scale", Vector2(1.15, 0.85), 0.1)
	player_tw.tween_property(body_poly, "scale", Vector2.ONE, 0.12)


# ============================================================
# 遮蔽云
# ============================================================
func _on_fog_entered(body: Node2D) -> void:
	if body == player:
		_in_fog = true


func _on_fog_exited(body: Node2D) -> void:
	if body == player:
		_in_fog = false


# ============================================================
# 主循环
# ============================================================
func _physics_process(delta: float) -> void:
	if _game_over:
		_update_compass()
		return

	var ri: float = Input.get_axis("ui_left", "ui_right")
	angular_velocity += ri * ROT_ACCEL * delta
	angular_velocity *= ROT_DRAG
	player.rotation += angular_velocity * delta

	var thrusting: bool = Input.is_action_pressed("ui_up")
	if thrusting:
		player.velocity += Vector2.RIGHT.rotated(player.rotation) * THRUST * delta

	if Input.is_action_pressed("ui_down"):
		var spd: float = player.velocity.length()
		if spd > 0.0:
			var force: float = minf(BRAKE * delta, spd)
			player.velocity -= player.velocity.normalized() * force

	var _in_anchor_now := _is_in_anchor_range()

	if _wind_flip_timer > 0.0:
		_wind_flip_timer -= delta
		if _wind_flip_timer <= 0.0:
			var flip_dir: float = randf_range(-TAU * 0.5, TAU * 0.5) + PI
			wind_vector = wind_vector.rotated(flip_dir)
			_wind_flip_timer = randf_range(8.0, 25.0)

	if not _in_anchor_now:
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

	dash_offset += DASH_FLOW_SPEED * delta
	if dash_offset > DASH_GAP + DASH_LEN:
		dash_offset -= DASH_GAP + DASH_LEN

	trail_node.queue_redraw()
	_fog_draw_node.queue_redraw()

	if anchor_active:
		anchor_dash_node.queue_redraw()

	_update_hazards()
	_update_scan(delta)
	_update_compass()
	_update_fuel()
	_update_sos_beacon(delta)


# ============================================================
# _process
# ============================================================
func _process(delta: float) -> void:
	if _game_over:
		if Input.is_key_pressed(KEY_R):
			_restart()
		elif Input.is_key_pressed(KEY_M):
			GameManager.change_scene("LevelSelect")

	# 制作人员名单播报（通过机载 RadioAdvisor）
	if not _credits_finished:
		_credit_timer -= delta
		if _credit_timer <= 0.0:
			_play_next_credit()
			_credit_timer = 7.0  # 每条消息间隔 7 秒（RadioAdvisor 显示 6 秒后淡出，需 > 6 秒避免堆叠）

	if not _game_over and anchor != null and not _in_fog:
		var dist: float = player.global_position.distance_to(anchor.global_position)
		beep_timer -= delta
		if beep_timer <= 0.0:
			var t: float = clamp(dist / 500.0, 0.0, 1.0)
			var freq: float = lerpf(200.0, 1600.0, 1.0 - t)
			var interval: float = lerpf(2.5, 0.12, 1.0 - t)
			_beep_freq = freq
			_beep_samples_left = int(AUDIO_SAMPLE_RATE * 0.08)
			beep_timer = interval
	elif _in_fog:
		beep_timer = 0.0
		_beep_samples_left = 0

	_fill_audio_buffer()


# ============================================================
# 灾害更新
# ============================================================
func _update_hazards() -> void:
	for da in _decoy_nodes:
		if da == null:
			continue
		da.scale = Vector2(sin(Time.get_ticks_msec() * 0.002) * 0.06 + 1.0, sin(Time.get_ticks_msec() * 0.002) * 0.06 + 1.0)

	_fog_draw_node.draw.connect(_draw_fog_clouds, CONNECT_ONE_SHOT)
	_fog_draw_node.queue_redraw()


func _draw_emi_zones() -> void:
	if _emi_draw_node == null:
		return
	var t: float = Time.get_ticks_msec() * 0.001
	for zone in _emi_zones:
		var zpos: Vector2 = zone["pos"]
		var zr: float = zone["radius"]
		var zone_seed: float = zone["seed"]
		var intensity: float = absf(sin(t * 1.5 + zone_seed)) * 0.25 + 0.15
		const SEG := 48
		var pts := PackedVector2Array()
		for j: int in range(SEG + 1):
			var a: float = TAU * float(j) / float(SEG)
			var r: float = zr + sin(a * 5.0 + t * 2.0 + zone_seed) * 15.0
			pts.append(zpos + Vector2(cos(a), sin(a)) * r)
		_emi_draw_node.draw_colored_polygon(pts, Color(0.5, 0.2, 0.8, intensity * 0.3))
		_emi_draw_node.draw_polyline(pts + PackedVector2Array([Vector2(cos(0), sin(0)) * zr]), Color(0.7, 0.3, 1.0, intensity), 2.0)


func _draw_fog_clouds() -> void:
	for fa in _fog_nodes:
		if fa == null:
			continue
		var r: float = fa.get_meta("fog_radius", 100.0)
		for layer: int in range(3):
			var lr: float = r - float(layer) * 25.0
			if lr < 10.0:
				continue
			_fog_draw_node.draw_circle(fa.global_position, lr, Color(0.3, 0.35, 0.5, 0.06 + float(layer) * 0.03))


# ============================================================
# 罗盘
# ============================================================
func _update_compass() -> void:
	var to: Vector2 = anchor.global_position - player.global_position
	var dist: float = to.length()
	dist_label.text = "最近距离: %.0f pc" % dist

	if _in_fog:
		compass_needle.visible = false
		compass_ripple.visible = false
		signal_label.text = "信号丢失..."
		signal_label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.4, 0.4))
		return

	compass_needle.visible = true
	var jitter_angle: float = 0.0

	for zone in _emi_zones:
		var dz: float = player.global_position.distance_to(zone["pos"])
		if dz < zone["radius"]:
			var intensity: float = 1.0 - (dz / zone["radius"])
			var phase: float = Time.get_ticks_msec() * 0.003 + zone["seed"]
			jitter_angle = sin(phase) * 35.0 * intensity
			break

	var emi_jitter: float = jitter_angle

	if not _compass_locked:
		var noise_t: float = Time.get_ticks_msec() * 0.001
		jitter_angle += sin(noise_t * 3.7) * 8.0 + cos(noise_t * 2.1) * 6.0

	if dist > 0.5:
		compass_needle.rotation = to.angle() - player.rotation + deg_to_rad(jitter_angle)

	var t: float = clampi(int(dist), 0, 500) / 500.0
	compass_needle.modulate = Color(
		lerpf(0.25, 1.0, 1.0 - t),
		lerpf(0.15, 0.9, 1.0 - t),
		lerpf(0.8, 0.15, 1.0 - t),
		0.95
	)
	var blink: float = sin(Time.get_ticks_msec() * 0.003 * lerpf(0.8, 6.0, 1.0 - t)) * 0.25 + 0.75
	compass_needle.modulate.a *= blink

	compass_ripple.visible = true
	var ripple_scale: float = lerpf(0.3, 1.1, 1.0 - t)
	var ripple_alpha: float = lerpf(0.05, 0.5, 1.0 - t)
	compass_ripple.scale = Vector2(ripple_scale, ripple_scale)
	compass_ripple.modulate.a = ripple_alpha
	compass_ripple.rotation += 0.008

	if absf(emi_jitter) > 2.0:
		signal_label.text = _scramble_text(dist)
		signal_label.add_theme_color_override("font_color", Color(0.7, 0.4, 1.0, 0.8))
	else:
		_update_signal_report(dist)


func _scramble_text(dist: float) -> String:
	const chars := "!@#$%^&*()_+-=[]{}|;:,.<>?/~`"
	var base: String
	if dist > 250.0:      base = "信号微弱"
	elif dist > 120.0:    base = "信号增强"
	elif dist > 40.0:     base = "信号强烈!"
	else:                  base = ">>> 已到达 <<<"
	var result := ""
	for i: int in range(base.length()):
		result += base[i]
		if randf_range(0.0, 1.0) < 0.4:
			result += chars[randi_range(0, chars.length() - 1)]
	return result


func _update_signal_report(dist: float) -> void:
	if dist > 500.0:
		signal_label.text = "搜索中..."
		signal_label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.8, 0.4))
	elif dist > 250.0:
		signal_label.text = "信号微弱"
		signal_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9, 0.6))
	elif dist > 120.0:
		signal_label.text = "信号增强"
		var p: float = sin(Time.get_ticks_msec() * 0.005) * 0.15 + 0.85
		signal_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, p))
	elif dist > 40.0:
		signal_label.text = "信号强烈!"
		var p: float = sin(Time.get_ticks_msec() * 0.01) * 0.3 + 0.7
		signal_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5, p))
	else:
		signal_label.text = ">>> 已到达 <<<"
		var flash: float = sin(Time.get_ticks_msec() * 0.015) * 0.5 + 0.5
		signal_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 0.7 + flash * 0.3))


# ============================================================
# 油量条（始终满）
# ============================================================
func _update_fuel() -> void:
	var r: float = GameManager.fuel / FUEL_MAX
	fuel_fill.size.x = 232.0 * r
	fuel_fill.color = Color(0.2, 0.85, 0.5, 0.9)


# ============================================================
# 六边形呼吸动效
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
		Vector2(-10, -5 + rng), Vector2(-22 - randf_range(0.0, 8.0), 0.0), Vector2(-10, 5 - rng),
	])
	flame_poly.color = Color(1.0, 0.45 + randf_range(0.0, 0.25), 0.05, 0.7 + randf_range(0.0, 0.3))


# ============================================================
# 星空
# ============================================================
func _build_stars() -> void:
	star_node = Node2D.new()
	star_node.name = "Stars"
	star_node.z_index = -10
	add_child(star_node)
	_stars.clear()
	_stars_phase.clear()
	for i: int in range(120):
		_stars.append(Vector2(randf_range(-2400.0, 2400.0), randf_range(-1600.0, 1600.0)))
		_stars_phase.append(randf_range(0.0, TAU))
	star_node.draw.connect(_draw_stars.bind(star_node))


func _draw_stars(node: Node2D) -> void:
	for i: int in range(_stars.size()):
		var twinkle: float = absf(sin(Time.get_ticks_msec() * 0.0004 + _stars_phase[i])) * 0.5 + 0.5
		var alpha: float = 0.15 + twinkle * 0.35
		node.draw_circle(_stars[i], 0.8 + twinkle * 0.6, Color(1.0, 1.0, 1.0, alpha))


# ============================================================
# 锚点系统
# ============================================================
func _do_anchor_drop() -> void:
	_remove_anchor()
	_spawn_anchor_node(player.global_position)
	_trigger_anchor_sound()


func _spawn_anchor_node(pos: Vector2) -> void:
	anchor_node = Node2D.new()
	anchor_node.name = "AnchorPoint"
	anchor_node.global_position = pos
	add_child(anchor_node)
	anchor_circle_poly = Polygon2D.new()
	anchor_circle_poly.name = "AnchorCircle"
	const SEG := 64
	var pts := PackedVector2Array()
	for i: int in range(SEG):
		var a: float = TAU * float(i) / float(SEG)
		pts.append(Vector2(cos(a), sin(a)) * ANCHOR_RADIUS)
	anchor_circle_poly.polygon = pts
	anchor_circle_poly.color = Color(0.2, 0.5, 1.0, 0.18)
	anchor_node.add_child(anchor_circle_poly)
	var ring := Line2D.new()
	ring.name = "AnchorRing"
	ring.width = 1.5
	ring.default_color = Color(0.3, 0.7, 1.0, 0.5)
	ring.closed = true
	var rpts := PackedVector2Array()
	for i: int in range(SEG + 1):
		var a: float = TAU * float(i % SEG) / float(SEG)
		rpts.append(Vector2(cos(a), sin(a)) * ANCHOR_RADIUS)
	ring.points = rpts
	anchor_node.add_child(ring)
	anchor_active = true
	anchor_dash_node.visible = true


func _remove_anchor() -> void:
	if anchor_node != null:
		anchor_node.queue_free()
		anchor_node = null
	anchor_active = false
	anchor_dash_node.visible = false


func _is_in_anchor_range() -> bool:
	if not anchor_active or anchor_node == null:
		return false
	if player.global_position.distance_to(anchor_node.global_position) > ANCHOR_RADIUS:
		_remove_anchor()
		return false
	return true


func _draw_anchor_dash() -> void:
	if not anchor_active or anchor_node == null:
		return
	var from: Vector2 = player.global_position
	var to: Vector2 = anchor_node.global_position
	var dir: Vector2 = (to - from).normalized()
	var total: float = from.distance_to(to)
	const DASH := 12.0
	const GAP := 8.0
	var pos: float = 0.0
	var draw_on := true
	while pos < total:
		var seg_end: float = minf(pos + (DASH if draw_on else GAP), total)
		if draw_on:
			anchor_dash_node.draw_line(from + dir * pos, from + dir * seg_end, Color(0.4, 0.75, 1.0, 0.55), 1.0)
		pos = seg_end
		draw_on = not draw_on


# ============================================================
# 速度矢量虚线
# ============================================================
func _draw_trail() -> void:
	if _game_over or player.velocity.length() < 5.0:
		return
	var vel_dir: Vector2 = player.velocity.normalized()
	var vel_len: float = player.velocity.length()
	var trail_len: float = clamp(vel_len * 0.45, 30.0, DASH_MAX)
	var alpha: float = clamp(vel_len / 180.0, 0.1, 0.55)
	var dash_color := Color(0.1, 0.95, 1.0, alpha)
	var start_pos: Vector2 = player.global_position + vel_dir * 6.0
	var offset: float = dash_offset
	var pos: float = 0.0
	var drawing := true
	while pos < trail_len:
		var seg_end: float = minf(pos + (DASH_LEN if drawing else DASH_GAP), trail_len)
		if drawing:
			var from: Vector2 = start_pos + vel_dir * pos
			var to: Vector2 = start_pos + vel_dir * seg_end
			from -= vel_dir * offset
			to -= vel_dir * offset
			var fade: float = 1.0 - (pos / trail_len)
			var col := Color(dash_color, dash_color.a * fade)
			trail_node.draw_line(from, to, col, 1.3)
		pos = seg_end
		drawing = not drawing


# ============================================================
# 程序化音频
# ============================================================
func _build_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.name = "AudioPlayer"
	add_child(audio_player)
	audio_gen = AudioStreamGenerator.new()
	audio_gen.mix_rate = AUDIO_SAMPLE_RATE
	audio_gen.buffer_length = AUDIO_BUFFER_LEN
	audio_player.stream = audio_gen
	audio_player.play()
	audio_playback = audio_player.get_stream_playback()


func _fill_audio_buffer() -> void:
	if audio_playback == null:
		return
	var to_fill: int = audio_playback.get_frames_available()
	if to_fill <= 0:
		return
	for _i: int in range(to_fill):
		var val: float = 0.0
		if _beep_samples_left > 0:
			var total: int = int(AUDIO_SAMPLE_RATE * 0.08)
			var elapsed: int = total - _beep_samples_left
			var t: float = float(elapsed) / float(AUDIO_SAMPLE_RATE)
			var env: float = 1.0
			var fade_smp: int = int(AUDIO_SAMPLE_RATE * 0.015)
			if _beep_samples_left < fade_smp:
				env = float(_beep_samples_left) / float(fade_smp)
			val += sin(t * TAU * _beep_freq) * env * 0.3
			_beep_samples_left -= 1
		if _anchor_sound_left > 0:
			var total: int = int(AUDIO_SAMPLE_RATE * 0.1)
			var elapsed: int = total - _anchor_sound_left
			var t: float = float(elapsed) / float(AUDIO_SAMPLE_RATE)
			var env: float = exp(-t * 18.0)
			val += sin(t * TAU * 200.0) * env * 0.5
			_anchor_sound_left -= 1
		val = clampf(val, -1.0, 1.0)
		audio_playback.push_frame(Vector2(val, val))


func _trigger_anchor_sound() -> void:
	_anchor_sound_left = int(AUDIO_SAMPLE_RATE * 0.1)


# ============================================================
# 搜索圈
# ============================================================
func _build_search_zones() -> void:
	const ZONE_RADIUS: float = 350.0
	var zone_count: int = randi_range(4, 6)
	var beacon_zone_index: int = randi_range(0, zone_count - 1)
	var beacon_pos: Vector2 = anchor.global_position

	for i: int in range(zone_count):
		var sz := Area2D.new()
		sz.name = "SearchZone%d" % i
		var col_shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = ZONE_RADIUS
		col_shape.shape = circle
		sz.add_child(col_shape)

		var has_beacon: bool = false

		if i == beacon_zone_index:
			var offset_angle: float = randf_range(0.0, TAU)
			var offset_dist: float = randf_range(100.0, 220.0)
			sz.global_position = beacon_pos + Vector2.RIGHT.rotated(offset_angle) * offset_dist
			has_beacon = true
		else:
			var a: float = TAU * float(i) / float(zone_count) + randf_range(-0.2, 0.2)
			var d: float = randf_range(400.0, 750.0)
			sz.global_position = player.global_position + Vector2.RIGHT.rotated(a) * d

		_wrap(sz)

		var zone_data := {
			"node": sz,
			"has_beacon": has_beacon,
			"radius": ZONE_RADIUS,
			"scanned": false
		}

		_search_zones.append(zone_data)
		add_child(sz)
		sz.body_entered.connect(_on_search_zone_entered.bind(zone_data))
		sz.body_exited.connect(_on_search_zone_exited.bind(zone_data))

	var any_has_beacon: bool = false
	for zd in _search_zones:
		if zd["has_beacon"]:
			any_has_beacon = true
			break
	if not any_has_beacon and _search_zones.size() > 0:
		_search_zones[0]["has_beacon"] = true


func _on_search_zone_entered(body: Node2D, zone_data: Dictionary) -> void:
	if body != player or _game_over:
		return
	if zone_data.get("scanned", false):
		return
	_in_search_zone = true
	_current_search_zone = zone_data
	_scan_timer = 0.0
	signal_label.text = "进入信号搜索区..."
	signal_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.8, 1.0))


func _on_search_zone_exited(body: Node2D, zone_data: Dictionary) -> void:
	if body != player:
		return
	if _current_search_zone == zone_data:
		_in_search_zone = false
		_current_search_zone = {}
		_scan_timer = 0.0
		_is_scanning = false
		if not _beacon_revealed:
			signal_label.text = "搜索中..."
			signal_label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.8, 0.4))


func _update_scan(delta: float) -> void:
	if _beacon_revealed:
		_is_scanning = false
		return
	if not _in_search_zone:
		return

	var zd := _current_search_zone
	if zd == null or zd.is_empty() or zd.get("scanned", false):
		return

	var w_held: bool = Input.is_action_pressed("ui_up")
	if w_held:
		_is_scanning = true
		_scan_timer += delta
	else:
		_is_scanning = false
		if _scan_timer > 0.0:
			_scan_timer = maxf(0.0, _scan_timer - delta * 0.5)

	var pct: int = int(clampf(_scan_timer / _scan_duration, 0.0, 1.0) * 100.0)
	var prog: float = clampf(_scan_timer / _scan_duration, 0.0, 1.0)

	if _scan_progress_bg != null and _scan_progress_bar != null:
		_scan_progress_bg.visible = true
		_scan_progress_bar.visible = true
		_scan_progress_bar.size.x = 174.0 * prog
		if w_held:
			_scan_progress_bar.color = Color(0.2, 0.9, 0.6, 0.9)
		else:
			_scan_progress_bar.color = Color(0.3, 0.6, 0.5, 0.6)

	if pct != _last_scan_pct or w_held != _last_w_held:
		_last_scan_pct = pct
		_last_w_held = w_held
		if w_held:
			signal_label.text = "扫描中... %d%%" % pct
			signal_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.8, 1.0))
		elif _scan_timer > 0.01:
			signal_label.text = "扫描中断... %d%%" % pct
			signal_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5, 0.9))
		else:
			signal_label.text = "按住 W 开始扫描..."
			signal_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.4, 0.8))

	if _scan_timer >= _scan_duration:
		_on_scan_complete()


func _draw_search_zones() -> void:
	if _search_zones_draw_node == null:
		return
	const SEG := 64
	for zd in _search_zones:
		if zd == null or zd.get("node") == null:
			continue
		var _node: Area2D = zd["node"]
		var r: float = zd["radius"]
		var scanned: bool = zd.get("scanned", false)

		var pts := PackedVector2Array()
		for i: int in range(SEG + 1):
			var a: float = TAU * float(i) / float(SEG)
			pts.append(Vector2(cos(a), sin(a)) * r)

		var pulse: float = sin(Time.get_ticks_msec() * 0.001) * 0.08 + 0.08
		if scanned:
			_search_zones_draw_node.draw_colored_polygon(pts, Color(0.3, 0.3, 0.3, 0.08))
			_search_zones_draw_node.draw_polyline(pts + PackedVector2Array([Vector2(cos(0), sin(0)) * r]), Color(0.5, 0.5, 0.5, 0.35), 1.5)
		else:
			_search_zones_draw_node.draw_colored_polygon(pts, Color(0.15, 0.5, 0.9, 0.08 + pulse))
			_search_zones_draw_node.draw_polyline(pts + PackedVector2Array([Vector2(cos(0), sin(0)) * r]), Color(0.3, 0.8, 1.0, 0.5), 2.0)


func _anchor_set_visible(v: bool) -> void:
	hex_poly.visible = v
	hex_border.visible = v
	rescue_ring.visible = v
	_beacon_revealed = v
	if v:
		_compass_locked = true


func _on_scan_complete() -> void:
	var zd := _current_search_zone
	if zd == null or zd.is_empty():
		return

	zd["scanned"] = true
	_is_scanning = false

	if zd.get("has_beacon", false):
		_anchor_set_visible(true)
		signal_label.text = ">>> 信号锁定 <<<"
		signal_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 1.0))
		var tw := create_tween()
		tw.tween_property(hex_poly, "scale", Vector2.ONE, 0.4).set_ease(Tween.EASE_OUT)
		hex_poly.scale = Vector2.ZERO
		tw.set_parallel(true)
		tw.tween_property(hex_border, "scale", Vector2.ONE, 0.4).set_ease(Tween.EASE_OUT)
		hex_border.scale = Vector2.ZERO
		tw.tween_property(rescue_ring, "scale", Vector2.ONE, 0.4).set_ease(Tween.EASE_OUT)
		rescue_ring.scale = Vector2.ZERO
		_cleanup_search_zones()
	else:
		signal_label.text = "搜索中..."
		signal_label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.8, 0.4))


func _update_sos_beacon(_delta: float) -> void:
	if _beacon_revealed or anchor == null:
		return

	var dist: float = player.global_position.distance_to(anchor.global_position)
	if dist > _sos_blink_dist:
		return

	var t: float = fmod(Time.get_ticks_msec() * 0.001, 3.2)
	var beacon_visible: bool = false
	if t < 0.3 or (t >= 0.6 and t < 0.9) or (t >= 1.2 and t < 1.5):
		beacon_visible = true

	hex_poly.visible = beacon_visible
	hex_border.visible = beacon_visible
	rescue_ring.visible = beacon_visible


func _cleanup_hazards() -> void:
	## 清理所有灾害节点（虚假信标、EMI、遮蔽云），防止内存泄露
	for da in _decoy_nodes:
		if da != null and is_instance_valid(da):
			da.queue_free()
	_decoy_nodes.clear()

	for fa in _fog_nodes:
		if fa != null and is_instance_valid(fa):
			fa.queue_free()
	_fog_nodes.clear()

	_emi_zones.clear()
	_in_fog = false


func _cleanup_search_zones() -> void:
	for zd in _search_zones:
		if zd.get("node") != null:
			(zd["node"] as Node).queue_free()
	_search_zones.clear()
	_in_search_zone = false
	_current_search_zone = {}


# ============================================================
# 边界包装（更大的地图：4800 x 3000）
# ============================================================
func _wrap(n: Node2D) -> void:
	const W := 4800.0
	const H := 3000.0
	if n.global_position.x > W / 2.0:  n.global_position.x -= W
	elif n.global_position.x < -W / 2.0: n.global_position.x += W
	if n.global_position.y > H / 2.0:  n.global_position.y -= H
	elif n.global_position.y < -H / 2.0: n.global_position.y += H


# ============================================================
# 重新开始
# ============================================================
func _restart() -> void:
	GameManager.fuel = FUEL_MAX
	GameManager.change_scene("EndlessMode")