extends AnimatableBody2D

@export var move_direction: Vector2 = Vector2(0, -1)
@export var move_speed: float = 100.0
@export var move_distance: float = 200.0

var _start_pos: Vector2
var _t: float = 0.0

func _ready() -> void:
	_start_pos = global_position

func _physics_process(delta: float) -> void:
	_t += delta
	var offset := sin(_t * move_speed / move_distance) * move_distance
	global_position = _start_pos + move_direction * offset