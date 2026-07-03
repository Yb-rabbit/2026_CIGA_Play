extends Node2D

## 调色盘（复用 anchor 碰撞视觉）
const CRAZY_COLORS := [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW, Color.MAGENTA]
## 拟声词库
const SOUND_WORDS := ["嘭！", "哎哟！", "Ouch!", "咚！", "嘎！"]

var wobble_tween: Tween
var has_bump_this_frame: bool = false
var _cooldown: float = 0.0

func trigger_bump(body: Node) -> void:
	if has_bump_this_frame:
		return
	# 冷却 0.8 秒，避免连续触发淹没画面
	if _cooldown > 0.0:
		return
	has_bump_this_frame = true
	_cooldown = 0.8

	# 鬼畜缩放（频率降低）
	_do_wobble()

	# 随机变色
	modulate = CRAZY_COLORS[randi() % CRAZY_COLORS.size()]
	var color_tween := create_tween()
	color_tween.tween_property(self, "modulate", Color.WHITE, 0.5)

	# 小号浮动拟声词（20px，不挡视线）
	var label := Label.new()
	label.text = SOUND_WORDS[randi() % SOUND_WORDS.size()]
	label.add_theme_font_size_override("font_size", 20)
	label.modulate = Color.ORANGE
	if body:
		label.position = (global_position + body.global_position) / 2.0
	else:
		label.position = global_position + Vector2(0, -20)
	get_parent().get_parent().add_child(label)

	var float_tween := create_tween()
	float_tween.set_parallel(true)
	float_tween.tween_property(label, "position", label.position + Vector2(0, -30), 0.6)
	float_tween.tween_property(label, "modulate", Color.TRANSPARENT, 0.6)
	float_tween.tween_callback(label.queue_free).set_delay(0.6)

func _do_wobble() -> void:
	if wobble_tween and wobble_tween.is_running():
		wobble_tween.kill()
	wobble_tween = create_tween()
	wobble_tween.tween_property(self, "scale", Vector2(1.8, 0.3), 0.06)
	wobble_tween.tween_property(self, "scale", Vector2(0.6, 1.4), 0.06)
	wobble_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)