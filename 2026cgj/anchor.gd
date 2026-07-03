extends RigidBody2D

const RESET_DELAY := 5.0
const STOP_THRESHOLD := 10.0

## 调色盘
const CRAZY_COLORS := [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW, Color.MAGENTA]
## 拟声词库
const SOUND_WORDS := ["嘭！", "哎哟！", "Ouch!", "咚！", "嘎！"]

var ship: CharacterBody2D
var timer: float = 0.0
var thrown: bool = false
var wobble_tween: Tween
var crazy_timer: Timer

## 钩爪拖拽状态
var is_grappling: bool = false
var hook_target: Node = null

func _ready() -> void:
	gravity_scale = 0.5
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.9
	body_entered.connect(_on_body_entered)

	# 【锚格分裂】随机间隔抽风
	crazy_timer = Timer.new()
	crazy_timer.wait_time = randf_range(2.0, 4.0)
	crazy_timer.one_shot = false
	crazy_timer.autostart = true
	crazy_timer.timeout.connect(_anchor_go_crazy)
	add_child(crazy_timer)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not thrown:
		return

	# 钩爪模式下不执行 5 秒重置（锚已粘在墙上）
	if is_grappling:
		return

	timer += state.step

	# 5 秒后如果还没停，瞬移回 Ship
	if timer >= RESET_DELAY:
		var vel_length := linear_velocity.length()
		if vel_length > STOP_THRESHOLD:
			reset_to_ship(ship)

func throw(from_ship: CharacterBody2D) -> void:
	ship = from_ship
	thrown = true
	timer = 0.0

	# 清除钩爪状态
	release_grapple()

	# 解除之前可能的冻结
	freeze = false
	sleeping = false

	# 放到 Ship 位置
	global_position = ship.global_position

	# 施加上升力 + 随机水平偏移
	var horizontal_force := randf_range(-200.0, 200.0)
	apply_central_impulse(Vector2(horizontal_force, -300.0))

func release_grapple() -> void:
	if not is_grappling:
		return
	is_grappling = false
	hook_target = null
	gravity_scale = 0.5
	freeze = false
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

func reset_to_ship(from_ship: CharacterBody2D) -> void:
	ship = from_ship
	thrown = false
	timer = 0.0
	release_grapple()
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	freeze = true
	global_position = ship.global_position
	scale = Vector2.ONE

func _on_body_entered(body: Node) -> void:
	if not thrown:
		return

	# 保留原有鬼畜缩放
	_do_wobble()

	# 1. 随机变色
	modulate = CRAZY_COLORS[randi() % CRAZY_COLORS.size()]
	var color_tween := create_tween()
	color_tween.tween_property(self, "modulate", Color.WHITE, 0.5)

	# 2. 浮动拟声词
	var label := Label.new()
	label.text = SOUND_WORDS[randi() % SOUND_WORDS.size()]
	label.font_size = 48
	label.modulate = Color.ORANGE
	label.position = (global_position + body.global_position) / 2.0
	get_parent().add_child(label)

	var float_tween := create_tween()
	float_tween.set_parallel(true)
	float_tween.tween_property(label, "position", label.position + Vector2(0, -60), 0.8)
	float_tween.tween_property(label, "modulate", Color.TRANSPARENT, 0.8)
	float_tween.tween_callback(label.queue_free).set_delay(0.8)

	# 3. 钩爪模式：粘在墙壁上
	if body is StaticBody2D and not is_grappling:
		is_grappling = true
		hook_target = body
		gravity_scale = 0.0
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		freeze = true

func _do_wobble() -> void:
	if wobble_tween and wobble_tween.is_running():
		wobble_tween.kill()
	wobble_tween = create_tween()
	wobble_tween.tween_property(self, "scale", Vector2(1.8, 0.3), 0.06)
	wobble_tween.tween_property(self, "scale", Vector2(0.6, 1.4), 0.06)
	wobble_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

func _anchor_go_crazy() -> void:
	# 钩爪模式下不抽风乱冲（粘住了）
	if is_grappling:
		return

	# 随机方向乱冲
	var angle := randf_range(0.0, TAU)
	var direction := Vector2(cos(angle), sin(angle))
	apply_central_impulse(direction * randf_range(80.0, 200.0))

	# 抽风闪烁：瞬间变红再恢复白色
	modulate = Color.RED
	var flash_tween := create_tween()
	flash_tween.tween_property(self, "modulate", Color.WHITE, 0.3)

	# 重置随机间隔
	crazy_timer.wait_time = randf_range(1.5, 4.0)
	crazy_timer.start()