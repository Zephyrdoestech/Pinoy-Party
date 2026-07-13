class_name LangitLupa
extends BaseMinigame

const MOVE_SPEED := 300.0
const JUMP_VELOCITY := -600.0
const GRAVITY := 1400.0
const FLOOD_RISE_SPEED := 15.0   # px/sec, tune to taste
const COYOTE_TIME := 0.15
const SCREEN_MARGIN := 100.0
const LAYER_HEIGHT := 100.0
const COLUMN_SPACING := 350.0   # must stay <= your real max horizontal jump distance
const PLATFORM_WIDTH := 150.0
const TUTORIAL_IMAGE_PATH := "res://assets/tutorials/tutorial_langit_lupa.png"
const PLATFORM_TEXTURES: Array[Texture2D] = [
	preload("res://assets/minigame_assets/langit_lupa_assets/LangitLupa_platform.png"),
	preload("res://assets/minigame_assets/langit_lupa_assets/LangitLupa_platform2.png")
]
const PLATFORM_VISUAL_HEIGHT := 48.0
# Set from NetworkManager.get_my_player_index() at start_game() - replaces
# the old hardcoded 0, which assumed the host was always Player 0.
var local_player_index := -1
var facing_right := true
var alive_players: Array[int] = []
var elimination_order: Array = []      # Array[Array[int]] - tie-groups, in elimination order
var flood_start_y: float
@onready var flood: Area2D = $Flood
@onready var flood_sprite: AnimatedSprite2D = $"Flood/flood sprite"
var round_start_msec: int
var round_active: bool = false
var _coyote_timer: float = 0.
var finished_players: Array[int] = []

# Position sync - each client broadcasts their position at SYNC_HZ rate.
# Host collects all positions and rebroadcasts to everyone.
const POSITION_SYNC_HZ := 20.0
var _position_sync_timer := 0.0
	
func start_round_synced() -> void:
	round_start_msec = Time.get_ticks_msec()

func start_game(players: Array[int]) -> void:
	super.start_game(players)
	local_player_index = NetworkManager.get_my_player_index()
	alive_players = players.duplicate()
	elimination_order.clear()
	await get_tree().process_frame
	_auto_position_spawn_and_goal()
	_position_players()
	_hide_inactive_players()
	_generate_platforms()
	flood_start_y = $Flood.position.y
	flood_sprite.play("default") 
	
	gameplay_locked = true
	if not GameManager.has_shown_tutorial("langit_lupa"):
		GameManager.mark_tutorial_shown("langit_lupa")
		_show_intro_tutorial_synced()
	
	await run_intro("")
	if NetworkManager.is_host:
		NetworkManager.sync_langitlupa_start.rpc()

# Builds the blurring layout wrapper on every client machine locally
func _show_intro_tutorial_synced() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 128
	add_child(overlay)
	
	var blur_rect := ColorRect.new()
	blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\n" + \
				  "uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;\n" + \
				  "uniform float lod: hint_range(0.0, 5.0) = 2.5;\n" + \
				  "void fragment() {\n" + \
				  "    COLOR = textureLod(screen_texture, SCREEN_UV, lod);\n" + \
				  "}"
	
	var mat := ShaderMaterial.new()
	mat.shader = shader
	blur_rect.material = mat
	overlay.add_child(blur_rect)
	
	var click_zone := TextureButton.new()
	click_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(click_zone)
	
	var tut_texture: Texture2D = load(TUTORIAL_IMAGE_PATH)
	if tut_texture:
		var tut_rect := TextureRect.new()
		tut_rect.texture = tut_texture
		tut_rect.set_anchors_preset(Control.PRESET_CENTER)
		tut_rect.grow_horizontal = Control.GROW_DIRECTION_BOTH
		tut_rect.grow_vertical = Control.GROW_DIRECTION_BOTH
		tut_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		click_zone.add_child(tut_rect)
		
	var flash_label := Label.new()
	flash_label.set_anchors_preset(Control.PRESET_CENTER)
	flash_label.position.y += 250
	flash_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	flash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	click_zone.add_child(flash_label)
	
	# Evaluate authority permissions
	var is_offline := not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	var can_interact := is_offline or NetworkManager.is_host
	
	if can_interact:
		flash_label.text = "Click anywhere to start the round..."
		var tween = create_tween().set_loops()
		tween.tween_property(flash_label, "modulate:a", 0.2, 0.6).set_trans(Tween.TRANS_SINE)
		tween.tween_property(flash_label, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
		
		click_zone.pressed.connect(func():
			tween.kill()
			if is_offline:
				_sync_dismiss_tutorial_and_start()
			else:
				rpc("_sync_dismiss_tutorial_and_start")
		)
	else:
		flash_label.text = "Waiting for host to dismiss tutorial..."
		flash_label.modulate.a = 0.7
		click_zone.disabled = true


@rpc("authority", "call_local", "reliable")
func _sync_dismiss_tutorial_and_start() -> void:
	# Cleans up the custom tutorial CanvasLayer on everyone's screen
	for child in get_children():
		if child is CanvasLayer and child.layer == 128:
			child.queue_free()
			
	# Lifts the block so physics engine and loops run together on the same frame
	gameplay_locked = false
	round_start_msec = Time.get_ticks_msec()
	round_active = true
	
	# Host signals the underlying server network state to listen for inputs
	if NetworkManager.is_host and multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		NetworkManager.sync_langitlupa_start.rpc()

func _position_players() -> void:
	var spawn_pos: Vector2 = $Platforms/SpawnPlatform.position
	for i in participating_players.size():
		var idx: int = participating_players[i]
		var node := _get_player_node(idx)
		node.position = spawn_pos + Vector2(i * 40.0 - 60.0, -30.0)

func _hide_inactive_players() -> void:
	for i in Constants.MAX_PLAYERS:
		var node := _get_player_node(i)
		var active := participating_players.has(i)
		node.visible = active
		node.set_physics_process(active)

func _auto_position_spawn_and_goal() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	$Platforms/SpawnPlatform.position = Vector2(SCREEN_MARGIN, viewport_size.y - SCREEN_MARGIN)
	$Platforms/GoalPlatform.position = Vector2(viewport_size.x - SCREEN_MARGIN, SCREEN_MARGIN)
	$Flood.position = Vector2(-viewport_size.x, viewport_size.y + 60.0)
	$Flood.get_node("ColorRect").size = Vector2(viewport_size.x * 3.0, 40.0)

func _generate_platforms() -> void:
	var spawn_pos: Vector2 = $Platforms/SpawnPlatform.position
	var goal_pos: Vector2 = $Platforms/GoalPlatform.position

	var total_height: float = abs(spawn_pos.y - goal_pos.y)
	var total_width: float = abs(spawn_pos.x - goal_pos.x)
	var num_rows: int = max(1, int(total_height / LAYER_HEIGHT))
	var num_cols: int = max(2, int(total_width / COLUMN_SPACING) + 1)

	var min_x: float = min(spawn_pos.x, goal_pos.x)
	var direction_x: float = sign(goal_pos.x - spawn_pos.x)
	if direction_x == 0.0:
		direction_x = 1.0

	for row in range(1, num_rows + 1):
		var y: float = spawn_pos.y - row * LAYER_HEIGHT
		# Zigzag brick pattern: odd rows offset by half a column so platforms
		# alternate position row-to-row instead of stacking directly above each other.
		var col_offset: float = (COLUMN_SPACING * 0.5) if row % 2 == 1 else 0.0

		for col in num_cols:
			var x: float = min_x + direction_x * (col * COLUMN_SPACING + col_offset)
			# Skip anything that would land past the goal's X or off the near edge -
			# keeps the grid from overshooting the level bounds.
			if x < SCREEN_MARGIN or x > get_viewport_rect().size.x - SCREEN_MARGIN:
				continue
			_spawn_platform_node(Vector2(x, y), row, col)

func _clear_generated_platforms() -> void:
	for child in $Platforms.get_children():
		if child.name.begins_with("GenPlatform_"):
			child.queue_free()

func _spawn_platform_node(pos: Vector2, layer: int, index: int) -> void:
	var plat := StaticBody2D.new()
	plat.name = "GenPlatform_%d_%d" % [layer, index]
	plat.position = pos

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(PLATFORM_WIDTH, 20.0)
	shape.shape = rect
	plat.add_child(shape)

	var visual := Sprite2D.new()
	var texture := PLATFORM_TEXTURES[(layer + index) % PLATFORM_TEXTURES.size()]
	visual.texture = texture
	visual.centered = true
	visual.position = Vector2.ZERO
	if texture:
		visual.scale = Vector2(
			PLATFORM_WIDTH / texture.get_width(),
			PLATFORM_VISUAL_HEIGHT / texture.get_height()
		)
	plat.add_child(visual)

	$Platforms.add_child(plat)

func _get_player_node(idx: int) -> CharacterBody2D:
	return get_node("Players/Player %d" % (idx + 1))

func _get_player_sprite(idx: int) -> AnimatedSprite2D:
	var player := _get_player_node(idx)
	match idx:
		0: return player.get_node("player1node")
		1: return player.get_node("player2node")
		2: return player.get_node("player3node")
		3: return player.get_node("player4node")
	return null

func apply_remote_state(player_idx: int, pos: Vector2, anim_name: String) -> void:
	if player_idx != local_player_index:
		_get_player_node(player_idx).position = pos
		var sprite = _get_player_sprite(player_idx)
		if sprite and anim_name != "" and sprite.animation != anim_name:
			sprite.play(anim_name)

func _process(delta: float) -> void:
	if not round_active or gameplay_locked:
		return

	_position_sync_timer += delta
	if _position_sync_timer >= 1.0 / POSITION_SYNC_HZ:
		_position_sync_timer = 0.0
		if local_player_index != -1:
			var my_pos: Vector2 = _get_player_node(local_player_index).position
			var sprite := _get_player_sprite(local_player_index)
			var my_anim: String = sprite.animation if sprite else ""
			if NetworkManager.is_host:
				NetworkManager.process_langitlupa_state(local_player_index, my_pos, my_anim)
			else:
				NetworkManager.send_langitlupa_state.rpc_id(1, local_player_index, my_pos, my_anim)
	# Flood visual - every peer computes this locally from round_start_msec, no need to sync.
	$Flood.position.y = _get_flood_y()

	# Authoritative elimination check runs on host only (or offline debug mode).
	if NetworkManager.is_host or not multiplayer.has_multiplayer_peer():
		_check_flood()
		_check_goal()

func _physics_process(delta: float) -> void:
	if not round_active or gameplay_locked:
		return
	if local_player_index == -1 or not alive_players.has(local_player_index):
		return

	var player := _get_player_node(local_player_index)
	var sprite := _get_player_sprite(local_player_index)
	player.velocity.y += GRAVITY * delta

	if player.is_on_floor():
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer -= delta

	var direction := 0.0

	if Input.is_action_pressed("move_left"):
		direction = -1.0
	elif Input.is_action_pressed("move_right"):
		direction = 1.0

	player.velocity.x = direction * MOVE_SPEED
	if direction > 0:
		facing_right = true
	elif direction < 0:
		facing_right = false

	if Input.is_action_just_pressed("jump") and _coyote_timer > 0.0:
		play_jump_sfx()
		player.velocity.y = JUMP_VELOCITY
		_coyote_timer = 0.0   # consume it so you can't double-jump off the same window
	
	if not player.is_on_floor():
		if facing_right:
			if sprite.animation != "jumpRight":
				sprite.play("jumpRight")
		else:
			if sprite.animation != "jumpLeft":
				sprite.play("jumpLeft")
	elif direction != 0:
		if facing_right:
			if sprite.animation != "walkRight":
				sprite.play("walkRight")
		else:
			if sprite.animation != "walkLeft":
				sprite.play("walkLeft")
	else:
		if facing_right:
			if sprite.animation != "idleRight":
				sprite.play("idleRight")
		else:
			if sprite.animation != "idleLeft":
				sprite.play("idleLeft")
				
	player.move_and_slide()

func _get_flood_y() -> float:
	var elapsed_sec := (Time.get_ticks_msec() - round_start_msec) / 1000.0
	return flood_start_y - FLOOD_RISE_SPEED * elapsed_sec

## Host-only. Checks every alive player against the current flood line.
func _check_flood() -> void:
	var current_flood_y := _get_flood_y()

	for idx in alive_players.duplicate():
		var p := _get_player_node(idx)		
		if is_instance_valid(p) and p.global_position.y >= current_flood_y:
			_eliminate_player(idx)

## Host-only. Checks every remaining player against the goal platform's top edge.
func _check_goal() -> void:
	var goal: StaticBody2D = $Platforms/GoalPlatform
	var goal_top: float = goal.position.y - 10.0   # top surface of the 20px-tall platform
	var goal_left: float = goal.position.x - PLATFORM_WIDTH * 0.5
	var goal_right: float = goal.position.x + PLATFORM_WIDTH * 0.5

	for idx in alive_players.duplicate():
		var p := _get_player_node(idx)
		if not is_instance_valid(p):
			continue
		var touching_top: bool = p.global_position.y <= goal_top + 5.0 \
			and p.global_position.x >= goal_left and p.global_position.x <= goal_right
		if touching_top:
			_finish_player(idx)

## Host-only. Records a finish, removes them from the active race, checks for round end.
func _finish_player(idx: int) -> void:
	if not alive_players.has(idx):
		return  # already finished or already flooded - guard against double-fire
	alive_players.erase(idx)
	finished_players.append(idx)
	if alive_players.size() <= 1:
		NetworkManager.sync_langitlupa_end.rpc(_compute_final_scores())

## Host-only. Removes a player, broadcasts it, ends the round if ≤1 remain.
func _eliminate_player(idx: int) -> void:
	if not alive_players.has(idx):
		return  # guard against double-fire in the same frame
	alive_players.erase(idx)
	elimination_order.append([idx])
	NetworkManager.broadcast_langitlupa_elimination.rpc(idx)
	if alive_players.size() <= 1:
		NetworkManager.sync_langitlupa_end.rpc(_compute_final_scores())

## Called on every peer (including host) when NetworkManager broadcasts an elimination.
func apply_elimination(player_idx: int) -> void:
	_get_player_node(player_idx).modulate.a = 0.3

func _compute_final_scores() -> Dictionary:
	var placement_points := [3, 2, 1]
	var scores := {}
	
	var ranking: Array[int] = []
	# 1. Players who reached the goal
	ranking.append_array(finished_players)
	# 2. Any remaining alive players who survived until the end
	ranking.append_array(alive_players)
	# 3. Eliminated players (last to die ranks higher than first to die)
	var reversed_eliminations = elimination_order.duplicate()
	reversed_eliminations.reverse()
	for group in reversed_eliminations:
		ranking.append_array(group)
		
	for i in ranking.size():
		if i < placement_points.size():
			scores[ranking[i]] = placement_points[i]
			
	return scores

func _end_game(scores: Dictionary) -> void:
	round_active = false
	gameplay_locked = true
	_clear_generated_platforms()

	print("[LangitLupa] Round over. Elimination order: %s" % [elimination_order])
	_finish(scores)
