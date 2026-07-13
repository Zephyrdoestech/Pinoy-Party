# scenes/minigames/LuksongBaka/luksong_baka.gd
class_name LuksongBaka
extends BaseMinigame

const ROUND_TIME_START := 2.2      # seconds for marker to sweep bar at round 1
const ROUND_TIME_MIN := 0.7        # fastest the sweep will ever get
const ROUND_SPEEDUP := 0.85        # multiply sweep time by this each round
const ZONE_WIDTH_START := 0.30     # green zone width as % of bar (round 1)
const ZONE_WIDTH_MIN := 0.12       # narrowest the zone will ev0er get
const ZONE_SHRINK := 0.92          # multiply zone width by this each round
const DEBUG_FORCE_LOCAL_TEST := false
const BAR_WIDTH := 200.0

# ---------------------------------------------------------------------------
# Visual constants
# ---------------------------------------------------------------------------
const CHAR_SCALE: float = 0.12            # Scale factor for characters
const CHAR_Y: float = 275.0               # Adjusted vertical alignment relative to quadrant size

@onready var round_label: Label = $UI/RoundLabel
@onready var countdown_label: Label = $UI/CountdownLabel
@onready var splitscreen_grid: GridContainer = $SplitscreenGrid
const TUTORIAL_PNG_PATH := "res://assets/tutorials/tutorial_luksong_baka.png" 

var tutorial_node: CanvasLayer = null

const QUADRANT_SCENE = preload("res://scenes/minigames/LuksongBaka/player_quadrant.tscn")
const PLAYER_SCENES := {
	0: preload("res://scenes/minigames/LuksongBaka/minigame_character.tscn"),
	1: preload("res://scenes/minigames/LuksongBaka/minigame_character2.tscn"),
	2: preload("res://scenes/minigames/LuksongBaka/minigame_character3.tscn"),
	3: preload("res://scenes/minigames/LuksongBaka/minigame_character4.tscn")
}

const OBSTACLE_TEXTURES := [
	preload("res://assets/minigame_assets/luksong_baka_assets/luksong_baka_obstacle4.png"),
	preload("res://assets/minigame_assets/luksong_baka_assets/luksong_baka_obstacle7.png"),
	preload("res://assets/minigame_assets/luksong_baka_assets/luksong_baka_obstacle11.png"),
	preload("res://assets/minigame_assets/luksong_baka_assets/luksong_baka_obstacle9.png"),
	preload("res://assets/minigame_assets/luksong_baka_assets/luksong_baka_obstacle8.png")
]

var current_round := 0
var round_time := ROUND_TIME_START
var zone_width := ZONE_WIDTH_START
var zone_start := 0.0  # 0.0-1.0 position of zone start on the bar

var alive_players: Array[int] = []
var jumped_this_round: Dictionary = {}   # player_index -> bool
var marker_t := 0.0                      # 0.0-1.0 sweep progress
var sweeping := false

var eliminated_this_round: Array[int] = []
var elimination_order: Array = []  # Array of Array[int], chronological (earliest round first)

var bars: Dictionary = {}          # player_index -> bar UI nodes reference
var char_sprites: Dictionary = {}  # player_index -> AnimatedSprite2D
var quadrants: Dictionary = {}     # player_index -> SubViewportContainer reference

func _ready() -> void:
	randomize()
	
	# ️ LOCAL TESTING OVERRIDE GATEWAY:
	if DEBUG_FORCE_LOCAL_TEST :
		GameManager.players = [
			{"name": "Player 1", "score": 0},
			{"name": "CPU Player 2", "score": 0},
			{"name": "CPU Player 3", "score": 0},
			{"name": "CPU Player 4", "score": 0}
		]
		
		gameplay_locked = false 
		start_game([0, 1, 2, 3])

func start_game(players: Array[int]) -> void:
	alive_players = players.duplicate()
	super(players)
	elimination_order.clear()
	
	# Initialize our 4 separate isolated viewports
	_spawn_splitscreen_worlds()
	
	if not GameManager.has_shown_tutorial("luksong_baka"):
		GameManager.mark_tutorial_shown("luksong_baka")
		_show_tutorial_png()
	else:
		_show_tutorial_png()
	
	if DEBUG_FORCE_LOCAL_TEST :
		await get_tree().process_frame 
		_start_countdown()
		_begin_round(randf_range(0.0, 1.0 - zone_width)) # Kicks off local sandbox with an initial zone position
	else:
		await run_intro()
		_start_countdown()

func _start_countdown() -> void:
	current_round += 1
	round_label.text = "Round %d" % current_round
	jumped_this_round.clear()
	eliminated_this_round.clear()
	
	if current_round == 1:
		gameplay_locked = true 
		await get_tree().create_timer(3.0).timeout 
		gameplay_locked = false

	var picked_zone_start := randf_range(0.0, 1.0 - zone_width)

	#  LOCAL SANDBOX COMPATIBILITY GATEWAY:
	var is_local_test: bool = DEBUG_FORCE_LOCAL_TEST 
	if is_local_test:
		# Directly run the logic instantly without routing through NetworkManager
		_begin_round(picked_zone_start)
	else:
		# Normal production network execution pathway
		if NetworkManager.is_host:
			NetworkManager.sync_luksong_round.rpc(picked_zone_start)

#  UNIFIED ROUND START FUNCTION
func _begin_round(synced_zone_start: float) -> void:
	zone_start = synced_zone_start
	marker_t = 0.0
	
	# Force tracking arrays to reset cleanly 
	jumped_this_round.clear()
	
	for player_idx in participating_players:
		#  CRITICAL FIX: If this player is already eliminated, 
		# do NOT reset their quadrant! Leave them frozen.
		if not alive_players.has(player_idx):
			continue # Skip straight to the next player loop execution
			
		if char_sprites.has(player_idx) and bars.has(player_idx):
			var spr = char_sprites[player_idx]
			var bar_ui = bars[player_idx]
			
			# Reset character state to their walking animation
			if spr and is_instance_valid(spr):
				spr.play("walk")
				spr.modulate = Color.WHITE # Reset gray scale out-outs from prior losses
			
			# RANDOMIZED STATIONARY OBSTACLE RESET
			if quadrants.has(player_idx):
				var quad = quadrants[player_idx]
				var obstacle: Sprite2D = quad.get_node_or_null("SubViewport/Obstacle")
				if obstacle:
					obstacle.texture = OBSTACLE_TEXTURES.pick_random()
					obstacle.position.x = 500.0 # Set completely off-screen right at start
					obstacle.show()
			
			# Configure visual track bar nodes safely
			var track: Control = bar_ui.get_node_or_null("Track")
			var zone_rect: Control = bar_ui.get_node_or_null("Track/Zone")
			var marker_rect: Control = bar_ui.get_node_or_null("Track/Marker")
			var status: Label = bar_ui.get_node_or_null("Status")
			
			if track and zone_rect and marker_rect:
				var current_track_width: float = track.size.x
				zone_rect.position.x = current_track_width * zone_start
				zone_rect.size.x = current_track_width * zone_width
				marker_rect.position.x = 0.0
				zone_rect.show()
				
			if status:
				status.text = ""
				status.modulate = Color.WHITE
				
	_begin_sweep()


func _process(delta: float) -> void:
	if gameplay_locked:
		return
		
	# Keep updating backgrounds (moving active ones, maintaining freeze states)
	_scroll_buildings(delta)
	
	if not sweeping:
		return

	# Increment global timeline progression calculation
	marker_t += delta / round_time
	if marker_t >= 1.0:
		marker_t = 1.0
		_end_round_sweep()
		return

	if DEBUG_FORCE_LOCAL_TEST:
		for player_idx in alive_players.duplicate():
			if player_idx == 0: continue
			if jumped_this_round.has(player_idx): continue
			
			# AI Logic: If the sweeping marker enters the safe zone, roll a random chance to jump
			if marker_t >= zone_start and marker_t <= (zone_start + zone_width):
				if randf() < 0.05: # 5% frame chance to react while inside the zone
					_try_jump(player_idx)

	# Update visual timelines, markers, and obstacles for each player grid
	var visible_players: Array = participating_players
	#if not DEBUG_FORCE_LOCAL_TEST:
		#visible_players = [NetworkManager.get_my_player_index()]

	for player_idx in visible_players:
		if not bars.has(player_idx):
			continue
			
		# 1.  TIMED OBSTACLE LERP MOVEMENT
		if alive_players.has(player_idx) and quadrants.has(player_idx):
			var quad = quadrants[player_idx]
			var obstacle: Sprite2D = quad.get_node_or_null("SubViewport/Obstacle")
			
			if obstacle and is_instance_valid(obstacle):
				var start_x := 500.0  # Spawn coordinate (off-screen right)
				var target_x := 80.0   # Character's horizontal position
				
				var arrival_time := zone_start + (zone_width * 0.4) # for better visual alignment of the obstacles
				
				# Normalize marker progress against where the safe zone actually begins
				if marker_t < arrival_time:
					var t_normalized = marker_t / arrival_time
					obstacle.position.x = lerp(start_x, target_x, t_normalized)
				else:
					# If marker passes the target zone, pass through the player to the left off-screen
					var overshoot = (marker_t - arrival_time) / (1.0 - arrival_time)
					obstacle.position.x = lerp(target_x, -100.0, overshoot)
		
		if not alive_players.has(player_idx):
			continue
		
		# 2. UI TIMING BAR MARKER MOVEMENT
		# Freeze visual marker placement instantly if the player has already jumped
		if jumped_this_round.has(player_idx):
			continue
			
		var track: Control = bars[player_idx].get_node_or_null("Track")
		var marker_rect: Control = bars[player_idx].get_node_or_null("Track/Marker")
		
		if track and marker_rect:
			var current_track_width: float = track.size.x
			marker_rect.position.x = marker_t * current_track_width

func _begin_sweep() -> void:
	if tutorial_node and is_instance_valid(tutorial_node):
		tutorial_node.queue_free()
	marker_t = 0.0
	sweeping = true
	gameplay_locked = false

func _unhandled_input(event: InputEvent) -> void:
	# 1. Ignore inputs if the bar isn't actively sweeping
	if not sweeping:
		return
		
	# 2. Ignore any input that isn't our designated jump action
	if not event.is_action_pressed("jump"):
		return
		
	print(" Jump action detected!")

	# 3. GATEWAY A: Local Sandbox Mode (F6 Testing)
	var is_local_test: bool = DEBUG_FORCE_LOCAL_TEST 
	if DEBUG_FORCE_LOCAL_TEST:
		print("️ Sandbox Mode: Routing jump to _try_jump(0)")
		_try_jump(0)
		return #  

	# 4. GATEWAY B: Production Network Mode (F5 Running Main Game)
	var my_idx: int = NetworkManager.get_my_player_index()
	print(" Network Mode: My Player Index = ", my_idx, " | Is Alive = ", alive_players.has(my_idx))
	
	if my_idx == -1 or not alive_players.has(my_idx):
		return
	if jumped_this_round.has(my_idx):
		return
		
	if NetworkManager.is_host:
		NetworkManager.process_luksong_jump(my_idx, marker_t)
	else:
		NetworkManager.request_luksong_jump.rpc_id(1, my_idx, marker_t)

func _try_jump(player_idx: int) -> void:
	print(" Checking _try_jump guards for player: ", player_idx)
	
	if not alive_players.has(player_idx):
		print("Guard failed: player_idx is not in alive_players! current alive: ", alive_players)
		return
	if jumped_this_round.has(player_idx):
		print("Guard failed: player already jumped this round!")
		return
	if not bars.has(player_idx):
		print("Guard failed: bars dictionary is missing player_idx!")
		return
	if not char_sprites.has(player_idx):
		print("Guard failed: char_sprites dictionary is missing player_idx!")
		return

	print("All guards passed! Processing jump calculations...")
	play_jump_sfx()
	jumped_this_round[player_idx] = true
	var in_zone: bool = marker_t >= zone_start and marker_t <= (zone_start + zone_width)
	var status: Label = bars[player_idx].get_node_or_null("Status")

	if in_zone:
		if status:
			status.text = "Ligtas!"
			status.modulate = Color(0.3, 0.9, 0.4)
		GameManager.add_score(player_idx, 1)
		
		var spr: AnimatedSprite2D = char_sprites[player_idx]
		spr.play("jump")
		var tween = create_tween().set_parallel(false)
		var jump_height := 150.0  
		var jump_duration := 0.25 # How fast they reach the peak
		
		# 1. Animate upward relative to the base CHAR_Y alignment
		tween.tween_property(spr, "position:y", CHAR_Y - jump_height, jump_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
# 2. Animate back down to the ground
		tween.tween_property(spr, "position:y", CHAR_Y, jump_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# Return to walk state when the distinct resource finishes playing
		spr.animation_finished.connect(func():
			if is_instance_valid(spr) and alive_players.has(player_idx):
				spr.play("walk"), 
		CONNECT_ONE_SHOT)

		# Return to walk state when the distinct resource finishes playing
		spr.animation_finished.connect(func():
			if is_instance_valid(spr) and alive_players.has(player_idx):
				spr.play("walk")
		, CONNECT_ONE_SHOT)
	else:
		if status:
			status.text = "Aray!"
			status.modulate = Color(0.9, 0.3, 0.3)
		
		var spr: AnimatedSprite2D = char_sprites[player_idx]
		spr.stop()
		spr.modulate = Color(0.4, 0.4, 0.4)
			
		if DEBUG_FORCE_LOCAL_TEST :
			alive_players.erase(player_idx)
		else:
			_eliminate(player_idx)

func _end_round_sweep() -> void:
	sweeping = false
	var is_local_test: bool = DEBUG_FORCE_LOCAL_TEST 
	
	# ️ HARD SANDBOX RESET FOR F6 TESTING
	if is_local_test:
		print("--- ROUND ENDED (SANDBOX) ---")
		
		# Eliminate anyone who didn't trigger a jump callback
		for player_idx in alive_players.duplicate():
			if not jumped_this_round.has(player_idx):
				if bars.has(player_idx):
					var status: Label = bars[player_idx].get_node_or_null("Status")
					if status:
						status.text = "Aray!"
						status.modulate = Color(0.9, 0.3, 0.3)
				
				if char_sprites.has(player_idx):
					var spr: AnimatedSprite2D = char_sprites[player_idx]
					spr.stop()
					spr.modulate = Color(0.4, 0.4, 0.4)
				
				alive_players.erase(player_idx)
		
		# Evaluate Game Over conditions natively inside the sandbox
		if alive_players.size() == 0:
			print("--- GAME OVER: ALL PLAYERS ELIMINATED ---")
			countdown_label.text = "GAME OVER"
			return
			
		await get_tree().create_timer(1.0).timeout

		jumped_this_round.clear()
		eliminated_this_round.clear()
		
		round_time = max(ROUND_TIME_MIN, round_time * ROUND_SPEEDUP)
		zone_width = max(ZONE_WIDTH_MIN, zone_width * ZONE_SHRINK)
		
		_start_countdown()
		_begin_round(randf_range(0.0, 1.0 - zone_width))
		return

	# --- ORIGINAL BACKEND LOBBY MULTIPLAYER CODE ---
	if not NetworkManager.is_host:
		return

	var auto_eliminated: Array[int] = []
	for player_idx in alive_players.duplicate():
		if not jumped_this_round.has(player_idx):
			auto_eliminated.append(player_idx)

	NetworkManager.sync_luksong_round_end.rpc(auto_eliminated)

func apply_jump_result(player_idx: int, in_zone: bool) -> void:
	if not alive_players.has(player_idx):
		return
	play_jump_sfx()
	jumped_this_round[player_idx] = true
	var status: Label = null
	if bars.has(player_idx):
		status = bars[player_idx].get_node_or_null("Status")
	if status:
		status.text = "Ligtas!" if in_zone else "Aray!"
		status.modulate = Color(0.3, 0.9, 0.4) if in_zone else Color(0.9, 0.3, 0.3)
		
	if in_zone:
		if char_sprites.has(player_idx):
			var spr: AnimatedSprite2D = char_sprites[player_idx]
			spr.play("jump")
			
			var tween = create_tween().set_parallel(false)
			var jump_height := 150.0  
			var jump_duration := 0.25 
			
			# Animate upward and back down relative to standard footing alignment
			tween.tween_property(spr, "position:y", CHAR_Y - jump_height, jump_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(spr, "position:y", CHAR_Y, jump_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

			spr.animation_finished.connect(func():
				if is_instance_valid(spr) and alive_players.has(player_idx):
					spr.play("walk")
				, CONNECT_ONE_SHOT)
	else:
		if char_sprites.has(player_idx):
			char_sprites[player_idx].stop()
			char_sprites[player_idx].modulate = Color(0.4, 0.4, 0.4)
			
		if quadrants.has(player_idx):
			var obstacle = quadrants[player_idx].get_node_or_null("SubViewport/Obstacle")
			if obstacle:
				obstacle.hide()
				
		_eliminate(player_idx)

func apply_round_end(auto_eliminated: Array) -> void:
	for player_idx in auto_eliminated:
		var status: Label = null
		if bars.has(player_idx):
			status = bars[player_idx].get_node_or_null("Status")
		if status:
			status.text = "Aray!"
			status.modulate = Color(0.9, 0.3, 0.3)
		if char_sprites.has(player_idx):
			char_sprites[player_idx].stop()
			char_sprites[player_idx].modulate = Color(0.4, 0.4, 0.4)
			
		#  FIXED: Moved inside the loop so player_idx and obstacle are in scope
		if quadrants.has(player_idx):
			var obstacle = quadrants[player_idx].get_node_or_null("SubViewport/Obstacle")
			if obstacle:
				obstacle.hide() # Hides the hurdle instantly on failure
				
		_eliminate(player_idx)

	# This logic runs after the loop finishes processing all players
	if eliminated_this_round.size() > 0:
		elimination_order.append(eliminated_this_round.duplicate())
	
	_check_game_over()

func _eliminate(player_idx: int) -> void:
	alive_players.erase(player_idx)
	eliminated_this_round.append(player_idx)

func _check_game_over() -> void:
	var is_local_test: bool = DEBUG_FORCE_LOCAL_TEST 

	if alive_players.size() <= 1:
		print("--- GAME OVER (No players left or 1 winner) ---")
		if not is_local_test:
			_end_game()
		return

	round_time = max(ROUND_TIME_MIN, round_time * ROUND_SPEEDUP)
	zone_width = max(ZONE_WIDTH_MIN, zone_width * ZONE_SHRINK)

	if is_local_test:
		_start_countdown()
	else:
		await get_tree().create_timer(1.0).timeout
		_start_countdown()

func _end_game() -> void:
	var groups: Array = []
	if alive_players.size() == 1:
		groups.append(alive_players.duplicate())
	var reversed_eliminations: Array = elimination_order.duplicate()
	reversed_eliminations.reverse()
	groups += reversed_eliminations

	var scores: Dictionary = compute_placement_scores(groups)
	_finish(scores)

# ---------------------------------------------------------------------------
# Visual helpers - Handles targeted viewport processing and dynamic instantiation
# ---------------------------------------------------------------------------

## Cleanly instantiates viewports and drops in unique character scene copies
func _spawn_splitscreen_worlds() -> void:
	for child in splitscreen_grid.get_children():
		child.queue_free()
		
	quadrants.clear()
	char_sprites.clear()
	bars.clear()

	var visible_players: Array = participating_players
	splitscreen_grid.columns = 2
	#if not DEBUG_FORCE_LOCAL_TEST:
		#visible_players = [NetworkManager.get_my_player_index()]

	for player_idx in range(4):
		var quad = QUADRANT_SCENE.instantiate()
		quad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quad.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		quad.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		
		splitscreen_grid.add_child(quad)
		quadrants[player_idx] = quad
		
		var viewport: SubViewport = quad.get_node("SubViewport")
		var bar_ui = quad.get_node_or_null("PlayerBarUI")
		
		# 1. Clear out the placeholder character inside the base quadrant file
		var old_char = viewport.get_node_or_null("Character")
		if old_char:
			old_char.queue_free()
		
		# 2. Check if this slot belongs to an active player
		if visible_players.has(player_idx):
			quadrants[player_idx] = quad
			if PLAYER_SCENES.has(player_idx):
				var character_scene: PackedScene = PLAYER_SCENES[player_idx]
				var spr = character_scene.instantiate() as AnimatedSprite2D
				
				viewport.add_child(spr)
				spr.name = "Character" # Rename to keep code references consistent across scripts
				
				spr.scale = Vector2(CHAR_SCALE, CHAR_SCALE)
				spr.position = Vector2(80.0, CHAR_Y)
				
				spr.play("walk")
				char_sprites[player_idx] = spr
			
			if bar_ui:
				bars[player_idx] = bar_ui
				bar_ui.show()
			
		else:
			quad.modulate = Color(0.2, 0.2, 0.2, 1.0)
			if bar_ui:
				bar_ui.hide()
				
			var bg: Parallax2D = quad.get_node_or_null("SubViewport/Parallax2D")
			if bg:
				bg.autoscroll.x = 0.0
				
			var obstacle = quad.get_node_or_null("SubViewport/Obstacle")
			if obstacle:
				obstacle.hide()
			var placeholder_char = viewport.get_node_or_null("Character")
			if placeholder_char and placeholder_char is AnimatedSprite2D:
				placeholder_char.hide()
			
## Cycles through viewports and shifts backgrounds only if that specific quadrant is active
## Cycles through viewports and shifts backgrounds only if that specific quadrant is active
func _scroll_buildings(_delta: float) -> void:
	var speed_mult: float = ROUND_TIME_START / max(round_time, ROUND_TIME_MIN)
	var base_speed: float = -400.0 
	
	var visible_players: Array = participating_players
	#if not DEBUG_FORCE_LOCAL_TEST:
		#visible_players = [NetworkManager.get_my_player_index()]

	for player_idx in visible_players:
		if quadrants.has(player_idx):
			var quad = quadrants[player_idx]
			var bg: Parallax2D = quad.get_node_or_null("SubViewport/Parallax2D")
			
			if bg:
				#  If the player is alive AND the game is actively sweeping, scroll!
				if alive_players.has(player_idx) and sweeping and not gameplay_locked:
					bg.autoscroll.x = base_speed * speed_mult
				else:
					#  Otherwise, freeze their background completely
					bg.autoscroll.x = 0.0
					
func _show_tutorial_png() -> void:
	if current_round > 1:
		return
		
	var tutorial_tex = load(TUTORIAL_PNG_PATH)
	if not tutorial_tex:
		print("Error: Could not find the tutorial PNG file path")
		return

	tutorial_node = CanvasLayer.new()
	tutorial_node.layer = 128
	add_child(tutorial_node)

	var tut_rect := TextureRect.new()
	tut_rect.texture = tutorial_tex
	
	tut_rect.custom_minimum_size = tutorial_tex.get_size()
	
	tut_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	tut_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	
	tut_rect.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tut_rect.grow_vertical = Control.GROW_DIRECTION_BOTH
	tut_rect.set_anchors_preset(Control.PRESET_CENTER)
	
	tutorial_node.add_child(tut_rect)
	tut_rect.set_anchors_preset(Control.PRESET_CENTER)
