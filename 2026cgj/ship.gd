extends CharacterBody2D

const SPEED := 400.0
const LERP_FACTOR := 0.08
const HOOK_SPEED := 800.0
const GRAPPLE_PULL := 800.0
const GRAPPLE_ARRIVE_DIST := 30.0

@onready var anchor: RigidBody2D = $"../Anchor"

var squish_tween: Tween

func _ready() -> void:
	anchor.reset_to_ship(self)

func _physics_process(delta: float) -> void:
	# 读取输入方向
	var input_dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)

	# 拖拉机式延迟跟随
	var target_velocity := input_dir * SPEED
	velocity = velocity.lerp(target_velocity, LERP_FACTOR)

	# 【醉酒惯性】每帧随机旋转 + 随机横向漂移
	rotation += randf_range(-0.015, 0.015)
	velocity += Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0)) * delta

	# 【钩爪拖拽拉力】锚粘墙时，船被拉向锚
	if anchor.is_grappling:
		var dist := global_position.distance_to(anchor.global_position)
		# 距离很近时自动解除钩爪
		if dist <= GRAPPLE_ARRIVE_DIST:
			anchor.release_grapple()
			anchor.reset_to_ship(self)
		else:
			var pull_dir := (anchor.global_position - global_position).normalized()
			velocity += pull_dir * GRAPPLE_PULL * delta

	move_and_slide()

	# 撞墙检测 - 拍扁效果
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider is StaticBody2D:
			_do_squish()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		if not anchor.thrown:
			anchor.throw(self)

	# 【路怒症】按 E 键膨胀 + 击飞锚
	if event.is_action_pressed("horn"):
		_horn_rage()

	# 【钩爪发射】鼠标左键
	if event.is_action_pressed("hook"):
		_fire_hook()

func _do_squish() -> void:
	if squish_tween and squish_tween.is_running():
		return
	squish_tween = create_tween()
	squish_tween.tween_property(self, "scale", Vector2(1.6, 0.4), 0.05)
	squish_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

func _horn_rage() -> void:
	# 膨胀再缩回
	var rage_tween := create_tween()
	rage_tween.tween_property(self, "scale", Vector2(1.8, 1.8), 0.08)
	rage_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.12)

	# 击飞锚：从 Ship 指向 Anchor 的方向
	var direction := anchor.global_position - global_position
	if direction.length() < 0.001:
		direction = Vector2.UP  # 如果锚恰好在身上，默认向上击飞
	direction = direction.normalized()
	anchor.apply_central_impulse(direction * 600.0)

func _fire_hook() -> void:
	# 获取鼠标全局位置
	var mouse_pos := get_global_mouse_position()
	var direction := (mouse_pos - global_position).normalized()

	# 清除钩爪状态，恢复重力
	anchor.release_grapple()
	anchor.gravity_scale = 0.5

	# 从船头出发
	anchor.thrown = true
	anchor.freeze = false
	anchor.sleeping = false
	anchor.global_position = global_position + direction * 50.0

	# 高速向鼠标发射
	anchor.linear_velocity = Vector2.ZERO
	anchor.apply_central_impulse(direction * HOOK_SPEED)