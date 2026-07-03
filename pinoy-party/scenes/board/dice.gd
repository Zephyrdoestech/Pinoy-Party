# scenes/board/dice.gd
extends Node2D

const FACE_TEXTURE_PATHS := [
	"res://assets/board_assets/Dice/3d/dice_3d_static_1.png",
	"res://assets/board_assets/Dice/3d/dice_3d_static_2.png",
	"res://assets/board_assets/Dice/3d/dice_3d_static_3.png",
	"res://assets/board_assets/Dice/3d/dice_3d_static_4.png",
	"res://assets/board_assets/Dice/3d/dice_3d_static_5.png",
	"res://assets/board_assets/Dice/3d/dice_3d_static_6.png",
]
const ROLLING_TEXTURE_PATH := "res://assets/board_assets/Dice/3d/rolling_dice-sheet.png"
const ROLLING_FRAME_SIZE := Vector2i(25, 29)
const ROLLING_COLUMNS := 6
const ROLLING_FRAME_COUNT := 28

@onready var label: Label = $Label
@onready var sprite: AnimatedSprite2D = _find_animated_sprite()

var is_rolling: bool = false
var current_face: int = 1

func _ready() -> void:
	_setup_sprite_frames()
	label.visible = false
	_play_face(current_face)
	EventBus.dice_rolled.connect(_on_dice_rolled)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		roll()

func roll() -> void:
	if is_rolling:
		return
	if NetworkManager.get_my_player_index() != GameManager.current_player_index:
		return  # not your turn
	is_rolling = true
	_play_rolling()

	for i in Constants.DICE_ROLL_TICKS:
		if sprite.sprite_frames == null:
			label.text = str(randi_range(1, Constants.DICE_FACES))
		await get_tree().create_timer(0.05).timeout

	# Don't generate the result locally anymore — ask the host for the
	# real roll so every peer ends up with the identical number.
	# If we're the host, call directly — Godot blocks rpc_id(1) on yourself.
	# If we're a client, send the request to the host (peer 1).
	if NetworkManager.is_host:
		NetworkManager._process_roll_request(multiplayer.get_unique_id())
	else:
		NetworkManager.request_roll.rpc_id(1)

# Fires on every peer once the host has broadcast the real roll result
# via EventBus.dice_rolled (emitted from GameManager.on_dice_rolled()).
func _on_dice_rolled(_player_index: int, result: int) -> void:
	current_face = clampi(result, 1, Constants.DICE_FACES)
	label.text = str(result)
	_play_face(current_face)
	is_rolling = false

func _setup_sprite_frames() -> void:
	if _has_required_animations():
		return

	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	_add_face_animations(frames)
	_add_rolling_animation(frames)
	sprite.sprite_frames = frames

func _find_animated_sprite() -> AnimatedSprite2D:
	for child in find_children("*", "AnimatedSprite2D", true, false):
		var animated_child := child as AnimatedSprite2D
		if _sprite_has_required_animations(animated_child):
			return animated_child

	var direct_sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if direct_sprite != null:
		return direct_sprite

	var sprite_node := AnimatedSprite2D.new()
	sprite_node.name = "AnimatedSprite2D"
	add_child(sprite_node)
	return sprite_node

func _has_required_animations() -> bool:
	return _sprite_has_required_animations(sprite)

func _sprite_has_required_animations(animated_sprite: AnimatedSprite2D) -> bool:
	if animated_sprite == null:
		return false
	if animated_sprite.sprite_frames == null or not animated_sprite.sprite_frames.has_animation(&"rolling"):
		return false
	for face in Constants.DICE_FACES:
		if not animated_sprite.sprite_frames.has_animation(StringName("face_%d" % (face + 1))):
			return false
	return true

func _add_face_animations(frames: SpriteFrames) -> void:
	for i in FACE_TEXTURE_PATHS.size():
		var animation_name := StringName("face_%d" % (i + 1))
		frames.add_animation(animation_name)
		frames.set_animation_loop(animation_name, false)

		var texture := load(FACE_TEXTURE_PATHS[i]) as Texture2D
		if texture == null:
			push_warning("[Dice] Could not load %s." % FACE_TEXTURE_PATHS[i])
			continue
		frames.add_frame(animation_name, texture)

func _add_rolling_animation(frames: SpriteFrames) -> void:
	frames.add_animation(&"rolling")
	frames.set_animation_loop(&"rolling", true)
	frames.set_animation_speed(&"rolling", 18.0)

	var texture := load(ROLLING_TEXTURE_PATH) as Texture2D
	if texture == null:
		push_warning("[Dice] Could not load %s." % ROLLING_TEXTURE_PATH)
		return

	for i in ROLLING_FRAME_COUNT:
		var column := i % ROLLING_COLUMNS
		var row := int(i / ROLLING_COLUMNS)
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(
			Vector2(column * ROLLING_FRAME_SIZE.x, row * ROLLING_FRAME_SIZE.y),
			Vector2(ROLLING_FRAME_SIZE.x, ROLLING_FRAME_SIZE.y)
		)
		frames.add_frame(&"rolling", atlas)

func _play_rolling() -> void:
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(&"rolling"):
		sprite.play(&"rolling")

func _play_face(face: int) -> void:
	var animation_name := StringName("face_%d" % face)
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation_name):
		sprite.play(animation_name)
		sprite.stop()
	else:
		push_warning("[Dice] Missing animation '%s'." % animation_name)
