extends Control
## ============================================================
## WinStory — 通关表彰故事页
## 三关全部通关后解锁，播放庆祝故事 + flute BGM
## 结束后返回关卡选择页
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
var _bgm_player: AudioStreamPlayer = null

const CHAR_INTERVAL: float = 0.04
const SKIP_SPEED: float = 0.002


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

	# ---- 顶部金色装饰线 ----
	var accent := ColorRect.new()
	accent.name = "AccentLine"
	accent.color = Color(0.9, 0.7, 0.2, 0.4)
	accent.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	accent.size = Vector2(0, 4)
	add_child(accent)

	# ---- 底部金色装饰线 ----
	var accent2 := ColorRect.new()
	accent2.name = "AccentLine2"
	accent2.color = Color(0.9, 0.7, 0.2, 0.3)
	accent2.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	accent2.position = Vector2(0, -4)
	accent2.size = Vector2(0, 4)
	add_child(accent2)

	# ---- RichTextLabel（打字机显示区域） ----
	_rich_label = RichTextLabel.new()
	_rich_label.name = "StoryText"
	_rich_label.bbcode_enabled = true
	_rich_label.fit_content = true
	_rich_label.scroll_following = true
	_rich_label.selection_enabled = false
	_rich_label.add_theme_font_size_override("normal_font_size", 30)
	_rich_label.add_theme_font_override("normal_font", _font)
	_rich_label.add_theme_color_override("default_color", Color(0.85, 0.85, 0.9, 1.0))
	_rich_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_rich_label.position = Vector2(-400, -330)
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

	# ---- 光标闪烁指示器 (金色) ----
	var cursor := ColorRect.new()
	cursor.name = "Cursor"
	cursor.color = Color(0.9, 0.7, 0.2, 0.9)
	cursor.size = Vector2(3, 28)
	cursor.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	cursor.position = Vector2(0, -46)
	add_child(cursor)

	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(cursor, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cursor, "modulate:a", 0.9, 0.5).set_ease(Tween.EASE_IN_OUT)

	# ---- 通关庆祝故事文本 ----
	_full_text = "[center][font_size=42]锚点之外[/font_size][/center]\n\n" \
		+ "[color=#aaa]破晓号的黑匣子记录——\n" \
		+ "日期未知，坐标无意义。[/color]\n\n" \
		+ "三份航行日志，\n" \
		+ "三片截然不同的空域，\n" \
		+ "三次近乎不可能的救援。\n\n" \
		+ "你在迷雾中学会倾听，\n" \
		+ "在残骸中学会坚持，\n" \
		+ "在永夜中学会相信。\n\n" \
		+ "[color=#ffaa44]你留下的每一座临时锚点，[/color]\n" \
		+ "仍在深空中微弱地闪烁着。\n" \
		+ "它们是坐标，是灯塔，是承诺。\n\n" \
		+ "[color=#88aaff]破晓号，任务完成。[/color]\n" \
		+ "感谢你，飞行员。\n\n" \
		+ "[color=#666]\"每一次救援，都值得被铭记。\"[/color]"

	_char_index = 0
	_rich_label.text = ""

	# ---- 播放 flute(remasterd_dm).ogg 庆祝音乐 ----
	if ResourceLoader.exists("res://flute(remasterd_dm).ogg"):
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.name = "FluteBGM"
		_bgm_player.bus = "Master"
		_bgm_player.volume_db = -4.0
		_bgm_player.stream = load("res://flute(remasterd_dm).ogg")
		add_child(_bgm_player)
		_bgm_player.play()


# ============================================================
# _process — 打字机逐字显示
# ============================================================
func _process(delta: float) -> void:
	if _finished:
		return

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

	var display: String = _full_text.substr(0, _char_index)
	display = _close_open_tags(display)
	_rich_label.text = display

	if _char_index >= _full_text.length():
		_on_text_finished()


# ============================================================
# _input — 点击屏幕跳过或前往下一场景
# ============================================================
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _finished:
			_go_back()
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
	_rich_label.text = _full_text

	for child in get_children():
		if child.name == "Cursor":
			child.visible = false

	for child in get_children():
		if child is Label and child.name == "SkipHint":
			child.text = "点击屏幕返回选关"
			child.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 0.8))
			break


# ============================================================
# 返回关卡选择页
# ============================================================
func _go_back() -> void:
	if _bgm_player != null:
		_bgm_player.stop()
	GameManager.change_scene("LevelSelect")


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
			var close_name := tag.substr(2, tag.length() - 3).split(" ")[0]
			for i: int in range(open_tags.size() - 1, -1, -1):
				if open_tags[i].begins_with("[" + close_name):
					open_tags.remove_at(i)
					break
		elif tag.begins_with("[") and not tag.begins_with("[/"):
			open_tags.append(tag)

		pos = tag_end + 1

	for i: int in range(open_tags.size() - 1, -1, -1):
		var open_tag := open_tags[i]
		var close_name2 := open_tag.substr(1, open_tag.length() - 2).split(" ")[0]
		result += "[/" + close_name2 + "]"

	return result