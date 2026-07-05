extends CanvasLayer
## ============================================================
## DevTools — 开发者跳关工具
## 按 F12 打开/关闭，提供跳关、解锁全部、重置进度
## ============================================================

var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = load("res://YuFanDanQingSong.otf") as Font
	layer = 128

	# 半透明遮罩
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# ---- 居中面板（左侧：按钮操作） ----
	var panel := Panel.new()
	panel.name = "Panel"
	panel.size = Vector2(420, 700)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.06, 0.14, 0.92)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.3, 0.65, 1.0, 0.5)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", panel_style)

	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-420, -310)  # 左移，给右侧面板腾空间
	add_child(panel)

	# ---- 标题 ----
	var title := Label.new()
	title.name = "Title"
	title.text = "开发者工具"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0, 0.9))
	title.add_theme_font_override("font", _font)
	title.size = Vector2(380, 50)
	title.position = Vector2(20, 14)
	panel.add_child(title)

	# ---- 分隔线 ----
	var sep := HSeparator.new()
	sep.name = "Separator"
	sep.size = Vector2(340, 2)
	sep.position = Vector2(40, 72)
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(0.3, 0.5, 0.8, 0.3)
	sep_style.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	panel.add_child(sep)

	# ---- 信息标签 ----
	var info := Label.new()
	info.name = "InfoLabel"
	var all_cleared := GameManager.check_all_levels_completed()
	info.text = "关卡: %d  已解锁: %s  无尽: %s  WIN: %s" % [
		GameManager.current_level,
		str(GameManager.unlocked_levels),
		"是" if GameManager.endless_unlocked else "否",
		"是" if all_cleared else "否"
	]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9, 0.8))
	info.add_theme_font_override("font", _font)
	info.size = Vector2(380, 26)
	info.position = Vector2(20, 86)
	panel.add_child(info)

	# ---- 按钮 ----
	var btn_y := 126.0
	const BTN_GAP := 62.0

	var skip_btn := _make_button("跳过当前关卡", _on_skip_current)
	skip_btn.position = Vector2(60, btn_y)
	panel.add_child(skip_btn)
	btn_y += BTN_GAP

	for lv: int in range(1, GameManager.MAX_LEVELS + 1):
		var btn := _make_button("跳转到关卡 %d" % lv, _on_jump_to.bind(lv))
		btn.position = Vector2(60, btn_y)
		panel.add_child(btn)
		btn_y += BTN_GAP

	var endless_btn := _make_button("跳转到无尽深空", _on_jump_endless)
	endless_btn.position = Vector2(60, btn_y)
	panel.add_child(endless_btn)
	btn_y += BTN_GAP

	var win_btn := _make_button("跳转到通关表彰 (WIN)", _on_jump_win)
	win_btn.position = Vector2(60, btn_y)
	panel.add_child(win_btn)
	btn_y += BTN_GAP

	var unlock_btn := _make_button("解锁全部卡片", _on_unlock_all)
	unlock_btn.position = Vector2(60, btn_y)
	panel.add_child(unlock_btn)
	btn_y += BTN_GAP

	var reset_btn := _make_button("重置所有进度", _on_reset_progress)
	reset_btn.position = Vector2(60, btn_y)
	reset_btn.modulate = Color(0.85, 0.65, 0.65, 1.0)
	panel.add_child(reset_btn)

	# ---- 关闭提示 ----
	var hint := Label.new()
	hint.name = "CloseHint"
	hint.text = "按 F12 或点击遮罩关闭"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.35, 0.35, 0.45, 0.5))
	hint.add_theme_font_override("font", _font)
	hint.size = Vector2(380, 22)
	hint.position = Vector2(20, 588)
	panel.add_child(hint)

	# ---- 右侧面板：关卡完成状态切换 ----
	_build_toggle_panel()


# ============================================================
# 按钮工厂（与 PauseMenu 保持一致）
# ============================================================
func _make_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size = Vector2(300, 50)
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_font_override("font", _font)
	btn.add_theme_color_override("font_color", Color.WHITE)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.08, 0.12, 0.24, 0.9)
	normal_style.border_width_left = 4
	normal_style.border_width_right = 4
	normal_style.border_width_top = 4
	normal_style.border_width_bottom = 4
	normal_style.border_color = Color(0.3, 0.6, 1.0, 0.5)
	normal_style.corner_radius_top_left = 8
	normal_style.corner_radius_top_right = 8
	normal_style.corner_radius_bottom_left = 8
	normal_style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.14, 0.2, 0.36, 0.95)
	hover_style.border_color = Color(0.5, 0.8, 1.0, 0.8)
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.pressed.connect(callback)
	return btn


# ============================================================
# _input — F12 关闭
# ============================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		queue_free()
		get_viewport().set_input_as_handled()


# ============================================================
# 回调
# ============================================================

func _on_skip_current() -> void:
	var lv := GameManager.current_level
	print("[DevTools] 跳过关卡 %d" % lv)
	GameManager.complete_level(lv)
	GameManager.check_all_levels_completed()
	_close_then_go("LevelSelect")


func _on_jump_to(level_id: int) -> void:
	print("[DevTools] 跳转到关卡 %d" % level_id)
	for i: int in range(1, level_id + 1):
		if i not in GameManager.unlocked_levels:
			GameManager.unlocked_levels.append(i)
	GameManager.unlocked_levels.sort()
	GameManager.current_level = level_id
	GameManager.fuel = 100.0
	_close_then_go("GameScene")


func _on_jump_endless() -> void:
	print("[DevTools] 跳转到无尽深空")
	GameManager.endless_unlocked = true
	for i: int in range(1, GameManager.MAX_LEVELS + 1):
		if i not in GameManager.unlocked_levels:
			GameManager.unlocked_levels.append(i)
	GameManager.unlocked_levels.sort()
	_close_then_go("EndlessMode")


func _on_jump_win() -> void:
	print("[DevTools] 跳转到通关表彰")
	_close_then_go("WinStory")


func _on_unlock_all() -> void:
	print("[DevTools] 解锁全部")
	# 解锁全部关卡
	for i: int in range(1, GameManager.MAX_LEVELS + 1):
		if i not in GameManager.unlocked_levels:
			GameManager.unlocked_levels.append(i)
	GameManager.unlocked_levels.sort()
	# 标记全部通关（WIN 卡片需要 completed_levels）
	for i: int in range(1, GameManager.MAX_LEVELS + 1):
		if i not in GameManager.completed_levels:
			GameManager.completed_levels.append(i)
	GameManager.endless_unlocked = true
	GameManager.check_all_levels_completed()
	# 跳转到选关页面让玩家立即看到变化
	_close_then_go("LevelSelect")


func _on_reset_progress() -> void:
	print("[DevTools] 重置所有进度")
	GameManager.unlocked_levels = [1]
	GameManager.unlocked_levels.sort()
	GameManager.endless_unlocked = false
	GameManager.completed_levels = []
	GameManager.current_level = 1
	GameManager.high_score = 0
	GameManager.best_times = {}
	GameManager.best_distances = {}
	# 跳转到选关页面让玩家立即看到变化
	_close_then_go("LevelSelect")


func _build_toggle_panel() -> void:
	## 右侧面板：关卡完成状态切换按钮
	var rpanel := Panel.new()
	rpanel.name = "TogglePanel"
	rpanel.size = Vector2(240, 300)

	var rstyle := StyleBoxFlat.new()
	rstyle.bg_color = Color(0.04, 0.06, 0.14, 0.92)
	rstyle.border_width_left = 2
	rstyle.border_width_right = 2
	rstyle.border_width_top = 2
	rstyle.border_width_bottom = 2
	rstyle.border_color = Color(0.3, 0.65, 1.0, 0.5)
	rstyle.corner_radius_top_left = 12
	rstyle.corner_radius_top_right = 12
	rstyle.corner_radius_bottom_left = 12
	rstyle.corner_radius_bottom_right = 12
	rpanel.add_theme_stylebox_override("panel", rstyle)

	rpanel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rpanel.position = Vector2(20, -310)
	add_child(rpanel)

	# 标题
	var rtitle := Label.new()
	rtitle.name = "ToggleTitle"
	rtitle.text = "关卡完成开关"
	rtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rtitle.add_theme_font_size_override("font_size", 26)
	rtitle.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0, 0.9))
	rtitle.add_theme_font_override("font", _font)
	rtitle.size = Vector2(200, 36)
	rtitle.position = Vector2(20, 14)
	rpanel.add_child(rtitle)

	# 关卡切换按钮
	var rbtn_y := 70.0
	for lv: int in range(1, GameManager.MAX_LEVELS + 1):
		var completed: bool = (lv in GameManager.completed_levels)
		var btn := Button.new()
		btn.name = "Toggle_%d" % lv
		btn.text = "日志 %d：%s" % [lv, "已完成 ✓" if completed else "未通关"]
		btn.size = Vector2(200, 50)
		btn.position = Vector2(20, rbtn_y)
		btn.add_theme_font_size_override("font_size", 22)
		btn.add_theme_font_override("font", _font)
		# 已完成→绿色，未通关→灰色
		if completed:
			btn.add_theme_color_override("font_color", Color(0.3, 0.95, 0.5, 0.9))
		else:
			btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.8))
		btn.pressed.connect(_on_toggle_level_complete.bind(lv, btn))
		rpanel.add_child(btn)
		rbtn_y += 64.0

	# 底部提示
	var rhint := Label.new()
	rhint.name = "ToggleHint"
	rhint.text = "点击切换状态\nWIN 随全部通关自动更新"
	rhint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rhint.add_theme_font_size_override("font_size", 14)
	rhint.add_theme_color_override("font_color", Color(0.35, 0.35, 0.45, 0.5))
	rhint.add_theme_font_override("font", _font)
	rhint.size = Vector2(200, 36)
	rhint.position = Vector2(20, 260)
	rpanel.add_child(rhint)


func _on_toggle_level_complete(level_id: int, btn: Button) -> void:
	## 切换关卡完成状态，维护 WIN 逻辑
	var was_completed := (level_id in GameManager.completed_levels)
	if was_completed:
		GameManager.completed_levels.erase(level_id)
		print("[DevTools] 关卡 %d 标记为未通关" % level_id)
	else:
		if level_id not in GameManager.completed_levels:
			GameManager.completed_levels.append(level_id)
		GameManager.completed_levels.sort()
		print("[DevTools] 关卡 %d 标记为已完成" % level_id)

	# 同步更新无尽模式解锁 & WIN 状态
	var all_done := GameManager.check_all_levels_completed()

	# 刷新右侧面板按钮文字和颜色
	_refresh_toggle_buttons()

	# 同时更新左侧信息标签
	var info := get_node_or_null("Panel/InfoLabel") as Label
	if info != null:
		info.text = "关卡: %d  已解锁: %s  无尽: %s  WIN: %s" % [
			GameManager.current_level,
			str(GameManager.unlocked_levels),
			"是" if GameManager.endless_unlocked else "否",
			"是" if all_done else "否"
		]

	# 如果在选关页面，刷新卡片
	var parent := get_parent()
	if parent != null and parent.has_method("refresh_cards"):
		parent.refresh_cards()


func _refresh_toggle_buttons() -> void:
	## 刷新右侧面板所有切换按钮的文字和颜色
	var rpanel := get_node_or_null("TogglePanel")
	if rpanel == null:
		return
	for lv: int in range(1, GameManager.MAX_LEVELS + 1):
		var btn := rpanel.get_node_or_null("Toggle_%d" % lv) as Button
		if btn == null:
			continue
		var completed: bool = (lv in GameManager.completed_levels)
		btn.text = "日志 %d：%s" % [lv, "已完成 ✓" if completed else "未通关"]
		if completed:
			btn.add_theme_color_override("font_color", Color(0.3, 0.95, 0.5, 0.9))
		else:
			btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.8))


func _close_then_go(scene: String) -> void:
	var tree := get_tree()
	queue_free()
	# 用 SceneTree Timer 延迟切换，避免 call_deferred 在节点释放后失效
	var timer := tree.create_timer(0.03)
	timer.timeout.connect(GameManager.change_scene.bind(scene))
