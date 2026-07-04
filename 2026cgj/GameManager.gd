extends Node
## ============================================================
## GameManager — 全局管理器 (AutoLoad 单例)
## 负责：游戏状态管理、关卡解锁、跨场景数据、场景切换
## ============================================================

# ==================== 淡入淡出覆盖层 ====================
var _fade_overlay: ColorRect
var _fading: bool = false

func _enter_tree() -> void:
	# 创建专用 CanvasLayer（Control 必须在 CanvasLayer 下才能渲染）
	var overlay_layer := CanvasLayer.new()
	overlay_layer.name = "FadeLayer"
	overlay_layer.layer = 4096  # 最高渲染层

	_fade_overlay = ColorRect.new()
	_fade_overlay.name = "FadeOverlay"
	_fade_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(_fade_overlay)

	# 添加到 root，确保在所有场景节点之上
	get_tree().root.call_deferred("add_child", overlay_layer)

# ==================== 游戏状态枚举 ====================
enum GameState {
	MENU,
	PLAYING,
	PAUSED,
	STORY
}

# ==================== 全局数据存储 ====================
const MAX_LEVELS: int = 3                          # 总关卡数
var current_level: int = 1                         # 当前关卡
var unlocked_levels: Array = [1]                   # 已解锁关卡列表，默认只有第1关
var high_score: int = 0                            # 最高分
var game_state: GameState = GameState.MENU         # 当前游戏状态
var fuel: float = 100.0                             # 全局燃料缓存，用于跨场景传递

# ==================== 信号 ====================
signal scene_changed(scene_name: String)
signal game_paused()
signal game_resumed()
signal level_completed(level_id: int)
signal state_changed(new_state: GameState)


# ============================================================
# 场景切换
# ============================================================
func change_scene(scene_name: String) -> void:
	_fade_switch(scene_name)


# ============================================================
# 淡入淡出切换（异步）
# ============================================================
func _fade_switch(scene_name: String) -> void:
	if _fading:
		return
	_fading = true

	# 步骤 1：淡出（黑屏覆盖）
	if _fade_overlay != null:
		var tw := create_tween()
		tw.tween_property(_fade_overlay, "color:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)
		await tw.finished

	# 步骤 2：执行实际场景切换
	_do_change_scene(scene_name)

	# 步骤 3：淡入（黑屏消去）
	await get_tree().process_frame  # 等新场景构建完一帧
	if _fade_overlay != null:
		var tw2 := create_tween()
		tw2.tween_property(_fade_overlay, "color:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
		await tw2.finished

	_fading = false


func _do_change_scene(scene_name: String) -> void:
	## 封装场景切换逻辑（无动画）
	## 优先级：.tscn 文件 → 以 scene_name 本身作为路径 → .gd 脚本动态构建场景
	var scene_path: String = "res://%s.tscn" % scene_name

	# 1) 尝试 .tscn 文件
	if ResourceLoader.exists(scene_path):
		get_tree().change_scene_to_file(scene_path)
		scene_changed.emit(scene_name)
		print("[GameManager] 切换场景 → %s" % scene_path)
		return

	# 2) 尝试 scene_name 本身
	if ResourceLoader.exists(scene_name):
		get_tree().change_scene_to_file(scene_name)
		scene_changed.emit(scene_name)
		print("[GameManager] 切换场景 → %s" % scene_name)
		return

	# 3) 回退：尝试加载 .gd 脚本并动态构建场景（适用于纯脚本 UI）
	var script_path: String = "res://%s.gd" % scene_name
	if not ResourceLoader.exists(script_path):
		if scene_name.ends_with(".gd") and ResourceLoader.exists(scene_name):
			script_path = scene_name
		else:
			push_error("[GameManager] 场景资源未找到: %s (尝试了 %s, %s, %s)" % [scene_name, scene_path, scene_name, script_path])
			return

	var gd := load(script_path) as GDScript
	if gd == null:
		push_error("[GameManager] 脚本加载失败: %s" % script_path)
		return

	var root: Node
	var base := gd.get_instance_base_type()
	match base:
		"Control":     root = Control.new()
		"Node2D":      root = Node2D.new()
		"CanvasLayer": root = CanvasLayer.new()
		"Node3D":      root = Node3D.new()
		_:             root = Node.new()

	root.set_script(gd)
	root.name = scene_name

	get_tree().root.add_child(root)
	get_tree().current_scene.queue_free()
	get_tree().current_scene = root

	if root is Control:
		var vpr := root.get_viewport().get_visible_rect()
		root.position = Vector2.ZERO
		root.size = vpr.size
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.anchor_left = 0.0
		root.anchor_top = 0.0
		root.anchor_right = 1.0
		root.anchor_bottom = 1.0
		root.offset_left = 0.0
		root.offset_top = 0.0
		root.offset_right = 0.0
		root.offset_bottom = 0.0

	scene_changed.emit(scene_name)
	print("[GameManager] 切换场景（动态构建） → %s" % scene_name)


# ============================================================
# 暂停 / 恢复
# ============================================================
func pause_game() -> void:
	## 暂停游戏：设置全局暂停并更新游戏状态
	if game_state != GameState.PLAYING:
		return
	get_tree().paused = true
	game_state = GameState.PAUSED
	state_changed.emit(game_state)
	game_paused.emit()
	print("[GameManager] 游戏已暂停")


func resume_game() -> void:
	## 恢复游戏：取消全局暂停并恢复游戏状态
	if game_state != GameState.PAUSED:
		return
	get_tree().paused = false
	game_state = GameState.PLAYING
	state_changed.emit(game_state)
	game_resumed.emit()
	print("[GameManager] 游戏已恢复")


# ============================================================
# 关卡完成 / 解锁
# ============================================================
func complete_level(level_id: int) -> void:
	## 标记关卡解锁
	## - 如果 level_id 尚未在 unlocked_levels 中，则追加并排序
	## - 自动解锁下一关（level_id + 1）
	if level_id not in unlocked_levels:
		unlocked_levels.append(level_id)
		unlocked_levels.sort()
		print("[GameManager] 关卡 %d 已解锁" % level_id)

	# 自动解锁下一关（上限保护）
	var next_level: int = level_id + 1
	if next_level <= MAX_LEVELS and next_level not in unlocked_levels:
		unlocked_levels.append(next_level)
		unlocked_levels.sort()
		print("[GameManager] 关卡 %d 已解锁（自动）" % next_level)

	level_completed.emit(level_id)


# ============================================================
# 状态设置（便捷方法，供其他场景调用）
# ============================================================
func set_game_state(new_state: GameState) -> void:
	## 直接设置游戏状态，并发射对应信号
	var previous_state: GameState = game_state
	game_state = new_state
	state_changed.emit(new_state)
	print("[GameManager] 状态切换: %s → %s" % [
		GameState.keys()[previous_state],
		GameState.keys()[new_state]
	])


# ============================================================
# 关卡查询
# ============================================================
func is_level_unlocked(level_id: int) -> bool:
	## 查询指定关卡是否已解锁
	return level_id in unlocked_levels


func get_next_unlocked_level() -> int:
	## 返回已解锁关卡数量（即最后一关 + 1 是否可玩）
	return unlocked_levels.size()
