extends Node2D

const Utils = preload("res://scripts/utils.gd")

var player_index: int = 0
var board_ref: Node2D

signal movement_finished(player_index: int)

## Assign a SpriteFrames resource here per player (one per character).
## Set in Game.gd._spawn_tokens() at runtime, or pre-assign in the editor.
@export var sprite_frames: SpriteFrames

@onready var sprite: AnimatedSprite2D = $Sprite

func setup(index: int, board: Node2D) -> void:
	player_index = index
	board_ref    = board

	# Wire the SpriteFrames resource into the AnimatedSprite2D.
	if sprite_frames != null:
		sprite.sprite_frames = sprite_frames
		# Play the front-facing idle walk animation as the board stance.
		if sprite.sprite_frames.has_animation("walkFront"):
			sprite.play("walkFront")
		else:
			# Fallback: play whatever the first animation is.
			var anims := sprite.sprite_frames.get_animation_names()
			if anims.size() > 0:
				sprite.play(anims[0])
	else:
		push_warning("PlayerToken %d: no sprite_frames assigned." % index)

	global_position = board_ref.get_tile_position(0) + Utils.token_offset(player_index)

func move_to(target_tile_index: int) -> void:
	if board_ref == null:
		return
	var current_idx: int = GameManager.players[player_index]["tile_index"]
	_step_toward(current_idx, target_tile_index)

func _step_toward(current_idx: int, target_idx: int) -> void:
	if current_idx >= target_idx:
		movement_finished.emit(player_index)
		return

	var next_idx: int = min(current_idx + 1, target_idx)
	var target_pos: Vector2 = board_ref.get_tile_position(next_idx) + Utils.token_offset(player_index)

	var tween := create_tween()
	tween.tween_property(self, "global_position", target_pos, Constants.MOVE_STEP_DURATION)
	tween.finished.connect(func():
		GameManager.players[player_index]["tile_index"] = next_idx
		_step_toward(next_idx, target_idx)
	)
