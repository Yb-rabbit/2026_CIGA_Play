extends Node2D

## ============================================
## 行为状态枚举
## ============================================
enum State { IDLE, PATROL, ATTACK }

## ============================================
## 可调参数
## ============================================
const SPEED := 120.0
const LERP_FACTOR := 0.06
const ATTACK_SPEED_MULT := 5.0
const ATTACK_DURATION := 0.3
const ATTACK_COOLDOWN := 1.5
const ATTACK_RANGE := 300.0
const PATROL_DIR_CHANGE := 5.0
const SEGMENT_COUNT := 5
const SEGMENT_SPACING := 48.0
const HISTORY_STEP := 8
const SEGMENT_RADIUS := 18.0

## 包围盒（擂台中心 0,0，半宽 504，半高 376）
const BOX_HW := 504.0
const BOX_HH := 376.0
const WALL_MARGIN := 150.0
const WALL_FORCE := 800.0

## ============================================
## 预加载
## ============================================
var SegmentScript = preload("res://Segment.gd")

## ============================================
## 节点引用
## ============================================
@onready var line_trail: Line2D = $LineTrail
var segments: Array[Node2D] = []
var _query_circle: CircleShape2D

## ============================================
## 状态变量
## ============================================
var current_state: State = State.IDLE
var position_history: Array = []
var velocity := Vector2.ZERO
var patrol_dir := Vector2.RIGHT
var patrol_timer := 0.0
var attack_timer := 0.0
var attack_cooldown_timer := 0.0
var attack_dir := Vector2.ZERO
var idle_breathe_timer := 0.0

## ============================================
## 初始化
## ============================================
func _ready() -> void:
	_query_circle = CircleShape2D.new()
	_query_circle.radius = SEGMENT_RADIUS

	for i in range(SEGMENT_COUNT):
		var seg := Node2D.new()
		seg.name = "Segment_" + str(i + 1)
		seg.set_script(SegmentScript)
		seg.global_position = global_position + Vector2(-(i + 1) * SEGMENT_SPACING, 0)
		_add_anchor_polygons(seg, SEGMENT_RADIUS, true)
		add_child(seg)
		segments.append(seg)

	# 预填充位置历史
	var hist_size := SEGMENT_COUNT * HISTORY_STEP + HISTORY_STEP * 4
	for _j in range(hist_size):
		position_history.append(global_position)

	if line_trail:
		line_trail.clear_points()
		for _j in range(60):
			line_trail.add_point(to_local(global_position))

## ============================================
## 虫子版锚形多边形（暗紫+血红）
## ============================================
func _add_anchor_polygons(parent: Node2D, size: float, _is_worm: bool) -> void:
	var s := size / 14.0
	var ring_col := Color(0.35, 0.15, 0.35, 1)
	var body_col := Color(0.3, 0.1, 0.3, 1)
	var tip_col  := Color(0.6, 0.2, 0.2, 1)

	_add_rect(parent, "Ring", Vector2(-4,-12)*s, Vector2(4,-7)*s, ring_col)
	_add_rect(parent, "Shaft", Vector2(-2,-7)*s, Vector2(2,8)*s, body_col)
	_add_rect(parent, "Crossbar", Vector2(-8,-3)*s, Vector2(8,0)*s, body_col)
	_add_tri(parent, "FlukeL", [Vector2(-2,7)*s, Vector2(-8,12)*s, Vector2(-2,12)*s], tip_col)
	_add_tri(parent, "FlukeR", [Vector2(2,7)*s, Vector2(8,12)*s, Vector2(2,12)*s], tip_col)

func _add_rect(parent: Node2D, name_str: String, tl: Vector2, br: Vector2, col: Color) -> void:
	var p := Polygon2D.new()
	p.name = name_str
	p.polygon = PackedVector2Array([tl, Vector2(br.x, tl.y), br, Vector2(tl.x, br.y)])
	p.color = col
	parent.add_child(p)

func _add_tri(parent: Node2D, name_str: String, verts: Array, col: Color) -> void:
	var p := Polygon2D.new()
	p.name = name_str
	p.polygon = PackedVector2Array(verts)
	p.color = col
	parent.add_child(p)

## ============================================
## 物理帧
## ============================================
func _physics_process(delta: float) -> void:
	for seg in segments:
		seg.has_bump_this_frame = false

	match current_state:
		State.IDLE:    _process_idle(delta)
		State.PATROL:  _process_patrol(delta)
		State.ATTACK:  _process_attack(delta)

	_check_attack_trigger(delta)

	rotation += randf_range(-0.008, 0.008)
	velocity += Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0)) * delta

	# --- 避墙：在位置更新之前修正速度方向 ---
	_steer_away_from_walls(delta)

	global_position += velocity * delta

	_hard_clamp()

	_update_history()
	_update_segments()
	_update_trail()
	_check_segment_wall_collisions()

## ============================================
## 避墙 —— 核心逻辑
## ============================================
func _steer_away_from_walls(delta: float) -> void:
	var p := global_position
	var steer := Vector2.ZERO

	if p.x < -BOX_HW + WALL_MARGIN:
		steer.x += clamp((p.x - (-BOX_HW + WALL_MARGIN)) / (-BOX_HW - (-BOX_HW + WALL_MARGIN)), 0.0, 1.0)
	elif p.x > BOX_HW - WALL_MARGIN:
		steer.x -= clamp((p.x - (BOX_HW - WALL_MARGIN)) / (BOX_HW - (BOX_HW - WALL_MARGIN)), 0.0, 1.0)

	if p.y < -BOX_HH + WALL_MARGIN:
		steer.y += clamp((p.y - (-BOX_HH + WALL_MARGIN)) / (-BOX_HH - (-BOX_HH + WALL_MARGIN)), 0.0, 1.0)
	elif p.y > BOX_HH - WALL_MARGIN:
		steer.y -= clamp((p.y - (BOX_HH - WALL_MARGIN)) / (BOX_HH - (BOX_HH - WALL_MARGIN)), 0.0, 1.0)

	if steer.length() > 0.001:
		# 将当前速度向避让方向旋转，而非直接叠加
		var target_dir := steer.normalized()
		var current_dir := velocity.normalized() if velocity.length() > 0.01 else target_dir
		var blended: Vector2 = current_dir.lerp(target_dir, clamp(WALL_FORCE * delta, 0.0, 1.0))
		blended = blended.normalized()
		velocity = blended * velocity.length()

func _hard_clamp() -> void:
	const HW := BOX_HW - 12.0
	const HH := BOX_HH - 12.0
	var p := global_position
	var hit := false
	if p.x < -HW:
		global_position.x = -HW
		velocity.x = abs(velocity.x) * 0.3
		hit = true
	elif p.x > HW:
		global_position.x = HW
		velocity.x = -abs(velocity.x) * 0.3
		hit = true
	if p.y < -HH:
		global_position.y = -HH
		velocity.y = abs(velocity.y) * 0.3
		hit = true
	elif p.y > HH:
		global_position.y = HH
		velocity.y = -abs(velocity.y) * 0.3
		hit = true
	if hit and segments.size() > 0:
		segments[0].trigger_bump(null)

## ============================================
## 行为
## ============================================
func _process_idle(delta: float) -> void:
	idle_breathe_timer += delta
	var breathe := sin(idle_breathe_timer * 2.0) * 0.03 + 1.0
	scale = Vector2(breathe, 1.0 / breathe)
	velocity = velocity.lerp(Vector2.ZERO, 0.04)

func _process_patrol(delta: float) -> void:
	patrol_timer += delta
	if patrol_timer >= PATROL_DIR_CHANGE + randf() * 2.0:
		patrol_timer = 0.0
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		patrol_dir = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))

	velocity = velocity.lerp(patrol_dir * SPEED, LERP_FACTOR)

func _process_attack(delta: float) -> void:
	attack_timer -= delta
	if attack_timer > 0.0:
		velocity = attack_dir * SPEED * ATTACK_SPEED_MULT
		scale = Vector2(0.6, 1.5)
	else:
		scale = scale.lerp(Vector2.ONE, 0.15)
		velocity = velocity.lerp(Vector2.ZERO, 0.08)
		if attack_cooldown_timer <= 0.0 and velocity.length() < 3.0:
			current_state = State.PATROL
	attack_cooldown_timer -= delta

func _check_attack_trigger(delta: float) -> void:
	if current_state == State.ATTACK:
		return
	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
		return
	var player := get_node_or_null("/root/Main/Ship")
	if player and global_position.distance_to(player.global_position) <= ATTACK_RANGE:
		attack_dir = (player.global_position - global_position).normalized()
		attack_timer = ATTACK_DURATION
		attack_cooldown_timer = ATTACK_COOLDOWN
		current_state = State.ATTACK

## ============================================
## 位置历史 & 追踪 & 拖尾
## ============================================
func _update_history() -> void:
	position_history.push_front(global_position)
	while position_history.size() > SEGMENT_COUNT * HISTORY_STEP + HISTORY_STEP * 4:
		position_history.pop_back()

func _update_segments() -> void:
	for i in range(segments.size()):
		var idx := (i + 1) * HISTORY_STEP
		if idx < position_history.size():
			segments[i].global_position = position_history[idx]

func _update_trail() -> void:
	if not line_trail:
		return
	line_trail.add_point(to_local(global_position), 0)
	while line_trail.get_point_count() > 60:
		line_trail.remove_point(line_trail.get_point_count() - 1)

## ============================================
## 节段墙壁碰撞检测
## ============================================
func _check_segment_wall_collisions() -> void:
	if segments.is_empty():
		return
	var world := get_world_2d()
	if not world:
		return
	var space_state := world.direct_space_state

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _query_circle
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 1

	for seg in segments:
		if seg.has_bump_this_frame:
			continue
		query.transform = Transform2D(0.0, seg.global_position)
		var results = space_state.intersect_shape(query)
		for result in results:
			var collider = result.get("collider", null)
			if collider is StaticBody2D:
				seg.trigger_bump(collider)
				break