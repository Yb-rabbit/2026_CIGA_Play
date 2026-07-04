extends Node2D
## ============================================================
## GameScene — 核心游戏关卡
## 重构自 game.gd，适配多场景架构 + GameManager 全局单例
## 新增 S 级难度系统：虚假信标、电磁干扰区、信号遮蔽云
## ============================================================

# ==================== 信号 ====================
## 扫描完成信号：has_beacon=true 表示找到信标，false 表示空圈
signal scan_completed(has_beacon: bool)
## 风暴增强信号：level 表示当前风暴等级（1, 2, 3...）
signal storm_intensified(level: int)

# ==================== 关卡参数 ====================
const RESCUES_PER_LEVEL: int = 4             # 每关需要救援次数
const FUEL_MAX: float = 100.0                 # 最大燃料
const FUEL_BURN: float = 10.0                # W 键每秒油耗（降低，给警告系统更多应用空间）
const FUEL_REFILL: float = 40.0              # 救援成功回油量

# ==================== 风场 ====================
var wind_vector: Vector2 = Vector2.ZERO       # 初始无风（渐进式）
var _wind_active: bool = false
var _first_rescue_done: bool = false
const BASE_WIND: float = 80.0                 # 基础风力

# ==================== 飞行参数 ====================
const THRUST: float = 320.0
const BRAKE: float = 200.0
const ROT_ACCEL: float = 20.0
const ROT_DRAG: float = 0.80
const LIN_DRAG: float = 0.992
const MAX_SPD: float = 420.0

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

# 速度矢量虚线系统
const DASH_COUNT := 8
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
var _tutorial_label: Label = null
var _storm_label: Label = null           # 风暴警报（系统 UI）
var _storm_timer: float = 0.0            # 风暴提示残留计时器
var _onboard_system: Node = null         # 飞控电脑节点
var _bgm_player: AudioStreamPlayer = null # 背景音乐播放器

# 锚点系统
var anchor_node: Node2D = null
var anchor_active: bool = false
const ANCHOR_RADIUS: float = 150.0
const ANCHOR_FUEL_COST: float = 5.0
var anchor_circle_poly: Polygon2D
var anchor_dash_node: Node2D

# ==================== S 级难度系统 ====================
# 虚假信标 (Decoy — 紫色六边形+X)
var _decoy_nodes: Array[Area2D] = []
const DECOY_FUEL_DRAIN: float = 22.0
const DECOY_KNOCKBACK: float = 520.0

# 电磁干扰区 (EMI — 罗盘抖动 + 信号乱码)
var _emi_zones: Array[Dictionary] = []

# 信号遮蔽云 (Fog — 罗盘完全失效)
var _fog_nodes: Array[Area2D] = []
var _in_fog: bool = false
var _fog_draw_node: Node2D

# ==================== 搜索圈 + 扫描锁定系统 ====================
## SearchZone 数组：每个字典包含 { "node": Area2D, "has_beacon": bool, "radius": float }
var _search_zones: Array[Dictionary] = []
var _in_search_zone: bool = false                   # 飞船当前是否在搜索圈内
var _current_search_zone: Dictionary = {}           # 当前所在的搜索圈
var _beacon_revealed: bool = false                   # 信标是否已被锁定并显示
var _scan_timer: float = 0.0                         # 扫描计时器（按住 W 累计）
const SCAN_DURATION: float = 0.8                     # 扫描需要按住 W 的秒数
var _is_scanning: bool = false                       # 是否正在进行扫描
var _compass_locked: bool = false                    # 罗盘是否已锁定目标
var _search_zones_draw_node: Node2D                  # 搜索圈绘制节点

# ==================== 推进音效 ====================
var _thrust_stream: AudioStreamPlayer
var _thrust_stream_pb: AudioStreamGeneratorPlayback
var _thrust_samples_left: int = 0
const _thrust_sample_total: int = 0  # 从 .wav 计算
var _thrust_audio_data: PackedFloat32Array

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


# ============================================================
# _ready — 构建一切 + 同步 GameManager 状态
# ============================================================
func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.02, 0.04, 0.16, 1.0))

	# ---- 从 GameManager 同步初始化数据 ----
	GameManager.set_game_state(GameManager.GameState.PLAYING)

	if GameManager.fuel <= 0.0:
		GameManager.fuel = FUEL_MAX
	else:
		GameManager.fuel = minf(GameManager.fuel, FUEL_MAX)

	# 风力初始化：渐进式——关卡1从零风开始
	var level := GameManager.current_level
	var wind_mult: float = 1.0 + float(level - 1) * 0.5
	if level == 1:
		wind_vector = Vector2.ZERO
		_wind_active = false
	else:
		var na: float = randf_range(0.0, TAU)
		wind_vector = Vector2.RIGHT.rotated(na) * BASE_WIND * wind_mult
		_wind_active = true

	# 构建场景（顺序至关重要：player 必须在 hazards 之前）
	_build_stars()

	trail_node = Node2D.new()
	trail_node.name = "TrailNode"
	add_child(trail_node)
	trail_node.draw.connect(_draw_trail)

	_build_player()        # 1. 先创建 player（hazards 依赖 player.position）
	_build_camera()
	_build_anchor()
	_spawn_anchor()        # 2. 先生成信标，确定最终位置
	_build_search_zones()  # 3. 搜索圈基于信标实际位置（确保至少 1 个圈包含它）
	_build_hazards()       # 4. 再创建虚假信标/EMI/遮蔽云
	_build_ui()

	# 搜索圈绘制节点
	_search_zones_draw_node = Node2D.new()
	_search_zones_draw_node.name = "SearchZonesDraw"
	add_child(_search_zones_draw_node)
	_search_zones_draw_node.draw.connect(_draw_search_zones)

	# 信标初始隐藏，搜索圈引导玩家扫描锁定
	_anchor_set_visible(false)
	_compass_locked = false

	anchor_dash_node = Node2D.new()
	anchor_dash_node.name = "AnchorDash"
	add_child(anchor_dash_node)
	anchor_dash_node.draw.connect(_draw_anchor_dash)

	_fog_draw_node = Node2D.new()
	_fog_draw_node.name = "FogDraw"
	add_child(_fog_draw_node)

	_build_audio()
	_build_thrust_audio()

	score_label.text = "救援: %d" % _session_score
	_update_fuel()

	# ---- 机载飞控电脑 ----
	var obd := load("res://OnboardSystem.gd") as GDScript
	var obd_node: Node = Node.new()
	obd_node.set_script(obd)
	obd_node.name = "OnboardSystem"
	add_child(obd_node)
	_onboard_system = obd_node

	# ---- 风暴警报 UI ----
	_build_storm_ui()

	# ---- 背景音乐 ----
	_build_bgm()

	if level == 1:
		_spawn_tutorial_hint()

	# ---- 创建无线电通讯系统 ----
	var RadioAdvisorClass := load("res://RadioAdvisor.gd") as GDScript
	var radio: Node = RadioAdvisorClass.new()
	radio.name = "RadioAdvisor"
	radio._game_scene = self
	add_child.call_deferred(radio)


# ============================================================
# 背景音乐 — stage1(dm).ogg 自动循环，剧情/暂停时降低响度
# ============================================================
func _build_bgm() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMusic"
	_bgm_player.bus = "Master"
	_bgm_player.volume_db = -8.0  # 默认音量
	add_child(_bgm_player)

	# 加载关卡内循环曲目 stage1(2.0).ogg
	_bgm_load_and_play("res://stage1(2.0).ogg")

	if _bgm_player.stream == null:
		# 回退：尝试原版曲目
		_bgm_load_and_play("res://stage1(dm).ogg")


func _bgm_load_and_play(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	_bgm_player.stream = stream
	if not stream is AudioStreamInteractive:
		_bgm_player.finished.connect(_bgm_loop)
	_bgm_player.play()


func _bgm_loop() -> void:
	# 重播实现循环
	if _bgm_player != null:
		_bgm_player.play()


func _bgm_duck(to_db: float) -> void:
	## 动态降低/恢复 BGM 音量（单位：dB）
	if _bgm_player == null:
		return
	var tw := create_tween()
	tw.tween_property(_bgm_player, "volume_db", to_db, 0.4).set_ease(Tween.EASE_OUT)


# ============================================================
# _input — S 键抛锚 / ESC 暂停
# ============================================================
func _input(event: InputEvent) -> void:
	if _game_over:
		return

	if event.is_action_pressed("ui_down") and not event.is_echo():
		_do_anchor_drop()

	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_open_pause_menu()
		get_viewport().set_input_as_handled()


# ============================================================
# 暂停菜单
# ============================================================
func _open_pause_menu() -> void:
	var PauseMenuClass := load("res://PauseMenu.gd") as GDScript
	var pause_menu: Node = PauseMenuClass.new()
	add_child(pause_menu)


# ============================================================
# 教学提示 (关卡 1 专属)
# ============================================================
func _spawn_tutorial_hint() -> void:
	_tutorial_label = Label.new()
	_tutorial_label.name = "TutorialHint"
	_tutorial_label.text = "A/D 旋转飞船 | W 加速推进 | S 减速/抛锚\n将红色罗盘指针指向正上方，找到信标！"
	_tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_label.add_theme_font_size_override("font_size", 30)
	_tutorial_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0, 0.9))
	_tutorial_label.add_theme_font_override("font", _font)
	_tutorial_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_tutorial_label.position = Vector2(-450, 400)
	_tutorial_label.size = Vector2(900, 80)
	add_child(_tutorial_label)
	var tw := create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(_tutorial_label, "modulate:a", 0.0, 2.0)
	tw.tween_callback(_tutorial_label.queue_free)


# ============================================================
# 玩家
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
# 虚假信标 — 构建
# ============================================================
func _build_decoy(dpos: Vector2) -> Area2D:
	var da := Area2D.new()
	da.name = "DecoyBeacon"
	da.global_position = dpos

	var col_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 40.0
	col_shape.shape = circle
	da.add_child(col_shape)

	# 紫色六边形
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

	# X 标记
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


# ============================================================
# 信号遮蔽云 — 构建
# ============================================================
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
# 灾害系统 — 构建
# ============================================================
func _build_hazards() -> void:
	var level := GameManager.current_level

	# ---- 虚假信标 ----
	var decoy_count: int
	match level:
		1: decoy_count = 1
		2: decoy_count = 3
		_: decoy_count = 5

	for i: int in range(decoy_count):
		var da: float = randf_range(0.0, TAU)
		var dd: float = randf_range(400.0, 800.0)
		var dpos := player.position + Vector2.RIGHT.rotated(da) * dd
		var decoy := _build_decoy(dpos)
		add_child(decoy)
		_decoy_nodes.append(decoy)

	# ---- 电磁干扰区 ----
	var emi_count: int
	match level:
		1: emi_count = 1
		2: emi_count = 2
		_: emi_count = 3

	for i: int in range(emi_count):
		var ea: float = randf_range(0.0, TAU)
		var ed: float = randf_range(500.0, 1000.0)
		_emi_zones.append({
			"pos": player.position + Vector2.RIGHT.rotated(ea) * ed,
			"radius": randf_range(220.0, 350.0),
			"seed": randf_range(0.0, TAU)
		})

	# ---- 信号遮蔽云 ----
	var fog_count: int
	match level:
		1: fog_count = 1
		2: fog_count = 2
		_: fog_count = 3

	for i: int in range(fog_count):
		var fa: float = randf_range(0.0, TAU)
		var fd: float = randf_range(600.0, 900.0)
		var fcenter := player.position + Vector2.RIGHT.rotated(fa) * fd
		var fradius: float = randf_range(100.0, 150.0)
		var fog := _build_fog_cloud(fcenter, fradius)
		fog.set_meta("fog_radius", fradius)
		add_child(fog)
		_fog_nodes.append(fog)


# ============================================================
# 虚假信标碰撞回调
# ============================================================
func _on_decoy_collision(body: Node2D) -> void:
	if body != player or _game_over:
		return
	GameManager.fuel = maxf(0.0, GameManager.fuel - DECOY_FUEL_DRAIN)
	if GameManager.fuel <= 0.0:
		GameManager.fuel = 0.0
		_on_game_over_fuel()
		return
	var away: Vector2 = (player.global_position - body.global_position).normalized()
	if away.length() < 0.1:
		away = Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	player.velocity += away * DECOY_KNOCKBACK
	_show_hint_text("赝品信标！燃料 -%d" % int(DECOY_FUEL_DRAIN))
	_update_fuel()


# ============================================================
# 遮蔽云 — 进入/离开
# ============================================================
func _on_fog_entered(body: Node2D) -> void:
	if body == player:
		_in_fog = true

func _on_fog_exited(body: Node2D) -> void:
	if body == player:
		_in_fog = false


# ============================================================
# 推进音效
# ============================================================
func _build_thrust_audio() -> void:
	_thrust_stream = AudioStreamPlayer.new()
	_thrust_stream.name = "ThrustStream"
	add_child(_thrust_stream)

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = AUDIO_SAMPLE_RATE
	gen.buffer_length = 0.05
	_thrust_stream.stream = gen
	_thrust_stream.volume_db = -8.0
	_thrust_stream.play()

	_thrust_stream_pb = _thrust_stream.get_stream_playback()

	# 尝试加载 Power_Put.wav 并转换为样本数据
	if ResourceLoader.exists("res://Power_Put.wav"):
		var wav_file := FileAccess.open("res://Power_Put.wav", FileAccess.READ)
		if wav_file != null:
			var raw_bytes: PackedByteArray = wav_file.get_buffer(wav_file.get_length())
			wav_file.close()
			# 跳过 WAV 头（44 字节），读取 16-bit PCM 数据
			if raw_bytes.size() > 44:
				var pcm16 := PackedByteArray()
				for i: int in range(44, raw_bytes.size() - 1):
					pcm16.append(raw_bytes[i])
				# 解码为 float
				var samples := PackedFloat32Array()
				for i: int in range(0, pcm16.size() - 1, 2):
					var s16: int = pcm16[i] | (pcm16[i + 1] << 8)
					if s16 >= 32768:
						s16 -= 65536
					samples.append(float(s16) / 32768.0)
				_thrust_audio_data = samples


# ============================================================
# UI (CanvasLayer)
# ============================================================
func _build_ui() -> void:
	_font = load("res://YuFanDanQingSong.otf") as Font

	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	# ---- 罗盘 (右上) ----
	var cc := Control.new()
	cc.name = "Compass"
	cc.position = Vector2(1600 - 204, 14)
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
	fl.add_theme_font_override("font", _font)
	ui.add_child(fl)

	# ---- 分数 ----
	score_label = Label.new()
	score_label.position = Vector2(20, 78)
	score_label.text = "救援: 0"
	score_label.add_theme_font_size_override("font_size", 36)
	score_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 0.9))
	score_label.add_theme_font_override("font", _font)
	ui.add_child(score_label)

	# ---- 距离 ----
	dist_label = Label.new()
	dist_label.position = Vector2(1600 - 224, 210)
	dist_label.size = Vector2(190, 28)
	dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_label.add_theme_font_size_override("font_size", 26)
	dist_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 0.7))
	dist_label.add_theme_font_override("font", _font)
	ui.add_child(dist_label)

	# ---- 信号报告 ----
	signal_label = Label.new()
	signal_label.position = Vector2(1600 - 224, 240)
	signal_label.size = Vector2(190, 32)
	signal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	signal_label.add_theme_font_size_override("font_size", 24)
	signal_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 0.0))
	signal_label.add_theme_font_override("font", _font)
	signal_label.text = "搜索中..."
	ui.add_child(signal_label)

	# ---- 操作提示 (底部中央) ----
	hint_label = Label.new()
	hint_label.anchors_preset = Control.PRESET_CENTER_BOTTOM
	hint_label.position = Vector2(-280, -36)
	hint_label.size = Vector2(560, 30)
	hint_label.text = "A/D 旋转 | W 加速 | S 抛锚/减速 | Esc 暂停 | 指针指上 = 对准目标"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 28)
	hint_label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.9, 0.7))
	hint_label.add_theme_font_override("font", _font)
	ui.add_child(hint_label)

	# ---- Game Over ----
	game_over_label = Label.new()
	game_over_label.visible = false
	game_over_label.text = "燃料耗尽...\n按 R 重新开始"
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
	var d: float = randf_range(300.0, 550.0)
	anchor.global_position = player.global_position + Vector2.RIGHT.rotated(a) * d
	_wrap(anchor)
	hex_poly.scale = Vector2.ONE
	hex_border.scale = Vector2.ONE
	rescue_ring.scale = Vector2.ONE


# ============================================================
# 风暴警报 UI（顶部横幅）
# ============================================================
func _build_storm_ui() -> void:
	_storm_label = Label.new()
	_storm_label.name = "StormAlert"
	_storm_label.text = ""
	_storm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_storm_label.add_theme_font_size_override("font_size", 28)
	_storm_label.add_theme_font_override("font", _font)
	_storm_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_storm_label.position = Vector2(-500, 420)
	_storm_label.size = Vector2(1000, 40)
	_storm_label.modulate.a = 0.0
	# 加入 UI CanvasLayer（必须在 _build_ui 之后调用，所以通过查找已有 UI 层）
	# 先存起来，在 _build_ui 创建的 ui 容器里添加
	call_deferred("_add_storm_label_to_ui")


func _add_storm_label_to_ui() -> void:
	# 找到 UI CanvasLayer 并添加风暴标签
	for child in get_children():
		if child is CanvasLayer and child.name == "UI":
			child.add_child(_storm_label)
			return


func _show_storm_warning(msg: String) -> void:
	if _storm_label == null:
		return
	_storm_label.text = msg
	_storm_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.1, 1.0))
	_storm_label.modulate.a = 1.0
	_storm_timer = 4.0  # 显示 4 秒后渐隐


func _update_storm_label(delta: float) -> void:
	if _storm_timer <= 0.0:
		return
	_storm_timer -= delta
	# 最后一秒渐隐
	if _storm_timer < 1.0 and _storm_timer > 0.0:
		_storm_label.modulate.a = _storm_timer  # 1.0 → 0.0
	elif _storm_timer <= 0.0:
		_storm_label.modulate.a = 0.0


# ============================================================
# 救援成功
# ============================================================
func _on_rescue(_b: Node2D) -> void:
	if _game_over or rescuing:
		return
	rescuing = true
	_rescue_count += 1
	_session_score += int(100 + _rescue_count * 15)

	GameManager.fuel = minf(FUEL_MAX, GameManager.fuel + FUEL_REFILL)
	if _session_score > GameManager.high_score:
		GameManager.high_score = _session_score

	score_label.text = "救援: %d" % _session_score

	# 渐进式风力
	var level := GameManager.current_level
	if level == 1 and not _first_rescue_done:
		_first_rescue_done = true
		_wind_active = true
		var wind_mult: float = 1.0
		var fraction: float = 0.3 + float(_rescue_count) * 0.35
		var na: float = randf_range(0.0, TAU)
		wind_vector = Vector2.RIGHT.rotated(na) * BASE_WIND * wind_mult * fraction
		_show_storm_warning("⚠ 警告：电磁风暴正在增强！")
		storm_intensified.emit(_rescue_count)
	else:
		var na: float = randf_range(0.0, TAU)
		var wind_mult: float = 1.0 + float(level - 1) * 0.5
		var ns: float = BASE_WIND * wind_mult + float(_rescue_count) * 25.0
		wind_vector = Vector2.RIGHT.rotated(na) * ns
		if not _first_rescue_done and _rescue_count >= 1:
			storm_intensified.emit(_rescue_count)

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
	if _rescue_count >= RESCUES_PER_LEVEL:
		_level_complete()
	else:
		_spawn_anchor()
		rescuing = false


func _level_complete() -> void:
	GameManager.high_score = maxi(GameManager.high_score, _session_score)
	GameManager.complete_level(GameManager.current_level)
	await get_tree().create_timer(0.8).timeout
	GameManager.change_scene("LevelSelect")


# ============================================================
# Game Over / Restart
# ============================================================
func _on_game_over_fuel() -> void:
	_game_over = true
	game_over_label.text = "燃料耗尽...\n按 R 重新开始\n按 M 返回主菜单"
	game_over_label.visible = true
	if hint_label != null:
		hint_label.text = "按 R 重新开始  |  M 返回主菜单"
	flame_poly.visible = false


func _restart() -> void:
	GameManager.fuel = FUEL_MAX
	GameManager.change_scene("GameScene")


func _go_to_main_menu() -> void:
	GameManager.fuel = FUEL_MAX
	GameManager.change_scene("MainMenu")


# ============================================================
# 主循环 (_physics_process)
# ============================================================
func _physics_process(delta: float) -> void:
	if _game_over:
		_update_compass()
		return

	var ri: float = Input.get_axis("ui_left", "ui_right")
	angular_velocity += ri * ROT_ACCEL * delta
	angular_velocity *= ROT_DRAG
	player.rotation += angular_velocity * delta

	var thrusting: bool = Input.is_action_pressed("ui_up") and GameManager.fuel > 0.0
	if thrusting:
		var thrust_mult: float = 1.0
		var burn_mult: float = 1.0
		if _onboard_system != null:
			thrust_mult = _onboard_system.get("thrust_multiplier")
			burn_mult = _onboard_system.get("fuel_burn_multiplier")
		player.velocity += Vector2.RIGHT.rotated(player.rotation) * THRUST * thrust_mult * delta
		GameManager.fuel = maxf(0.0, GameManager.fuel - FUEL_BURN * burn_mult * delta)
		# 推进音效
		_fill_thrust_buffer()
		if GameManager.fuel <= 0.0:
			GameManager.fuel = 0.0
			_on_game_over_fuel()

	if Input.is_action_pressed("ui_down"):
		var spd: float = player.velocity.length()
		if spd > 0.0:
			var force: float = minf(BRAKE * delta, spd)
			player.velocity -= player.velocity.normalized() * force

	if _wind_active and not _is_in_anchor_range():
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

	_update_hazards(delta)
	_update_scan(delta)
	_update_compass()
	_update_fuel()
	_update_sos_beacon(delta)
	_update_storm_label(delta)


# ============================================================
# _process — 重试检测 + 音频
# ============================================================
func _process(_delta: float) -> void:
	if _game_over:
		if Input.is_key_pressed(KEY_R):
			_restart()
		elif Input.is_key_pressed(KEY_M):
			_go_to_main_menu()

	if not _game_over and anchor != null and not _in_fog:
		var dist: float = player.global_position.distance_to(anchor.global_position)
		beep_timer -= _delta
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
# 推进力音效填充
# ============================================================
func _fill_thrust_buffer() -> void:
	if _thrust_stream_pb == null or _thrust_audio_data == null or _thrust_audio_data.size() == 0:
		return
	var to_fill: int = _thrust_stream_pb.get_frames_available()
	if to_fill <= 0:
		return
	for _i: int in range(to_fill):
		_thrust_samples_left = (_thrust_samples_left + 1) % _thrust_audio_data.size()
		var val: float = _thrust_audio_data[_thrust_samples_left] * 0.25
		_thrust_stream_pb.push_frame(Vector2(val, val))


# ============================================================
# 灾害更新
# ============================================================
func _update_hazards(_d: float) -> void:
	for da in _decoy_nodes:
		if da == null:
			continue
		da.scale = Vector2(sin(Time.get_ticks_msec() * 0.002) * 0.06 + 1.0, sin(Time.get_ticks_msec() * 0.002) * 0.06 + 1.0)

	_fog_draw_node.draw.connect(_draw_fog_clouds, CONNECT_ONE_SHOT)
	_fog_draw_node.queue_redraw()


func _draw_fog_clouds() -> void:
	for fa in _fog_nodes:
		if fa == null:
			continue
		var r: float = fa.get_meta("fog_radius", 100.0)
		for layer: int in range(3):
			var lr: float = r - float(layer) * 25.0
			if lr < 10.0: continue
			_fog_draw_node.draw_circle(fa.global_position, lr, Color(0.3, 0.35, 0.5, 0.06 + float(layer) * 0.03))


# ============================================================
# 罗盘更新（含 EMI 抖动 + 扫描锁定 + 遮蔽云遮挡）
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

	# 记录 EMI 分量（仅用于判断是否弹乱码文本）
	var emi_jitter: float = jitter_angle

	# 进入搜索圈时—罗盘指针轻微噪声（提示进入搜索模式）
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

	# 仅 EMI 严重干扰时弹乱码（噪声不影响文本）
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


# ============================================================
# 油量条
# ============================================================
func _update_fuel() -> void:
	var r: float = GameManager.fuel / FUEL_MAX
	fuel_fill.size.x = 232.0 * r
	if r > 0.4:          fuel_fill.color = Color(0.2, 0.85, 0.5, 0.9)
	elif r > 0.15:        fuel_fill.color = Color(1.0, 0.7, 0.1, 0.9)
	else:                  fuel_fill.color = Color(1.0, 0.15, 0.1, 0.9)


# ============================================================
# 信号报告
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
# 提示文字（临时弹出）
# ============================================================
func _show_hint_text(msg: String) -> void:
	var ht := Label.new()
	ht.text = msg
	ht.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ht.add_theme_font_size_override("font_size", 36)
	ht.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2, 1.0))
	ht.add_theme_font_override("font", _font)
	ht.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	ht.position = Vector2(-300, 320)
	ht.size = Vector2(600, 50)
	add_child(ht)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(ht.queue_free)


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
# 星空背景
# ============================================================
func _build_stars() -> void:
	star_node = Node2D.new()
	star_node.name = "Stars"
	star_node.z_index = -10
	add_child(star_node)
	_stars.clear()
	_stars_phase.clear()
	for i: int in range(80):
		_stars.append(Vector2(randf_range(-1600.0, 1600.0), randf_range(-1000.0, 1000.0)))
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
	if GameManager.fuel < ANCHOR_FUEL_COST:
		return
	_remove_anchor()
	GameManager.fuel = maxf(0.0, GameManager.fuel - ANCHOR_FUEL_COST)
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
# 搜索圈系统 — 构建 3~4 个半透明巨大圆形 Area2D
# ============================================================
func _build_search_zones() -> void:
	const ZONE_RADIUS: float = 300.0
	var zone_count: int = randi_range(3, 4)

	# 决定哪个圈包含真实信标（随机选一个）
	var beacon_zone_index: int = randi_range(0, zone_count - 1)

	# 生成 anchor 之后才调用此方法，所以 anchor 已有初始位置
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
			# 信标圈：以信标位置为中心（偏移极小），确保信标一定在圈内
			sz.global_position = beacon_pos + Vector2(randf_range(-20, 20), randf_range(-20, 20))
			has_beacon = true
		else:
			# 其他圈：散布在玩家周围较近距离，确保可见
			var a: float = TAU * float(i) / float(zone_count) + randf_range(-0.2, 0.2)
			var d: float = randf_range(300.0, 550.0)
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

		# 连接碰撞信号
		sz.body_entered.connect(_on_search_zone_entered.bind(zone_data))
		sz.body_exited.connect(_on_search_zone_exited.bind(zone_data))

	# 如果随机决定后没有任何圈包含信标，强制第一个圈包含它
	var any_has_beacon: bool = false
	for zd in _search_zones:
		if zd["has_beacon"]:
			any_has_beacon = true
			break
	if not any_has_beacon and _search_zones.size() > 0:
		_search_zones[0]["has_beacon"] = true


# ============================================================
# 搜索圈碰撞回调
# ============================================================
func _on_search_zone_entered(body: Node2D, zone_data: Dictionary) -> void:
	if body != player or _game_over:
		return
	if zone_data.get("scanned", false):
		return  # 已经扫描过的区域不再触发

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


# ============================================================
# 扫描计时器更新（每物理帧调用）
# ============================================================
func _update_scan(delta: float) -> void:
	# 已经锁定信标 → 不再需要扫描
	if _beacon_revealed:
		_is_scanning = false
		return

	# 不在搜索圈内 → 无扫描
	if not _in_search_zone:
		return

	var zd := _current_search_zone
	if zd == null or zd.is_empty() or zd.get("scanned", false):
		return

	# 自动扫描：进入搜索圈后自动累进
	_is_scanning = true
	_scan_timer += delta

	var pct: int = int(clampf(_scan_timer / SCAN_DURATION, 0.0, 1.0) * 100.0)
	signal_label.text = "扫描中... %d%%" % pct
	signal_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.8, 1.0))

	if _scan_timer >= SCAN_DURATION:
		_on_scan_complete()


# ============================================================
# 搜索圈绘制
# ============================================================
func _draw_search_zones() -> void:
	if _search_zones_draw_node == null:
		return
	const SEG := 64
	for zd in _search_zones:
		if zd == null or zd.get("node") == null:
			continue
		var node: Area2D = zd["node"]
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
			# 未扫描 → 蓝色呼吸光晕（更明显）
			_search_zones_draw_node.draw_colored_polygon(pts, Color(0.15, 0.5, 0.9, 0.08 + pulse))
			_search_zones_draw_node.draw_polyline(pts + PackedVector2Array([Vector2(cos(0), sin(0)) * r]), Color(0.3, 0.8, 1.0, 0.5), 2.0)


# ============================================================
# 信标可见性控制
# ============================================================
func _anchor_set_visible(v: bool) -> void:
	## 控制信标视觉元素和罗盘锁定状态
	hex_poly.visible = v
	hex_border.visible = v
	rescue_ring.visible = v
	_beacon_revealed = v
	# 信标始终锁定罗盘（显示后即稳定指向）
	if v:
		_compass_locked = true


# ============================================================
# 扫描完成 — 信标锁定或空圈提示
# ============================================================
func _on_scan_complete() -> void:
	var zd := _current_search_zone
	if zd == null or zd.is_empty():
		return

	# 标记此区域已扫描
	zd["scanned"] = true
	_is_scanning = false

	if zd.get("has_beacon", false):
		# 发现信标！
		scan_completed.emit(true)
		_anchor_set_visible(true)
		_show_hint_text("信号锁定！信标已标记")
		signal_label.text = ">>> 信号锁定 <<<"
		signal_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 1.0))
		# 闪烁消失特效：信标从 0 缩放到 1
		var tw := create_tween()
		tw.tween_property(hex_poly, "scale", Vector2.ONE, 0.4).set_ease(Tween.EASE_OUT)
		hex_poly.scale = Vector2.ZERO
		tw.set_parallel(true)
		tw.tween_property(hex_border, "scale", Vector2.ONE, 0.4).set_ease(Tween.EASE_OUT)
		hex_border.scale = Vector2.ZERO
		tw.tween_property(rescue_ring, "scale", Vector2.ONE, 0.4).set_ease(Tween.EASE_OUT)
		rescue_ring.scale = Vector2.ZERO
		# 扫描到信标后，销毁所有搜索圈
		_cleanup_search_zones()
	else:
		# 空圈
		scan_completed.emit(false)
		_show_hint_text("此区域无救援信号")
		signal_label.text = "搜索中..."
		signal_label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.8, 0.4))


func _update_sos_beacon(_delta: float) -> void:
	## 当玩家距离隐藏信标 ≤ 200 时，信标以 SOS 频率闪烁
	if _beacon_revealed:
		return  # 已锁定则不闪烁

	if anchor == null:
		return

	var dist: float = player.global_position.distance_to(anchor.global_position)
	if dist > 200.0:
		return

	# SOS 节奏：0.3s 亮 → 0.3s 灭 → 0.3s 亮 → 0.3s 灭 → 0.3s 亮 → 0.7s 灭 → 0.7s 灭 → 重复 (周期 3.2s)
	# 简化为 sine 平方波模拟：快闪三下 + 停顿
	var t: float = fmod(Time.get_ticks_msec() * 0.001, 3.2)

	var visible: bool = false
	if t < 0.3 or (t >= 0.6 and t < 0.9) or (t >= 1.2 and t < 1.5):
		visible = true

	hex_poly.visible = visible
	hex_border.visible = visible
	rescue_ring.visible = visible


func _cleanup_search_zones() -> void:
	## 移除所有搜索圈节点（信标锁定后不再需要）
	for zd in _search_zones:
		if zd.get("node") != null:
			(zd["node"] as Node).queue_free()
	_search_zones.clear()
	_in_search_zone = false
	_current_search_zone = {}


# ============================================================
# 边界包装
# ============================================================
func _wrap(n: Node2D) -> void:
	const W := 3200.0
	const H := 2000.0
	if n.global_position.x > W / 2.0:  n.global_position.x -= W
	elif n.global_position.x < -W / 2.0: n.global_position.x += W
	if n.global_position.y > H / 2.0:  n.global_position.y -= H
	elif n.global_position.y < -H / 2.0: n.global_position.y += H
