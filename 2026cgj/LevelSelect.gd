extends Control
## ============================================================
## LevelSelect — 关卡选择页
## 纯代码构建，动态生成关卡按钮
## ============================================================

# ==================== 字体 ====================
var _font: Font
var _grid: GridContainer = null


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
	grid.columns = 5  # 5 列：关卡 1/2/3 + 无尽模式 + WIN 表彰
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)

	# 生成 3 个关卡按钮
	for level_id: int in range(1, 4):
		var card := _make_level_card(level_id)
		grid.add_child(card)

	# 无尽模式卡片（始终显示，未解锁时灰色锁定）
	var endless_card := _make_endless_card()
	grid.add_child(endless_card)

	# WIN 表彰卡片（三关通关后解锁，播放 flute 曲目 + 表彰文本）
	var win_card := _make_win_card()
	grid.add_child(win_card)

	# 居中放置 grid
	grid.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grid.position = Vector2(-410, -100)
	add_child(grid)
	_grid = grid

	# ---- 关卡评级标签（独立于 GridContainer，放在整个页面下方） ----
	# 计算 grid 在屏幕中的起始位置
	var grid_start_x := 800.0 - 410.0  # 视口中心 + grid 偏移
	var grid_start_y := 450.0 - 100.0  # 视口中心 + grid 偏移
	const CARD_W := 160.0
	const CARD_GAP := 20.0

	for level_id: int in range(1, 4):
		if not GameManager.is_level_unlocked(level_id):
			continue

		# 该关卡的列索引（0, 1, 2）
		var col: int = level_id - 1
		var card_x: float = grid_start_x + float(col) * (CARD_W + CARD_GAP)

		# 构建时间标签（双行，与卡片左对齐，同宽 160px）
		var bt := GameManager.get_best_time(level_id)
		var time_label := Label.new()
		time_label.name = "RatingTime_%d" % level_id
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_label.add_theme_font_size_override("font_size", 26)
		time_label.add_theme_font_override("font", _font)
		time_label.size = Vector2(CARD_W, 72)
		time_label.position = Vector2(card_x, grid_start_y + 287)

		if bt > 0.0:
			time_label.text = _format_time(bt)
			time_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.5, 0.8))
		else:
			time_label.text = "日志长度\n--"
			time_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4, 0.6))
		add_child(time_label)

		# 构建航程标签（双行，与卡片左对齐，同宽 160px）
		var bd := GameManager.get_best_distance(level_id)
		var dist_label := Label.new()
		dist_label.name = "RatingDist_%d" % level_id
		dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dist_label.add_theme_font_size_override("font_size", 26)
		dist_label.add_theme_font_override("font", _font)
		dist_label.size = Vector2(CARD_W, 72)
		dist_label.position = Vector2(card_x, grid_start_y + 367)

		if bd > 0.0:
			dist_label.text = "航程\n%.0f 单位" % bd
			dist_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.5, 0.8))
		else:
			dist_label.text = "航程\n--"
			dist_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4, 0.6))
		add_child(dist_label)

	# ---- 返回按钮 ----
	var back_btn := _make_small_button("返回主菜单", _on_back)
	back_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	back_btn.position = Vector2(-100, -184)
	back_btn.size = Vector2(200, 48)
	add_child(back_btn)


# ============================================================
# _input — F12 开发者工具
# ============================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_open_dev_tools()


func _open_dev_tools() -> void:
	var DevToolsClass := load("res://DevTools.gd") as GDScript
	var dev_tools: Node = DevToolsClass.new()
	add_child(dev_tools)


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
	var completed: bool = (level_id in GameManager.completed_levels)

	if unlocked:
		# 已解锁 → 金色；已完成 → 绿色边框
		bg.color = Color(0.15, 0.12, 0.05, 0.95)
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
		desc.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3, 0.8))

		if completed:
			# 已完成关卡：添加绿色勾号
			var check_mark := Label.new()
			check_mark.name = "CheckMark"
			check_mark.text = "✓"
			check_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			check_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			check_mark.add_theme_font_size_override("font_size", 36)
			check_mark.add_theme_font_override("font", _font)
			check_mark.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4, 0.9))
			check_mark.size = Vector2(40, 40)
			check_mark.position = Vector2(120, -8)
			check_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(check_mark)

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
# 无尽模式卡片工厂
# ============================================================
func _make_endless_card() -> Control:
	var card := Control.new()
	card.name = "EndlessCard"
	card.custom_minimum_size = Vector2(160, 200)
	card.size = Vector2(160, 200)

	# 用 Button 作为点击层
	var btn := Button.new()
	btn.name = "CardBtn"
	btn.size = Vector2(160, 200)
	btn.flat = true
	card.add_child(btn)

	# 卡片背景
	var bg := ColorRect.new()
	bg.name = "CardBG"
	bg.size = Vector2(160, 200)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)

	# ∞ 符号标签
	var label := Label.new()
	label.name = "EndlessLabel"
	label.text = "∞"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 72)
	label.add_theme_font_override("font", _font)
	label.size = Vector2(160, 130)
	label.position = Vector2(0, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)

	# 描述标签
	var desc := Label.new()
	desc.name = "EndlessDesc"
	desc.text = "无尽深空"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 26)
	desc.add_theme_font_override("font", _font)
	desc.size = Vector2(160, 32)
	desc.position = Vector2(0, 135)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc)

	var unlocked := GameManager.endless_unlocked

	if unlocked:
		# 已解锁 → 金色
		bg.color = Color(0.18, 0.14, 0.02, 0.95)
		label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.1, 1.0))
		desc.add_theme_color_override("font_color", Color(1.0, 0.7, 0.15, 0.9))
		btn.pressed.connect(_on_endless_selected)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		# 未解锁 → 灰色背景但 ∞ 和文字依然可见（提示玩家这里有东西）
		bg.color = Color(0.08, 0.08, 0.12, 0.9)
		label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.35, 0.6))
		desc.add_theme_color_override("font_color", Color(0.3, 0.3, 0.35, 0.5))
		btn.disabled = true
		btn.mouse_default_cursor_shape = Control.CURSOR_ARROW

	return card


# ============================================================
# WIN 表彰卡片工厂
# ============================================================
func _make_win_card() -> Control:
	var card := Control.new()
	card.name = "WinCard"
	card.custom_minimum_size = Vector2(160, 200)
	card.size = Vector2(160, 200)

	var btn := Button.new()
	btn.name = "CardBtn"
	btn.size = Vector2(160, 200)
	btn.flat = true
	card.add_child(btn)

	var bg := ColorRect.new()
	bg.name = "CardBG"
	bg.size = Vector2(160, 200)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)

	# "WIN" 标签
	var label := Label.new()
	label.name = "WinLabel"
	label.text = "WIN"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_font_override("font", _font)
	label.size = Vector2(160, 130)
	label.position = Vector2(0, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)

	# 描述标签
	var desc := Label.new()
	desc.name = "WinDesc"
	desc.text = "通关表彰"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 22)
	desc.add_theme_font_override("font", _font)
	desc.size = Vector2(160, 32)
	desc.position = Vector2(0, 135)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc)

	# WIN 卡片解锁条件：全部三关通关后可用（与无尽模式同步）
	var unlocked := GameManager.endless_unlocked

	if unlocked:
		# 已解锁 → 金色渐变
		bg.color = Color(0.16, 0.13, 0.02, 0.95)
		label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.1, 1.0))
		desc.add_theme_color_override("font_color", Color(1.0, 0.7, 0.15, 0.9))
		btn.pressed.connect(_on_win_selected)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		# 未解锁 → 灰色但仍可见轮廓（提示玩家还有内容）
		bg.color = Color(0.08, 0.08, 0.12, 0.9)
		label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.35, 0.5))
		desc.add_theme_color_override("font_color", Color(0.3, 0.3, 0.35, 0.4))
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
# 时间格式化
# ============================================================
func _format_time(seconds: float) -> String:
	## 将秒数格式化为双行 "日志长度\n时:分:秒" 格式
	var total_secs: int = int(seconds)
	var hrs: int = total_secs / 3600
	var mins: int = (total_secs % 3600) / 60
	var secs: int = total_secs % 60
	return "日志长度\n%02d:%02d:%02d" % [hrs, mins, secs]


# ============================================================
# 回调
# ============================================================
func _on_level_selected(level_id: int) -> void:
	GameManager.current_level = level_id
	GameManager.change_scene("StoryIntro")


func _on_endless_selected() -> void:
	# 无尽模式：先显示前置故事（flute 曲目），之后直接进入无尽深空
	GameManager.current_level = 99
	GameManager.change_scene("PreEndlessStory")


func _on_win_selected() -> void:
	# WIN 表彰：播放 flute 曲目 + 通关庆祝故事，结束后返回选关页面
	GameManager.change_scene("WinStory")


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


func refresh_cards() -> void:
	## 重建所有卡片和评级标签，反映最新完成状态（供 DevTools 调用）
	if _grid == null:
		return
	# 清除旧评级标签
	for child in get_children():
		var cn := child.name as String
		if cn.begins_with("RatingTime_") or cn.begins_with("RatingDist_"):
			child.queue_free()
	# 清除旧卡片
	for child in _grid.get_children():
		child.queue_free()
	# 重建卡片
	for level_id: int in range(1, 4):
		_grid.add_child(_make_level_card(level_id))
	_grid.add_child(_make_endless_card())
	_grid.add_child(_make_win_card())
	# 后处理：重建评级标签
	await get_tree().process_frame
	var grid_start_x := 800.0 - 410.0
	var grid_start_y := 450.0 - 100.0
	const CARD_W := 160.0
	const CARD_GAP := 20.0
	for level_id: int in range(1, 4):
		if not GameManager.is_level_unlocked(level_id):
			continue
		var col: int = level_id - 1
		var card_x: float = grid_start_x + float(col) * (CARD_W + CARD_GAP)
		var bt := GameManager.get_best_time(level_id)
		var time_label := Label.new()
		time_label.name = "RatingTime_%d" % level_id
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_label.add_theme_font_size_override("font_size", 26)
		time_label.add_theme_font_override("font", _font)
		time_label.size = Vector2(CARD_W, 72)
		time_label.position = Vector2(card_x, grid_start_y + 287)
		if bt > 0.0:
			time_label.text = _format_time(bt)
			time_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.5, 0.8))
		else:
			time_label.text = "日志长度\n--"
			time_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4, 0.6))
		add_child(time_label)
		var bd := GameManager.get_best_distance(level_id)
		var dist_label := Label.new()
		dist_label.name = "RatingDist_%d" % level_id
		dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dist_label.add_theme_font_size_override("font_size", 26)
		dist_label.add_theme_font_override("font", _font)
		dist_label.size = Vector2(CARD_W, 72)
		dist_label.position = Vector2(card_x, grid_start_y + 367)
		if bd > 0.0:
			dist_label.text = "航程\n%.0f 单位" % bd
			dist_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.5, 0.8))
		else:
			dist_label.text = "航程\n--"
			dist_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4, 0.6))
		add_child(dist_label)
