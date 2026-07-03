class_name LangitLupa
extends BaseMinigame

const MOVE_SPEED := 300.0
const JUMP_VELOCITY := -600.0
const GRAVITY := 1400.0
const NUM_LAYERS := 5
const FLOOD_RISE_SPEED := 15.0   # px/sec, tune to taste
const PLATFORMS_PER_LAYER_MIN := 5
const PLATFORMS_PER_LAYER_MAX := 8
const LAYER_HEIGHT := 90.0
const MAX_JUMP_DX := 150.0        # max horizontal reach between two connected platforms
const COYOTE_TIME := 0.15
const PLATFORM_WIDTH := 100.0
const SCREEN_MARGIN := 150.0

# Set from NetworkManager.get_my_player_index() at start_game() — replaces
# the old hardcoded 0, which assumed the host was always Player 0.
var local_player_index := -1

var alive_players: Array[int] = []
var elimination_order: Array = []      # Array[Array[int]] — tie-groups, in elimination order
var flood_start_y: float
var round_start_msec: int
var round_active: bool = false
var _platform_rng := RandomNumberGenerator.new()
var _coyote_timer: float = 0.0

# Position sync — each client broadcasts their position at SYNC_HZ rate.
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
	_auto_position_spawn_and_goal()
	_position_players()
	_hide_inactive_players()
	flood_start_y = $Flood.position.y
	await run_intro("")
	if NetworkManager.is_host:
		var seed_value: int = randi()
		NetworkManager.sync_langitlupa_platforms.rpc(seed_value)

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

func _generate_platforms(seed_value: int) -> void:
	print("[LangitLupa] Generating platforms with seed ", seed_value)
	_platform_rng.seed = seed_value

	var spawn_pos: Vector2 = $Platforms/SpawnPlatform.position
	var goal_pos: Vector2 = $Platforms/GoalPlatform.position
	print("[LangitLupa] spawn_pos=%s goal_pos=%s $Platforms.global_position=%s" % [spawn_pos, goal_pos, $Platforms.global_position])

	var total_height: float = abs(spawn_pos.y - goal_pos.y)
	var num_layers: int = clamp(int(total_height / LAYER_HEIGHT) - 1, 1, NUM_LAYERS)

	var prev_layer_x: Array[float] = [spawn_pos.x]
	var two_layers_ago_x: Array[float] = []
	var current_y: float = spawn_pos.y - LAYER_HEIGHT

	for layer in num_layers:
		var count: int = _platform_rng.randi_range(PLATFORMS_PER_LAYER_MIN, PLATFORMS_PER_LAYER_MAX)
		var new_layer_x: Array[float] = []

		for i in count:
			var anchor_x: float = prev_layer_x[_platform_rng.randi_range(0, prev_layer_x.size() - 1)]
			var viewport_size: Vector2 = get_viewport_rect().size
			var min_x: float = SCREEN_MARGIN
			var max_x: float = viewport_size.x - SCREEN_MARGIN

			var x: float = 0.0
			var attempts := 0
			while attempts < 10:
				var offset: float = _platform_rng.randf_range(-MAX_JUMP_DX, MAX_JUMP_DX)
				x = clamp(anchor_x + offset, min_x, max_x)
				var blocked := false
				for old_x in two_layers_ago_x:
					if abs(x - old_x) < PLATFORM_WIDTH:
						blocked = true
						break
				if not blocked:
					break
				attempts += 1

			new_layer_x.append(x)
			_spawn_platform_node(Vector2(x, current_y), layer, i)

		two_layers_ago_x = prev_layer_x
		prev_layer_x = new_layer_x
		current_y -= LAYER_HEIGHT

	# Guaranteed connector platform directly bridging the last layer to the goal.
	var closest_x: float = prev_layer_x[0]
	var closest_dist: float = abs(closest_x - goal_pos.x)
	for px in prev_layer_x:
		if abs(px - goal_pos.x) < closest_dist:
			closest_x = px
			closest_dist = abs(px - goal_pos.x)

	var connector_x: float = closest_x
	var connector_y: float = current_y
	var connector_id: int = 0
	while abs(connector_y - goal_pos.y) > LAYER_HEIGHT:
		connector_y -= LAYER_HEIGHT
		connector_x += clamp(goal_pos.x - connector_x, -MAX_JUMP_DX, MAX_JUMP_DX)
		_spawn_platform_node(Vector2(connector_x, connector_y), 999, connector_id)
		connector_id += 1

func _spawn_platform_node(pos: Vector2, layer: int, index: int) -> void:
	var plat := StaticBody2D.new()
	plat.name = "GenPlatform_%d_%d" % [layer, index]
	plat.position = pos

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(PLATFORM_WIDTH, 20.0)
	shape.shape = rect
	plat.add_child(shape)

	var visual := ColorRect.new()
	visual.size = Vector2(PLATFORM_WIDTH, 20.0)
	visual.color = Color(0.6, 0.4, 0.2)   
	visual.position = -visual.size / 2.0
	plat.add_child(visual)

	$Platforms.add_child(plat)
	print("[LangitLupa] Platform '%s' at %s" % [plat.name, plat.global_position])

func _clear_generated_platforms() -> void:
	for child in $Platforms.get_children():
		if child.name.begins_with("GenPlatform_"):
			child.queue_free()

func _get_player_node(idx: int) -> CharacterBody2D:
	return get_node("Players/Player %d" % (idx + 1))

func _process(delta: float) -> void:
	if gameplay_locked:
		return

	if not round_active:
		round_active = true
		print("[LangitLupa] Round started.")

	# Position sync — local client sends its position to host at POSITION_SYNC_HZ.
	_position_sync_timer += delta
	if _position_sync_timer >= 1.0 / POSITION_SYNC_HZ:
		_position_sync_timer = 0.0
		if local_player_index != -1:
			var my_pos: Vector2 = _get_player_node(local_player_index).position
			if NetworkManager.is_host:
				NetworkManager.process_langitlupa_position(local_player_index, my_pos)
			else:
				NetworkManager.send_langitlupa_position.rpc_id(1, local_player_index, my_pos)

	# Flood visual — every peer computes this locally from round_start_msec, no need to sync.
	$Flood.position.y = _get_flood_y()

	# Authoritative elimination check runs on host only.
	if NetworkManager.is_host:
		_check_flood()
func _physics_process(delta: float) -> void:
	if gameplay_locked:
		print("[LangitLupa] blocked: gameplay_locked")
		return
	if local_player_index == -1 or not alive_players.has(local_player_index):
		print("[LangitLupa] blocked: local_player_index=%s alive=%s" % [local_player_index, alive_players])
		return

	var player := _get_player_node(local_player_index)
	print("[LangitLupa] pos=%s left=%s right=%s jump=%s on_floor=%s" % [
		player.global_position, Input.is_action_pressed("move_left"), Input.is_action_pressed("move_right"),
		Input.is_action_just_pressed("jump"), player.is_on_floor()
	])
	player.velocity.y += GRAVITY * delta

	if player.is_on_floor():
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer -= delta

	var direction := 0.0
	if Input.is_action_pressed("move_left"):
		direction -= 1.0
	if Input.is_action_pressed("move_right"):
		direction += 1.0
	player.velocity.x = direction * MOVE_SPEED

	if Input.is_action_just_pressed("jump") and _coyote_timer > 0.0:
		player.velocity.y = JUMP_VELOCITY
		_coyote_timer = 0.0   # consume it so you can't double-jump off the same window

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
	print("[LangitLupa] Player %d caught by the flood!" % player_idx)

func _compute_final_scores() -> Dictionary:
	var groups: Array = []
	if alive_players.size() == 1:
		groups.append([alive_players[0]])
	var reversed_eliminations: Array = elimination_order.duplicate()
	reversed_eliminations.reverse()
	groups.append_array(reversed_eliminations)
	return BaseMinigame.compute_placement_scores(groups)

func _end_game(scores: Dictionary) -> void:
	round_active = false
	gameplay_locked = true
	_clear_generated_platforms()

	print("[LangitLupa] Round over. Elimination order: %s" % [elimination_order])
	_finish(scores)
