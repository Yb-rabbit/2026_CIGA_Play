extends Control
## ============================================================
## MainMenu — 标题页
## 纯代码构建所有 UI 元素，不依赖外部素材
## ============================================================

# ==================== 字体 ====================
var _font: Font

# ==================== _ready — 构建主菜单 ====================
func _ready() -> void:
	# 全屏铺满（动态构建时也可能尺寸为 0，需显式设置）
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

	# 纯黑背景
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

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

	# ---- 副标题 ----
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "盲飞救援"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 36)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9, 0.7))
	subtitle.add_theme_font_override("font", _font)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	subtitle.position = Vector2(-400, 370)
	subtitle.size = Vector2(800, 180)
	add_child(subtitle)

	# ---- "开始游戏" 按钮 ----
	var start_btn := _make_button("开始游戏", _on_start_game)
	start_btn.position = Vector2(
		(get_viewport().get_visible_rect().size.x - 320) / 2.0,
		580.0
	)
	add_child(start_btn)

	# ---- "退出游戏" 按钮 ----
	var exit_btn := _make_button("退出游戏", _on_exit_game)
	exit_btn.position = Vector2(
		(get_viewport().get_visible_rect().size.x - 320) / 2.0,
		730.0
	)
	exit_btn.modulate = Color(0.8, 0.6, 0.6, 1.0)
	add_child(exit_btn)

	# 背景音乐（原版曲目，主菜单专用）
	_build_menu_bgm()

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

	# 按钮样式：深色背景 + 边框
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


# ============================================================
# 按钮回调
# ============================================================
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