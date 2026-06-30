# scenes/minigames/LuksongBaka/luksong_baka.gd
extends BaseMinigame

const ROUND_TIME_START := 2.2      # seconds for marker to sweep bar at round 1
const ROUND_TIME_MIN := 0.7        # fastest the sweep will ever get
const ROUND_SPEEDUP := 0.85        # multiply sweep time by this each round
const ZONE_WIDTH_START := 0.30     # green zone width as % of bar (round 1)
const ZONE_WIDTH_MIN := 0.12       # narrowest the zone will ever get
const ZONE_SHRINK := 0.92          # multiply zone width by this each round
const BAR_WIDTH := 400.0
const PLAYER_JUMP_ACTIONS := ["p1_jump", "p2_jump", "p3_jump", "p4_jump"]

# ---------------------------------------------------------------------------
# Visual constants
# ---------------------------------------------------------------------------
const BUILDING_TEXTURES: Array[String] = [
	"res://assets/minigame_assets/luksong_baka_assets/luksong_baka_building1.png",
	"res://assets/minigame_assets/luksong_baka_assets/luksong_baka_building2.png",
	"res://assets/minigame_assets/luksong_baka_assets/luksong_baka_building3.png",
	"res://assets/minigame_assets/luksong_baka_assets/luksong_baka_building4.png",
	"res://assets/minigame_assets/luksong_baka_assets/luksong_baka_building5.png",
	"res://assets/minigame_assets/luksong_baka_assets/luksong_baka_building6.png",
]
const BUILDING_SCROLL_SPEED: float = 80.0  # pixels/sec at round 1
const BUILDING_Y: float = 400.0            # y position of building sprites
const BUILDING_SCALE: float = 4.0          # 160px × 4 = 640px wide per building
const BUILDING_NATIVE_W: int = 160         # source PNG width in pixels
const BUILDING_COUNT: int = 10             # sprites to spawn (fills 1280 + overflow)

# Character spritesheets: 4096×1024 (walk, 4 frames) / 2048×1024 (jump, 2 frames)
const CHAR_FRAME_W: int = 1024
const CHAR_FRAME_H: int = 1024
const CHAR_WALK_FRAMES: int = 4
const CHAR_JUMP_FRAMES: int = 2
const CHAR_WALK_FPS: float = 8.0
const CHAR_JUMP_FPS: float = 8.0
const CHAR_SCALE: float = 0.12            # 1024px × 0.12 ≈ 123px tall on screen
const CHAR_Y: float = 500.0               # vertical position of character sprites

@onready var player_bars: Node2D = $PlayerBars
@onready var round_label: Label = $UI/RoundLabel
@onready var countdown_label: Label = $UI/CountdownLabel
@onready var buildings_node: Node2D = $Buildings
@onready var characters_node: Node2D = $Characters

var current_round := 0
var round_time := ROUND_TIME_START
var zone_width := ZONE_WIDTH_START
var zone_start := 0.0  # 0.0–1.0 position of zone start on the bar

var alive_players: Array[int] = []
var jumped_this_round: Dictionary = {}   # player_index -> bool
var marker_t := 0.0                      # 0.0–1.0 sweep progress
var sweeping := false

var eliminated_this_round: Array[int] = []
var elimination_order: Array = []  # Array of Array[int], chronological (earliest round first)

var bars: Dictionary = {}  # player_index -> bar UI nodes

# Visual state
var building_sprites: Array[Sprite2D] = []
var building_textures_cache: Array[Texture2D] = []
var char_sprites: Dictionary = {}  # player_index -> AnimatedSprite2D

func start_game(players: Array[int]) -> void:
	super(players)
	alive_players = players.duplicate()
	_spawn_buildings()
	_spawn_character_sprites()
	_spawn_player_bars()
	await run_intro()
	_start_countdown()

# ---------------------------------------------------------------------------
# Existing gameplay functions — UNTOUCHED
# ---------------------------------------------------------------------------

func _spawn_player_bars() -> void:
	var spacing := 90
	var start_y := 0
	for i in alive_players.size():
		var player_idx: int = alive_players[i]
		var bar := _create_bar_ui(player_idx)
		bar.position = Vector2(0, start_y + i * spacing)
		player_bars.add_child(bar)
		bars[player_idx] = bar

func _create_bar_ui(player_idx: int) -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(BAR_WIDTH + 120, 70)

	var name_label := Label.new()
	name_label.text = GameManager.players[player_idx]["name"]
	name_label.position = Vector2(0, 0)
	container.add_child(name_label)

	var track := ColorRect.new()
	track.name = "Track"
	track.color = Color(0.25, 0.25, 0.25)
	track.position = Vector2(0, 24)
	track.size = Vector2(BAR_WIDTH, 24)
	container.add_child(track)

	var zone := ColorRect.new()
	zone.name = "Zone"
	zone.color = Color(0.3, 0.85, 0.4)
	zone.position = Vector2(0, 24)
	zone.size = Vector2(BAR_WIDTH * zone_width, 24)
	track.add_child(zone)

	var marker := ColorRect.new()
	marker.name = "Marker"
	marker.color = Color.WHITE
	marker.position = Vector2(0, 20)
	marker.size = Vector2(4, 32)
	track.add_child(marker)

	var status := Label.new()
	status.name = "Status"
	status.text = ""
	status.position = Vector2(BAR_WIDTH + 10, 24)
	container.add_child(status)

	return container

func _start_countdown() -> void:
	current_round += 1
	round_label.text = "Round %d" % current_round
	jumped_this_round.clear()
	eliminated_this_round.clear()

	# Randomize zone position each round
	zone_start = randf_range(0.0, 1.0 - zone_width)
	for player_idx in alive_players:
		var zone_rect: ColorRect = bars[player_idx].get_node("Track/Zone")
		zone_rect.position.x = BAR_WIDTH * zone_start
		zone_rect.size.x = BAR_WIDTH * zone_width
		var marker_rect: ColorRect = bars[player_idx].get_node("Track/Marker")
		marker_rect.position.x = 0.0
		var status: Label = bars[player_idx].get_node("Status")
		status.text = ""
		status.modulate = Color.WHITE

	_begin_sweep()

func _begin_sweep() -> void:
	marker_t = 0.0
	sweeping = true

func _process(delta: float) -> void:
	if gameplay_locked:
		return
	if not sweeping:
		_scroll_buildings(delta)
		return

	_scroll_buildings(delta)

	marker_t += delta / round_time
	if marker_t >= 1.0:
		marker_t = 1.0
		_end_round_sweep()

	for player_idx in alive_players:
		if jumped_this_round.has(player_idx):
			continue
		var marker_rect: ColorRect = bars[player_idx].get_node("Track/Marker")
		marker_rect.position.x = marker_t * BAR_WIDTH

func _unhandled_input(event: InputEvent) -> void:
	if not sweeping:
		return
	for player_idx in alive_players:
		var action: String = PLAYER_JUMP_ACTIONS[player_idx]
		if event.is_action_pressed(action):
			_try_jump(player_idx)

func _try_jump(player_idx: int) -> void:
	if not alive_players.has(player_idx) or jumped_this_round.has(player_idx):
		return

	jumped_this_round[player_idx] = true
	var in_zone: bool = marker_t >= zone_start and marker_t <= (zone_start + zone_width)
	var status: Label = bars[player_idx].get_node("Status")

	if in_zone:
		status.text = "Cleared!"
		status.modulate = Color(0.3, 0.9, 0.4)
		GameManager.add_score(player_idx, 1)
		# Visual: play jump animation once, then return to walk
		if char_sprites.has(player_idx):
			var spr: AnimatedSprite2D = char_sprites[player_idx]
			spr.play("jump")
			spr.animation_finished.connect(func():
				if is_instance_valid(spr) and alive_players.has(player_idx):
					spr.play("walk")
			, CONNECT_ONE_SHOT)
	else:
		status.text = "Caught!"
		status.modulate = Color(0.9, 0.3, 0.3)
		# Visual: grey out eliminated player
		if char_sprites.has(player_idx):
			var spr: AnimatedSprite2D = char_sprites[player_idx]
			spr.stop()
			spr.modulate = Color(0.4, 0.4, 0.4)
		_eliminate(player_idx)

func _end_round_sweep() -> void:
	sweeping = false
	# Anyone who never pressed space this round is auto-eliminated
	for player_idx in alive_players.duplicate():
		if not jumped_this_round.has(player_idx):
			var status: Label = bars[player_idx].get_node("Status")
			status.text = "Caught!"
			status.modulate = Color(0.9, 0.3, 0.3)
			# Visual: grey out auto-eliminated player
			if char_sprites.has(player_idx):
				var spr: AnimatedSprite2D = char_sprites[player_idx]
				spr.stop()
				spr.modulate = Color(0.4, 0.4, 0.4)
			_eliminate(player_idx)

	if eliminated_this_round.size() > 0:
		elimination_order.append(eliminated_this_round.duplicate())

	_check_game_over()

func _eliminate(player_idx: int) -> void:
	alive_players.erase(player_idx)
	eliminated_this_round.append(player_idx)

func _check_game_over() -> void:
	if alive_players.size() <= 1:
		_end_game()
		return

	# Speed up + shrink zone for next round
	round_time = max(ROUND_TIME_MIN, round_time * ROUND_SPEEDUP)
	zone_width = max(ZONE_WIDTH_MIN, zone_width * ZONE_SHRINK)

	await get_tree().create_timer(1.0).timeout
	_start_countdown()

func _end_game() -> void:
	# Build placement groups, BEST placement first: a lone survivor (if any)
	# is 1st on their own, then each elimination round's group in reverse
	# chronological order (most recently eliminated = better placement).
	var groups: Array = []
	if alive_players.size() == 1:
		groups.append(alive_players.duplicate())
	var reversed_eliminations: Array = elimination_order.duplicate()
	reversed_eliminations.reverse()
	groups += reversed_eliminations

	var scores: Dictionary = compute_placement_scores(groups)
	_finish(scores)

# ---------------------------------------------------------------------------
# Visual helpers — no gameplay logic here
# ---------------------------------------------------------------------------

## Spawn 10 building Sprite2Ds across the screen, filling from x=0 to ~1600.
func _spawn_buildings() -> void:
	# Pre-load all 6 building textures.
	for path in BUILDING_TEXTURES:
		building_textures_cache.append(load(path) as Texture2D)

	var scaled_w: float = BUILDING_NATIVE_W * BUILDING_SCALE
	for i in BUILDING_COUNT:
		var spr := Sprite2D.new()
		spr.texture = building_textures_cache[randi() % building_textures_cache.size()]
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Sprite2D origin is center; offset so bottom-left aligns with position.
		spr.centered = false
		spr.scale = Vector2(BUILDING_SCALE, BUILDING_SCALE)
		spr.position = Vector2(i * scaled_w, BUILDING_Y)
		buildings_node.add_child(spr)
		building_sprites.append(spr)

## Move all building sprites left each frame. When one exits left, wrap it right.
func _scroll_buildings(delta: float) -> void:
	if building_sprites.is_empty():
		return

	# Current speed scales with ROUND_SPEEDUP (faster each round).
	# round_time shrinks each round; speed is inversely proportional.
	var speed_mult: float = ROUND_TIME_START / max(round_time, ROUND_TIME_MIN)
	var speed: float = BUILDING_SCROLL_SPEED * speed_mult
	var scaled_w: float = BUILDING_NATIVE_W * BUILDING_SCALE

	# Find current rightmost x for wrapping.
	var max_x: float = -INF
	for spr in building_sprites:
		if spr.position.x > max_x:
			max_x = spr.position.x

	for spr: Sprite2D in building_sprites:
		spr.position.x -= speed * delta
		if spr.position.x < -scaled_w:
			# Teleport to right of the pack with random extra gap.
			spr.position.x = max_x + randf_range(10.0, 60.0)
			spr.texture = building_textures_cache[randi() % building_textures_cache.size()]
			# Recalculate max_x after moving this sprite.
			max_x = spr.position.x

## Build a SpriteFrames for a minigame character at runtime (no .tres bake).
## walk: 4096×1024 → 4 frames. jump: 2048×1024 → 2 frames.
func _build_char_frames(charac_num: int) -> SpriteFrames:
	var base := "res://assets/characters/minigame_characs/mg_c%d/mg_charac%d_" % [charac_num, charac_num]
	var walk_tex: Texture2D = load(base + "walkRight.PNG")
	var jump_tex: Texture2D = load(base + "jumpRight.PNG")

	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	# "walk" — 4 frames, looping
	frames.add_animation("walk")
	frames.set_animation_loop("walk", true)
	frames.set_animation_speed("walk", CHAR_WALK_FPS)
	for i in CHAR_WALK_FRAMES:
		var atlas := AtlasTexture.new()
		atlas.atlas = walk_tex
		atlas.region = Rect2(i * CHAR_FRAME_W, 0, CHAR_FRAME_W, CHAR_FRAME_H)
		frames.add_frame("walk", atlas)

	# "jump" — 2 frames, non-looping (plays once then stops)
	frames.add_animation("jump")
	frames.set_animation_loop("jump", false)
	frames.set_animation_speed("jump", CHAR_JUMP_FPS)
	for i in CHAR_JUMP_FRAMES:
		var atlas := AtlasTexture.new()
		atlas.atlas = jump_tex
		atlas.region = Rect2(i * CHAR_FRAME_W, 0, CHAR_FRAME_W, CHAR_FRAME_H)
		frames.add_frame("jump", atlas)

	return frames

## Spawn one AnimatedSprite2D per player, spread horizontally near bottom of screen.
func _spawn_character_sprites() -> void:
	var count: int = participating_players.size()
	var x_positions: Array[float] = []
	for i in count:
		x_positions.append(100.0 + (1000.0 / max(count - 1, 1)) * i)

	for i in count:
		var player_idx: int = participating_players[i]
		var charac_num: int = player_idx + 1  # player 0 → charac1, etc.

		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = _build_char_frames(charac_num)
		spr.scale = Vector2(CHAR_SCALE, CHAR_SCALE)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.position = Vector2(x_positions[i], CHAR_Y)
		spr.play("walk")

		characters_node.add_child(spr)
		char_sprites[player_idx] = spr
