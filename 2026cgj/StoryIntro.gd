extends Control
## ============================================================
## StoryIntro — 剧情介绍页
## 打字机效果逐字显示剧情文本
## 点击可跳过/继续，播放完毕自动进入游戏
## ============================================================

# ==================== 字体 ====================
var _font: Font

# ==================== 打字机状态 ====================
var _rich_label: RichTextLabel
var _full_text: String = ""
var _char_index: int = 0
var _timer: float = 0.0
var _finished: bool = false
var _skipping: bool = false

const CHAR_INTERVAL: float = 0.04          # 每个字符间隔（秒）
const SKIP_SPEED: float = 0.002             # 跳过时的快速间隔


# ============================================================
# 关卡剧情文本表
# ============================================================
const STORY_TEXTS: Dictionary = {
	1: "[center][font_size=36]第一章：信号迷雾[/font_size][/center]\n\n"
	+ "[color=#888]公元 2147 年，深空货运航线被未知干扰场笼罩。[/color]\n\n"
	+ "你的飞船「破晓号」在一次航线跳跃中偏离航道，\n"
	+ "导航系统全部失灵，燃料所剩无几。\n\n"
	+ "[color=#ff6644]操作提示：[/color]\n"
	+ "[color=#44aaff]A / D 键[/color] 旋转飞船方向\n"
	+ "[color=#44aaff]W 键[/color] 加速推进（消耗燃料）\n"
	+ "[color=#44aaff]S 键[/color] 减速 / 按住抛锚建立临时锚点\n"
	+ "[color=#44aaff]Esc 键[/color] 暂停游戏\n\n"
	+ "[color=#aaa]目标：将罗盘红色指针指向正上方，\n"
	+ "向红色六边形的信标前进。\n"
	+ "注意区分紫色叉号的虚假信标！[/color]\n\n"
	+ "[color=#ffaa44]首次救援后，电磁风暴将开始激活——\n"
	+ "做好准备！[/color]",

	2: "[center][font_size=36]第二章：陨石迷宫[/font_size][/center]\n\n"
	+ "[color=#888]穿越第一片碎片区后，前方传来密集的金属回波。[/color]\n\n"
	+ "这片区域布满了古代舰队的残骸，\n"
	+ "风力在此处变得极不稳定，剧烈变向。\n\n"
	+ "[color=#ff6644]锚定系统[/color]已解锁——\n"
	+ "在风暴中抛下临时锚点，可以获得短暂的避风港。\n\n"
	+ "[color=#aaa]\"这里埋葬了太多梦想……\n"
	+ "但你的故事不该到此为止。\"[/color]",

	3: "[center][font_size=36]第三章：永夜尽头[/font_size][/center]\n\n"
	+ "[color=#888]信号源的尽头，是一片完全黑暗的空域。[/color]\n\n"
	+ "不再有残骸，不再有风暴，\n"
	+ "只有纯粹的虚无和极度的酷寒。\n\n"
	+ "燃料存量已到临界点，\n"
	+ "这是最后一次抛锚的机会。\n\n"
	+ "[color=#ff6644]燃油管理系统[/color]已全面启动——\n"
	+ "每一滴燃料，都关乎生死。\n\n"
	+ "[color=#aaa]\"相信自己，飞行员。\n"
	+ "光就在前方。\"[/color]",
}


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

	GameManager.set_game_state(GameManager.GameState.STORY)

	# 纯黑背景
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# ---- 装饰性顶部条纹 ----
	var accent := ColorRect.new()
	accent.name = "AccentLine"
	accent.color = Color(0.2, 0.6, 1.0, 0.3)
	accent.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	accent.size = Vector2(0, 4)
	add_child(accent)

	# ---- RichTextLabel（打字机显示区域） ----
	_rich_label = RichTextLabel.new()
	_rich_label.name = "StoryText"
	_rich_label.bbcode_enabled = true
	_rich_label.fit_content = true
	_rich_label.scroll_following = true
	_rich_label.selection_enabled = false
	_rich_label.add_theme_font_size_override("normal_font_size", 30)
	_rich_label.add_theme_font_override("normal_font", _font)
	_rich_label.add_theme_color_override("default_color", Color(0.75, 0.8, 0.9, 1.0))
	_rich_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_rich_label.position = Vector2(-400, -280)
	_rich_label.size = Vector2(800, 520)
	add_child(_rich_label)

	# ---- "点击以跳过" 提示 ----
	var skip_hint := Label.new()
	skip_hint.name = "SkipHint"
	skip_hint.text = "点击屏幕可跳过 / 继续"
	skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip_hint.add_theme_font_size_override("font_size", 22)
	skip_hint.add_theme_color_override("font_color", Color(0.35, 0.35, 0.45, 0.5))
	skip_hint.add_theme_font_override("font", _font)
	skip_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	skip_hint.position = Vector2(-300, -80)
	skip_hint.size = Vector2(600, 30)
	add_child(skip_hint)

	# ---- 光标闪烁指示器 ----
	var cursor := ColorRect.new()
	cursor.name = "Cursor"
	cursor.color = Color(0.4, 0.8, 1.0, 0.9)
	cursor.size = Vector2(3, 28)
	cursor.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	cursor.position = Vector2(0, -46)
	add_child(cursor)

	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(cursor, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cursor, "modulate:a", 0.9, 0.5).set_ease(Tween.EASE_IN_OUT)

	# ---- 加载剧情文本 ----
	var level := GameManager.current_level
	if STORY_TEXTS.has(level):
		_full_text = STORY_TEXTS[level]
	else:
		_full_text = "[center]未知道路[/center]\n\n前方是未知的旅途……"
	_char_index = 0
	_rich_label.text = ""


# ============================================================
# _process — 打字机逐字显示
# ============================================================
func _process(delta: float) -> void:
	if _finished:
		return

	# 跳过模式（快速）
	if _skipping:
		_timer += delta
		while _timer >= SKIP_SPEED and _char_index < _full_text.length():
			_timer -= SKIP_SPEED
			_char_index += 1
	else:
		_timer += delta
		while _timer >= CHAR_INTERVAL and _char_index < _full_text.length():
			_timer -= CHAR_INTERVAL
			_char_index += 1

	# 更新显示文本：截取到当前字符位置，但保留 BBCode 完整性
	# 简单方案：逐字追加纯文本；复杂 BBCode 直接用 substring
	var display: String = _full_text.substr(0, _char_index)

	# 处理未闭合的 BBCode 标签：暂时关闭未闭合的标签
	display = _close_open_tags(display)

	_rich_label.text = display

	# 检查是否播放完毕
	if _char_index >= _full_text.length():
		_on_text_finished()


# ============================================================
# _input — 点击屏幕跳过或前往下一场景
# ============================================================
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _finished:
			_go_to_game()
		elif not _skipping:
			_skipping = true
			_timer = 0.0


# ============================================================
# 文本播放完毕
# ============================================================
func _on_text_finished() -> void:
	if _finished:
		return
	_finished = true
	_rich_label.text = _full_text  # 确保完整显示

	# 查找所有闪烁光标并隐藏
	for child in get_children():
		if child.name == "Cursor":
			child.visible = false

	# 更新提示文字
	for child in get_children():
		if child is Label and child.name == "SkipHint":
			child.text = "点击屏幕进入游戏"
			child.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 0.8))
			break


# ============================================================
# 进入游戏
# ============================================================
func _go_to_game() -> void:
	GameManager.set_game_state(GameManager.GameState.PLAYING)
	GameManager.change_scene("GameScene")


# ============================================================
# 辅助：关闭未闭合的 BBCode 标签
# ============================================================
func _close_open_tags(text: String) -> String:
	var open_tags: Array[String] = []
	var result := text
	var pos := 0

	while pos < result.length():
		var tag_start := result.find("[", pos)
		if tag_start == -1:
			break
		var tag_end := result.find("]", tag_start)
		if tag_end == -1:
			break

		var tag := result.substr(tag_start, tag_end - tag_start + 1)

		if tag.begins_with("[/"):
			# 闭合标签：移除最后一个匹配的打开标签
			var tag_name := tag.substr(2, tag.length() - 3).split(" ")[0]
			for i: int in range(open_tags.size() - 1, -1, -1):
				if open_tags[i].begins_with("[" + tag_name):
					open_tags.remove_at(i)
					break
		elif tag.begins_with("[") and not tag.begins_with("[/"):
			# 打开标签
			var tag_name := tag.substr(1, tag.length() - 2).split(" ")[0]
			open_tags.append(tag)

		pos = tag_end + 1

	# 反向追加闭合标签
	for i: int in range(open_tags.size() - 1, -1, -1):
		var open_tag := open_tags[i]
		var tag_name := open_tag.substr(1, open_tag.length() - 2).split(" ")[0]
		result += "[/" + tag_name + "]"

	return result