extends CharacterBody2D

## ============================================
## 移动参数
## ============================================
const SPEED := 400.0
const LERP_FACTOR := 0.08
const GRAVITY := 1200.0
const JUMP_VELOCITY := -550.0

## 钩爪参数
const HOOK_SPEED := 800.0
const GRAPPLE_PULL := 1400.0
const GRAPPLE_ARRIVE_DIST := 30.0

## 锚空闲自动隐藏时间
const ANCHOR_IDLE_TIMEOUT := 3.0

## ============================================
## 节点引用
## ============================================
@onready var anchor: RigidBody2D = $"../Anchor"

var squish_tween: Tween
var _anchor_idle_timer := 0.0
var _anchor_visible := false

## ============================================
## 初始化
## ============================================
func _ready() -> void:
	anchor.hide_anchor()

## ============================================
## 物理帧
## ============================================
func _physics_process(delta: float) -> void:
	# -- 重力 --
	velocity.y += GRAVITY * delta

	# -- 水平输入（仅 A/D） --
	var input_dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		0.0
	)

	var target_velocity_x := input_dir.x * SPEED
	var new_x: float = lerp(velocity.x, target_velocity_x, LERP_FACTOR)
	velocity.x = new_x

	# -- 醉酒惯性 --
	rotation += randf_range(-0.015, 0.015)
	velocity.x += randf_range(-30.0, 30.0) * delta

	# -- 锚空闲隐藏倒计时 --
	if _anchor_visible and not anchor.thrown and not anchor.is_grappling:
		_anchor_idle_timer -= delta
		if _anchor_idle_timer <= 0.0:
			anchor.hide_anchor()
			_anchor_visible = false

	# -- 钩爪拖拽拉力（勾住时抵消重力，拉力 1400） --
	if anchor.is_grappling:
		velocity.y = lerp(velocity.y, 0.0, 0.1)
		var dist := global_position.distance_to(anchor.global_position)
		if dist <= GRAPPLE_ARRIVE_DIST:
			anchor.release_grapple()
			anchor.reset_to_ship(self)
			_anchor_visible = false
		else:
			var pull_dir := (anchor.global_position - global_position).normalized()
			velocity += pull_dir * GRAPPLE_PULL * delta

	move_and_slide()

	# -- 撞墙拍扁 --
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider is StaticBody2D:
			_do_squish()

## ============================================
## 确保锚可见
## ============================================
func _show_anchor() -> void:
	if not _anchor_visible:
		anchor.show_anchor(self)
		_anchor_visible = true
	_anchor_idle_timer = ANCHOR_IDLE_TIMEOUT

## ============================================
## 输入
## ============================================
func _input(event: InputEvent) -> void:
	# 任意键重置锚隐藏计时器
	if _anchor_visible:
		_anchor_idle_timer = ANCHOR_IDLE_TIMEOUT

	# 跳跃
	if event.is_action_pressed("jump") and is_on_floor():
		_show_anchor()
		velocity.y = JUMP_VELOCITY

	# F 抛锚
	if event.is_action_pressed("ui_accept"):
		_show_anchor()
		if not anchor.thrown:
			anchor.throw(self)

	# E 路怒击飞
	if event.is_action_pressed("horn"):
		_show_anchor()
		_horn_rage()

	# 鼠标左键 钩爪发射
	if event.is_action_pressed("hook"):
		_show_anchor()
		_fire_hook()

## ============================================
## 撞墙拍扁
## ============================================
func _do_squish() -> void:
	if squish_tween and squish_tween.is_running():
		return
	squish_tween = create_tween()
	squish_tween.tween_property(self, "scale", Vector2(1.6, 0.4), 0.05)
	squish_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

## ============================================
## 路怒击飞
## ============================================
func _horn_rage() -> void:
	var rage_tween := create_tween()
	rage_tween.tween_property(self, "scale", Vector2(1.8, 1.8), 0.08)
	rage_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.12)

	var direction := anchor.global_position - global_position
	if direction.length() < 0.001:
		direction = Vector2.UP
	direction = direction.normalized()
	anchor.apply_central_impulse(direction * 600.0)

## ============================================
## 钩爪发射（鼠标方向）
## ============================================
func _fire_hook() -> void:
	var mouse_pos := get_global_mouse_position()
	var direction := (mouse_pos - global_position).normalized()

	anchor.release_grapple()
	anchor.gravity_scale = 0.5
	anchor.thrown = true
	anchor.freeze = false
	anchor.sleeping = false
	anchor.global_position = global_position + direction * 50.0
	anchor.linear_velocity = Vector2.ZERO
	anchor.apply_central_impulse(direction * HOOK_SPEED)