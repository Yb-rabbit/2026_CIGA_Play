extends Node
## ============================================================
## RadioAdvisor — 机载无线电通讯系统
## 监听飞控电脑、声呐、气象雷达信号，在右下角显示无线电文字。
## 包含定期空闲通讯消息。
## ============================================================

var _onboard_system: Node = null
var _game_scene: Node = null

const DISPLAY_SECONDS: float = 6.0
const FONT_SIZE: int = 22
const LABEL_HEIGHT: int = 32

var _font: FontFile = null
var _active_labels: Array[Label] = []
var _overheat_warned_already: bool = false
var _canvas: CanvasLayer = null
var _container: Control = null
var _idle_timer: float = 0.0
const IDLE_INTERVAL: float = 18.0  # 每18秒发送一次空闲消息


func _ready() -> void:
	_font = load("res://YuFanDanQingSong.otf")

	_canvas = CanvasLayer.new()
	_canvas.name = "RadioCanvas"
	add_child(_canvas)

	_container = Control.new()
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(_container)

	# 空闲计时器随机偏移，避免多条消息同时触发
	_idle_timer = randf_range(5.0, 15.0)

	call_deferred("_bind_signals")

	set_process(true)


func _process(delta: float) -> void:
	if _container == null:
		return

	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = IDLE_INTERVAL + randf_range(-3.0, 3.0)
		_send_idle_message()


func _send_idle_message() -> void:
	const MSGS: Array[Dictionary] = [
		{ "sender": "[通讯]", "msg": "距上次救援已飞行 2.4 天文单位，传感器阵列运行正常。", "color": Color(0.5, 0.7, 0.9) },
		{ "sender": "[导航]", "msg": "当前区域电磁噪音评级：中等，航线修正系统就绪。", "color": Color(0.4, 0.6, 0.8) },
		{ "sender": "[舰桥]", "msg": "一切正常，保持航向。", "color": Color(0.5, 0.5, 0.7) },
		{ "sender": "[传感器]", "msg": "被动扫描持续进行中，未发现异常能量读数。", "color": Color(0.3, 0.5, 0.8) },
		{ "sender": "[通讯]", "msg": "深空通讯延迟约 47 毫秒，中继卫星链路稳定。", "color": Color(0.5, 0.7, 0.9) },
		{ "sender": "[导航]", "msg": "陀螺仪校准完成，偏航补偿 ±2° 以内。", "color": Color(0.4, 0.6, 0.8) },
		{ "sender": "[舰桥]", "msg": "距目的地还有一段距离，建议保持当前巡航速度。", "color": Color(0.5, 0.5, 0.7) },
		{ "sender": "[日志]", "msg": "任务计时器已记录，飞船各系统运行参数保存完毕。", "color": Color(0.6, 0.6, 0.6) },
	]

	var entry: Dictionary = MSGS[randi_range(0, MSGS.size() - 1)]
	_show_message(entry["sender"], entry["msg"], entry["color"])


func _build_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	lbl.add_theme_font_override("font", _font)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.anchor_left = 0.0
	lbl.anchor_top = 0.0
	lbl.anchor_right = 0.0
	lbl.anchor_bottom = 0.0
	return lbl


func _bind_signals() -> void:
	if _game_scene == null:
		_game_scene = get_tree().current_scene
	if _game_scene == null:
		return

	if _onboard_system == null:
		_onboard_system = _game_scene.get_node_or_null("OnboardSystem")
		if _onboard_system == null:
			for child in _game_scene.get_children():
				if child.name == "OnboardSystem":
					_onboard_system = child
					break

	if _onboard_system != null:
		if _onboard_system.has_signal("overheat_warning"):
			_onboard_system.overheat_warning.connect(_on_overheat_warning)
		if _onboard_system.has_signal("thrust_limited"):
			_onboard_system.thrust_limited.connect(_on_thrust_limited)

	if _game_scene.has_signal("scan_completed"):
		_game_scene.scan_completed.connect(_on_scan_completed)

	if _game_scene.has_signal("storm_intensified"):
		_game_scene.storm_intensified.connect(_on_storm_intensified)


func _on_overheat_warning(is_overheating: bool) -> void:
	if not is_overheating or _overheat_warned_already:
		return
	_overheat_warned_already = true
	_show_message("[飞控电脑]", "持续高能耗输出，建议采用间歇式推进以节约燃料。", Color(1.0, 0.6, 0.2))


func _on_thrust_limited(is_limited: bool) -> void:
	if not is_limited:
		return
	_show_message("[飞控电脑]", "紧急保护已启动，推力限制 60%，请松开油门冷却引擎。", Color(1.0, 0.2, 0.1))


func _on_storm_intensified(level: int) -> void:
	_show_message("[气象雷达]", "电磁风暴增强至第%d级，注意偏航修正！" % level, Color(1.0, 0.5, 0.1))


func _on_scan_completed(has_beacon: bool) -> void:
	if has_beacon:
		return
	_show_message("[声呐]", "扫描完毕，未发现生命信号，建议转移至下一区域。", Color(0.4, 0.8, 1.0))


func _show_message(sender: String, msg: String, clr: Color) -> void:
	if _container == null:
		return

	var label := _build_label("[%s] %s" % [sender, msg])
	label.add_theme_color_override("font_color", clr)

	var stacked: int = _active_labels.size()
	var top: float = 850.0 - stacked * (LABEL_HEIGHT + 8)

	label.offset_left = 700.0
	label.offset_top = top
	label.offset_right = 1560.0
	label.offset_bottom = top + 80.0

	_container.add_child(label)
	_active_labels.append(label)

	var tw := create_tween()
	tw.tween_interval(DISPLAY_SECONDS)
	tw.tween_property(label, "modulate:a", 0.0, 1.0)
	tw.tween_callback(_remove_label.bind(label))


func _remove_label(label: Label) -> void:
	_active_labels.erase(label)
	if is_instance_valid(label):
		label.queue_free()