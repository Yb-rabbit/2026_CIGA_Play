extends Control
## ============================================================
## LevelSelect — 关卡选择页
## 纯代码构建，动态生成关卡按钮
## ============================================================

# ==================== 字体 ====================
var _font: Font


# ==================== _ready ====================
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

	_font = load("res://YuFanDanQingSong.otf") as Font

	# 背景音乐（原版曲目，选关页面共享）
	_build_menu_bgm()

	# 纯黑背景
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.02, 0.02, 0.06, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# ---- 页面标题 ----
	var title := Label.new()
	title.name = "Title"
	title.text = "选择目标日志"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0, 0.9))
	title.add_theme_font_override("font", _font)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-300, 230)
	title.size = Vector2(600, 80)
	add_child(title)

	# ---- 关卡列表容器 (GridContainer) ----
	var grid := GridContainer.new()
	grid.name = "LevelGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)

	# 生成 3 个关卡按钮
	for level_id: int in range(1, 4):
		var card := _make_level_card(level_id)
		grid.add_child(card)

	# 居中放置 grid
	grid.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grid.position = Vector2(-240, -100)
	add_child(grid)

	# ---- 返回按钮 ----
	var back_btn := _make_small_button("返回主菜单", _on_back)
	back_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	back_btn.position = Vector2(-100, -184)
	back_btn.size = Vector2(200, 48)
	add_child(back_btn)


# ============================================================
# 关卡卡片工厂
# ============================================================
func _make_level_card(level_id: int) -> Control:
	var card := Control.new()
	card.name = "LevelCard_%d" % level_id
	card.custom_minimum_size = Vector2(160, 200)
	card.size = Vector2(160, 200)

	# 用 Button 作为点击层（Child 在最上，接收所有鼠标事件）
	var btn := Button.new()
	btn.name = "CardBtn"
	btn.size = Vector2(160, 200)
	btn.flat = true
	card.add_child(btn)

	# 卡片背景色（子节点穿透鼠标）
	var bg := ColorRect.new()
	bg.name = "CardBG"
	bg.size = Vector2(160, 200)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)

	# 关卡数字标签
	var label := Label.new()
	label.name = "LevelLabel"
	label.text = str(level_id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_font_override("font", _font)
	label.size = Vector2(160, 130)
	label.position = Vector2(0, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)

	# 关卡描述标签
	var desc := Label.new()
	desc.name = "LevelDesc"
	desc.text = "日志 %d" % level_id
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 32)
	desc.add_theme_font_override("font", _font)
	desc.size = Vector2(160, 32)
	desc.position = Vector2(0, 135)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc)

	var unlocked: bool = GameManager.is_level_unlocked(level_id)

	if unlocked:
		# 已解锁 → 金色
		bg.color = Color(0.15, 0.12, 0.05, 0.95)
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
		desc.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3, 0.8))
		btn.pressed.connect(_on_level_selected.bind(level_id))
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		# 未解锁 → 灰色，不显示文字
		bg.color = Color(0.08, 0.08, 0.1, 0.9)
		label.visible = false
		desc.visible = false
		btn.disabled = true
		btn.mouse_default_cursor_shape = Control.CURSOR_ARROW

	return card


# ============================================================
# 小型按钮工厂
# ============================================================
func _make_small_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_font_override("font", _font)
	btn.add_theme_color_override("font_color", Color.WHITE)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.06, 0.1, 0.18, 0.85)
	normal_style.border_width_left = 1
	normal_style.border_width_right = 1
	normal_style.border_width_top = 1
	normal_style.border_width_bottom = 1
	normal_style.border_color = Color(0.3, 0.5, 0.8, 0.4)
	normal_style.corner_radius_top_left = 6
	normal_style.corner_radius_top_right = 6
	normal_style.corner_radius_bottom_left = 6
	normal_style.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.1, 0.15, 0.28, 0.9)
	hover_style.border_color = Color(0.5, 0.7, 1.0, 0.7)
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.pressed.connect(callback)
	return btn


# ============================================================
# 回调
# ============================================================
func _on_level_selected(level_id: int) -> void:
	GameManager.current_level = level_id
	GameManager.change_scene("StoryIntro")


func _on_back() -> void:
	GameManager.change_scene("MainMenu")


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
