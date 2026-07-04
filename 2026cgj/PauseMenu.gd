extends CanvasLayer
## ============================================================
## PauseMenu — 暂停菜单
## 继承 CanvasLayer，确保渲染在最上层
## 支持 Esc 键和手机返回键呼出/关闭
## ============================================================

# ==================== 字体 ====================
var _font: Font


# ==================== _ready ====================
func _ready() -> void:
	# 必须设为 ALWAYS，否则 get_tree().paused = true 会冻结本节点，按钮/输入全部失效
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = load("res://YuFanDanQingSong.otf") as Font
	layer = 128  # 最高渲染层级

	# 半透明黑色遮罩
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 点击遮罩空白区域不做任何操作（不穿透）
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# ---- 居中面板 ----
	var panel := Panel.new()
	panel.name = "Panel"
	panel.size = Vector2(360, 340)

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
	panel.position = Vector2(-180, -170)
	add_child(panel)

	# ---- "暂停" 标题 ----
	var title := Label.new()
	title.name = "Title"
	title.text = "游戏暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0, 0.9))
	title.add_theme_font_override("font", _font)
	title.size = Vector2(360, 50)
	title.position = Vector2(0, 20)
	panel.add_child(title)

	# ---- 分隔线 ----
	var sep := HSeparator.new()
	sep.name = "Separator"
	sep.size = Vector2(300, 2)
	sep.position = Vector2(30, 80)
	sep.add_theme_stylebox_override("separator", _make_sep_style())
	panel.add_child(sep)

	# ---- 按钮 ----
	var btn_y_start: float = 100.0
	var btn_spacing: float = 68.0

	# "继续" 按钮
	var resume_btn := _make_button("继续游戏", _on_resume)
	resume_btn.position = Vector2(60, btn_y_start)
	panel.add_child(resume_btn)

	# "重试" 按钮
	var retry_btn := _make_button("重新开始", _on_retry)
	retry_btn.position = Vector2(60, btn_y_start + btn_spacing)
	panel.add_child(retry_btn)

	# "返回主菜单" 按钮
	var menu_btn := _make_button("返回主菜单", _on_main_menu)
	menu_btn.position = Vector2(60, btn_y_start + btn_spacing * 2)
	menu_btn.modulate = Color(0.85, 0.65, 0.65, 1.0)
	panel.add_child(menu_btn)

	# 默认暂停游戏
	GameManager.pause_game()


# ============================================================
# _input — Esc 键和手机返回键处理
# ============================================================
func _input(event: InputEvent) -> void:
	# Esc 键关闭暂停菜单
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_on_resume()
		get_viewport().set_input_as_handled()


# ============================================================
# NOTIFICATION_WM_GO_BACK_REQUEST — Android 返回键
# ============================================================
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_resume()


# ============================================================
# 按钮工厂
# ============================================================
func _make_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size = Vector2(240, 52)
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_font_override("font", _font)
	btn.add_theme_color_override("font_color", Color.WHITE)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.08, 0.12, 0.24, 0.9)
	normal_style.border_width_left = 1
	normal_style.border_width_right = 1
	normal_style.border_width_top = 1
	normal_style.border_width_bottom = 1
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
# 分隔线样式
# ============================================================
func _make_sep_style() -> StyleBoxLine:
	var style := StyleBoxLine.new()
	style.color = Color(0.3, 0.5, 0.8, 0.3)
	style.thickness = 1
	return style


# ============================================================
# 回调
# ============================================================
func _on_resume() -> void:
	GameManager.resume_game()
	queue_free()


func _on_retry() -> void:
	GameManager.resume_game()
	# 重置燃料后通过 GameManager 重建场景（纯脚本无 .tscn 文件，不能用 reload_current_scene）
	GameManager.fuel = 100.0
	GameManager.change_scene("GameScene")
	queue_free()


func _on_main_menu() -> void:
	GameManager.resume_game()
	GameManager.change_scene("MainMenu")
	queue_free()