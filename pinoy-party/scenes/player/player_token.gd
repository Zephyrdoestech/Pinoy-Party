extends Node2D

# Spritesheet constants matching the exported PNG format from Pixsquare.
const FRAME_WIDTH  := 1024   # each frame is 1024x1024px
const FRAME_HEIGHT := 1024
const HFRAMES      := 4      # 4 frames in a single horizontal row
const FPS          := 8      # playback speed

# Scale: 1024px native -> ~51px on screen, fits within the 70px tile spacing.
const SPRITE_SCALE := Vector2(0.05, 0.05)


var player_index: int = 0
var board_ref: Node2D

signal movement_finished(player_index: int)

@onready var sprite: AnimatedSprite2D = $Sprite

## Called by Game.gd after instancing.
## `front_sheet` is the walkFront Texture2D for this player - the other three
## directional sheets are loaded internally using the same path pattern.
func setup(index: int, board: Node2D, front_sheet: Texture2D) -> void:
	player_index = index
	board_ref    = board

	sprite.sprite_frames = _build_frames(player_index + 1, front_sheet)
	sprite.scale         = SPRITE_SCALE
	sprite.play("walkFront")

	var current_tile: int = GameManager.players[index]["tile_index"]
	global_position = board_ref.get_tile_position(current_tile) + Utils.token_offset(player_index)

## Builds a SpriteFrames resource at runtime containing all 4 directional
## animations. `front_sheet` comes from Game.gd (already loaded); the other
## three sheets are loaded here using the confirmed path pattern.
## No .tres bake or AsepriteWizard dependency.
func _build_frames(charac_num: int, front_sheet: Texture2D) -> SpriteFrames:
	var base := "res://assets/characters/board_characs/charac%d/charac%d_" % [charac_num, charac_num]

	# Map animation name -> Texture2D source.
	# walkFront is already loaded (passed in); the rest are loaded here.
	var sheet_map: Dictionary = {
		"walkFront": front_sheet,
		"walkBack":  load(base + "walkBack.PNG"),
		"walkLeft":  load(base + "walkLeft.PNG"),
		"walkRight": load(base + "walkRight.PNG"),
	}

	var frames := SpriteFrames.new()
	# Remove the default "default" animation that SpriteFrames.new() adds.
	frames.remove_animation("default")

	for anim_name in sheet_map:
		var sheet: Texture2D = sheet_map[anim_name]
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, true)
		frames.set_animation_speed(anim_name, FPS)
		for i in HFRAMES:
			var atlas := AtlasTexture.new()
			atlas.atlas  = sheet
			atlas.region = Rect2(i * FRAME_WIDTH, 0, FRAME_WIDTH, FRAME_HEIGHT)
			frames.add_frame(anim_name, atlas)

	return frames

## Returns the animation name matching the direction of movement from
## `from_index` to `to_index`, determined by comparing their world positions
## on the board. This is robust to any board shape - no hardcoded index ranges.
func _get_direction_animation(from_index: int, to_index: int) -> String:
	if board_ref == null:
		return "walkFront"
	var from_pos: Vector2 = board_ref.get_tile_position(from_index)
	var to_pos:   Vector2 = board_ref.get_tile_position(to_index)
	var delta: Vector2    = to_pos - from_pos

	# Decide based on whichever axis has the larger displacement.
	if abs(delta.x) >= abs(delta.y):
		return "walkRight" if delta.x > 0 else "walkLeft"
	else:
		return "walkFront" if delta.y > 0 else "walkBack"

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

	# Switch to the animation that matches the board segment being traversed.
	var anim: String = _get_direction_animation(current_idx, next_idx)
	sprite.play(anim)

	var tween := create_tween()
	tween.tween_property(self, "global_position", target_pos, Constants.MOVE_STEP_DURATION)
	tween.finished.connect(func():
		GameManager.players[player_index]["tile_index"] = next_idx
		_step_toward(next_idx, target_idx)
	)
