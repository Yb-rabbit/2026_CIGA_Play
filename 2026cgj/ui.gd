extends CanvasLayer

func _ready() -> void:
	# 运行时强制开启碰撞体调试绘制
	if not Engine.is_editor_hint():
		Engine.physics_ticks_per_second = 60
		ProjectSettings.set_setting("debug/shapes/collision/shape_debug_draw", 1)