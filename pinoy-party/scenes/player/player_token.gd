extends Node2D

const Utils = preload("res://scripts/utils.gd")

# Spritesheet constants matching the exported PNG format from Pixsquare.
const FRAME_WIDTH  := 1024   # each frame is 1024×1024px
const FRAME_HEIGHT := 1024
const HFRAMES      := 4      # 4 frames in a single horizontal row
const FPS          := 8      # playback speed

# Scale: 1024px native → ~51px on screen, fits within the 70px tile spacing.
const SPRITE_SCALE := Vector2(0.05, 0.05)

var player_index: int = 0
var board_ref: Node2D

signal movement_finished(player_index: int)

@onready var sprite: AnimatedSprite2D = $Sprite

## Called by Game.gd after instancing. `sheet` must be the loaded Texture2D
## for this player's walkFront spritesheet.
func setup(index: int, board: Node2D, sheet: Texture2D) -> void:
	player_index = index
	board_ref    = board

	sprite.sprite_frames = _build_frames(sheet)
	sprite.scale         = SPRITE_SCALE
	sprite.play("walkFront")

	global_position = board_ref.get_tile_position(0) + Utils.token_offset(player_index)

## Builds a SpriteFrames resource at runtime by slicing the PNG spritesheet
## into HFRAMES AtlasTexture regions. This avoids needing a .tres bake step.
func _build_frames(sheet: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("walkFront")
	frames.set_animation_loop("walkFront", true)
	frames.set_animation_speed("walkFront", FPS)

	for i in HFRAMES:
		var atlas := AtlasTexture.new()
		atlas.atlas  = sheet
		atlas.region = Rect2(i * FRAME_WIDTH, 0, FRAME_WIDTH, FRAME_HEIGHT)
		frames.add_frame("walkFront", atlas)

	return frames

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
