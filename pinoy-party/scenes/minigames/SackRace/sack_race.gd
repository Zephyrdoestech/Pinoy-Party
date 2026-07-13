class_name SackRace
extends BaseMinigame

const FINISH_DISTANCE := 48.0      # "hops" needed to win
const HOP_DISTANCE := 1.0          # progress per press
const RACE_TIMEOUT := 15.0         # seconds, safety net
const HOP_PIXELS := 30.0           # how many pixels each ColorRect moves per press
const TUTORIAL_IMAGE_PATH := "res://assets/tutorials/tutorial_sack_race.png"
const SACK_RACE_UI_FONT := preload("res://assets/fonts/GrapeSoda.ttf")
const TIMER_BG := preload("res://assets/board_assets/Trivia/timer_container.png")
const TIMER_SIZE := Vector2(160, 46)

var progress: Dictionary = {}      # player_idx -> float progress
var finished_order: Array[int] = []
var race_active := false
var timeout_timer := 0.0
var _timer_container: TextureRect = null
@onready var timer_label: Label = $UI/TimerLabel

func _get_track_node(player_idx: int) -> Node2D:
	var path := "SplitScreenContainer/P%d_Container/Viewport%d/Track%d/Player%d" % [
		player_idx + 1, player_idx + 1, player_idx + 1, player_idx + 1
	]
	
	var node = get_node_or_null(path)
	if not node:
		return null
	return node

func start_game(players: Array[int]) -> void:
	super.start_game(players)
	
	# If we are online, the host tells everyone to execute the visual positioning logic
	if multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		if NetworkManager.is_host:
			rpc("_sync_local_client_setup", players)
	else:
		# Offline fallback
		_sync_local_client_setup(players)


# synchronized RPC function that configures the UI for each client player
@rpc("authority", "call_local", "reliable")
func _sync_local_client_setup(players: Array[int]) -> void:
	# Move variables to local scope for everyone
	for idx in players:
		progress[idx] = 0.0
		var node := _get_track_node(idx)
		if node:
			node.position.x = 0.0  
			
	finished_order.clear()
	timeout_timer = 0.0
	_style_timer()
	_update_timer_label(RACE_TIMEOUT)

	var countdown_label = get_node_or_null("UI/CountdownLabel") 
	if countdown_label:
		countdown_label.position.y += 400.0 

	var tutorial_overlay: CanvasLayer = null
	if not GameManager.has_shown_tutorial("sack_race"):
		GameManager.mark_tutorial_shown("sack_race")
		tutorial_overlay = _show_intro_tutorial()
	
	_manage_client_intro_lifecycle(tutorial_overlay)


# Helper tool to await completion locally without stalling the RPC network threat pipeline
func _manage_client_intro_lifecycle(overlay: CanvasLayer) -> void:
	await run_intro()
	if is_instance_valid(overlay):
		overlay.queue_free()
	
	# Only flip the active game state flag locally when the intro concludes
	race_active = true

func _show_intro_tutorial() -> CanvasLayer:
	var overlay := CanvasLayer.new()
	overlay.layer = 128
	add_child(overlay)
	
	# Background Blur 
	var blur_rect := ColorRect.new()
	blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\n" + \
				  "uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;\n" + \
				  "uniform float lod: hint_range(0.0, 5.0) = 2.0;\n" + \
				  "void fragment() {\n" + \
				  "    COLOR = textureLod(screen_texture, SCREEN_UV, lod);\n" + \
				  "}"
	
	var mat := ShaderMaterial.new()
	mat.shader = shader
	blur_rect.material = mat
	overlay.add_child(blur_rect)
	
	# Full-screen click zone so players can dismiss the tutorial
	var click_zone := TextureButton.new()
	click_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(click_zone)
	
	# Tutorial Graphic Panel
	var tut_texture: Texture2D = load(TUTORIAL_IMAGE_PATH)
	if tut_texture:
		var tut_rect := TextureRect.new()
		tut_rect.texture = tut_texture
		tut_rect.set_anchors_preset(Control.PRESET_CENTER)
		tut_rect.grow_horizontal = Control.GROW_DIRECTION_BOTH
		tut_rect.grow_vertical = Control.GROW_DIRECTION_BOTH
		tut_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		click_zone.add_child(tut_rect)

	# Flashing "click to dismiss" prompt, matching langit_lupa's tutorial UX
	var flash_label := Label.new()
	flash_label.text = "Click anywhere to continue..."
	flash_label.set_anchors_preset(Control.PRESET_CENTER)
	flash_label.position.y += 250
	flash_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	flash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	click_zone.add_child(flash_label)
	var tween = create_tween().set_loops(9999)
	tween.tween_property(flash_label, "modulate:a", 0.2, 0.6).set_trans(Tween.TRANS_SINE)
	tween.tween_property(flash_label, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)

	# Pressing anywhere dismisses the overlay immediately
	click_zone.pressed.connect(func():
		tween.kill()
		overlay.queue_free()
	)
		
	return overlay

func _process(delta: float) -> void:
	if not race_active or gameplay_locked:
		return
	timeout_timer += delta
	var time_left := RACE_TIMEOUT - timeout_timer
	_update_timer_label(max(time_left, 0.0))
	if timeout_timer >= RACE_TIMEOUT:
		_end_race()

func _style_timer() -> void:
	if timer_label == null:
		return
	if _timer_container == null:
		_timer_container = TextureRect.new()
		_timer_container.name = "TimerContainer"
		_timer_container.texture = TIMER_BG
		_timer_container.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_timer_container.stretch_mode = TextureRect.STRETCH_SCALE
		_timer_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_timer_container.offset_left = -TIMER_SIZE.x * 0.5
		_timer_container.offset_top = 0.0
		_timer_container.offset_right = TIMER_SIZE.x * 0.5
		_timer_container.offset_bottom = TIMER_SIZE.y
		$UI.add_child(_timer_container)
		$UI.move_child(_timer_container, timer_label.get_index())

	timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_label.offset_left = -TIMER_SIZE.x * 0.5
	timer_label.offset_top = 0.0
	timer_label.offset_right = TIMER_SIZE.x * 0.5
	timer_label.offset_bottom = TIMER_SIZE.y
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_override("font", SACK_RACE_UI_FONT)
	timer_label.add_theme_font_size_override("font_size", 30)
	timer_label.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24))

func _update_timer_label(time_left: float) -> void:
	if timer_label:
		timer_label.text = "%.1f" % time_left

func _input(event: InputEvent) -> void:
	if not race_active:
		return
	if not event.is_action_pressed("jump"):
		return
	#DEBUG
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		apply_hop(1) # control p1 for testing
		return
		
	var my_idx: int = NetworkManager.get_my_player_index()
	if my_idx == -1 or my_idx not in participating_players:
		return  # not a participant in this race (or no LAN match active)
	if my_idx in finished_order:
		return  # already finished, ignore further presses
	# Route through the host so every client's progress stays in sync -
	# same request -> host-broadcast pattern used for dice rolls.
	if NetworkManager.is_host or not multiplayer.has_multiplayer_peer():
		NetworkManager.process_sack_race_hop(my_idx)
	else:
		NetworkManager.request_sack_race_hop.rpc_id(1, my_idx)

## Called by NetworkManager._apply_sack_race_hop() on every peer once the
## host has validated and broadcast the hop. This is the only place
## progress should be advanced from now - local input no longer calls
## _advance() directly, it just requests a hop via NetworkManager.
func apply_hop(player_idx: int) -> void:
	if not race_active:
		return
	if player_idx in finished_order:
		return
	play_jump_sfx()
	_advance(player_idx)

func _advance(player_idx: int) -> void:
	
	progress[player_idx] += HOP_DISTANCE
	var player_node := _get_track_node(player_idx)
	
	if player_node:
		player_node.position.x = progress[player_idx] * HOP_PIXELS
		var anim = player_node.find_child("AnimationPlayer")
		if anim:
			player_node.find_child("AnimationPlayer").play("jump")
	
	if progress[player_idx] >= FINISH_DISTANCE and player_idx not in finished_order:
		finished_order.append(player_idx)
		if finished_order.size() == participating_players.size():
			_end_race()

func _end_race() -> void:
	race_active = false

	# Players who actually crossed the finish line have a strict, tie-free
	# order (only one player advances per key-press event, so two players
	# can't finish on the exact same input) - each is their own group.
	var groups: Array = []
	for idx in finished_order:
		groups.append([idx])

	# Anyone who didn't finish is ranked by remaining progress, with equal
	# progress at the timeout treated as a genuine tie (grouped together)
	# instead of being arbitrarily ordered by sort_custom.
	var unfinished: Array[int] = participating_players.filter(func(p): return p not in finished_order)
	unfinished.sort_custom(func(a, b): return progress[a] > progress[b])

	var i := 0
	while i < unfinished.size():
		var tie_group: Array = [unfinished[i]]
		var j := i + 1
		while j < unfinished.size() and is_equal_approx(progress[unfinished[j]], progress[unfinished[i]]):
			tie_group.append(unfinished[j])
			j += 1
		groups.append(tie_group)
		i = j

	var scores: Dictionary = BaseMinigame.compute_placement_scores(groups)
	_finish(scores)
