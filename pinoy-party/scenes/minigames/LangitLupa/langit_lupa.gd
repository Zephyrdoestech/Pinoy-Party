class_name LangitLupa
extends BaseMinigame

const PLAYER_SPEED := 150.0
const TAG_RADIUS := 30.0
const AREA_SIZE := 80.0              # visual width/height of each area (square) — detection now matches this exactly, see _point_in_area()
const AREA_SAFE_DURATION := 4.0
const AREA_FLASH_DURATION := 1.0     # how long an area flashes red before vanishing for good
const NUM_AREAS := 6
const ROUND_DURATION := 60.0
const SPAWN_CENTER := Vector2(400, 250)
const SPAWN_OFFSETS := [Vector2(-40, -40), Vector2(40, -40), Vector2(-40, 40), Vector2(40, 40)]

# Set from NetworkManager.get_my_player_index() at start_game() — replaces
# the old hardcoded 0, which assumed the host was always Player 0.
var local_player_index := -1

var areas: Array = []
var it_player: int = -1
var alive_players: Array[int] = []
var tagged_players: Array[int] = []
var round_time := 0.0
var round_active := false

# Position sync — each client broadcasts their position at SYNC_HZ rate.
# Host collects all positions and rebroadcasts to everyone.
const POSITION_SYNC_HZ := 20.0
var _position_sync_timer := 0.0

var ai_directions: Dictionary = {}   # idx -> Vector2
var ai_change_timer: Dictionary = {} # idx -> float
const AI_DIRECTION_CHANGE_INTERVAL := 1.5

# --- Dash mechanic ---
const DASH_SPEED_MULTIPLIER := 3.0
const DASH_DURATION := 0.15   # seconds the speed boost lasts
const DASH_COOLDOWN := 5.0    # seconds before that player can dash again
const AI_DASH_CHANCE := 0.3   # chance an AI dashes whenever it picks a new direction

var dash_cooldown_remaining: Dictionary = {} # idx -> float
var dash_time_remaining: Dictionary = {}     # idx -> float, >0 while a dash burst is active
var dash_rings: Dictionary = {}              # idx -> Node2D (radial cooldown indicator)

# A tiny custom-drawn Node2D for the radial dash-cooldown indicator, built at
# runtime so no new scene/script file is needed. Draws a shrinking wedge —
# full circle = just dashed, nothing drawn = ready to dash again.
const _DASH_RING_SOURCE := """
extends Node2D

var progress := 0.0
var ring_radius := 22.0
var ring_color := Color(1, 1, 1, 0.9)

func _draw() -> void:
	if progress <= 0.0:
		return
	var start_angle := -PI / 2.0
	var end_angle := start_angle + TAU * progress
	draw_arc(Vector2.ZERO, ring_radius, start_angle, end_angle, 32, ring_color, 3.0, true)

func set_progress(p: float) -> void:
	progress = clamp(p, 0.0, 1.0)
	queue_redraw()
"""

func start_game(players: Array[int]) -> void:
	super.start_game(players)
	local_player_index = NetworkManager.get_my_player_index()
	alive_players = players.duplicate()
	tagged_players.clear()
	round_time = 0.0
	round_active = false
	_position_players()
	for idx in players:
		dash_cooldown_remaining[idx] = 0.0
		dash_time_remaining[idx] = 0.0
		_create_dash_ring(idx)
	if NetworkManager.is_host:
		var picked_it: int = players[randi() % players.size()]
		var area_positions: Array = _generate_area_positions()
		NetworkManager.sync_langitlupa_start.rpc(picked_it, area_positions)

## Generates NUM_AREAS spawn positions avoiding player spawn points.
## Only called on the host — results are broadcast via sync_langitlupa_start.
func _generate_area_positions() -> Array:
	var positions: Array = []
	for i in NUM_AREAS:
		positions.append(_find_area_spawn_avoiding_players())
	return positions

## Called on every peer (including host, via call_local) once the host has
## chosen it_player and area positions. Finishes setting up the scene.
func apply_langitlupa_start(picked_it: int, area_positions: Array) -> void:
	it_player = picked_it
	$UI/ItLabel.text = "Player %d is IT!" % (it_player + 1)
	print("[LangitLupa] Player %d is IT." % it_player)
	_show_it_arrow(it_player)
	_spawn_areas_at(area_positions)
	_init_ai(participating_players)
	await run_intro("Player %d is IT!" % (it_player + 1))


## Adds a red downward arrow above the IT player's node so they're clearly
## identifiable without relying on color. Built at runtime — no scene edits needed.
func _show_it_arrow(idx: int) -> void:
	var node := _get_player_node(idx)
	# Remove any existing arrow first (safety in case this is called again)
	var existing := node.get_node_or_null("ItArrow")
	if existing:
		existing.queue_free()
	var arrow := Label.new()
	arrow.name = "ItArrow"
	arrow.text = "▼"
	arrow.add_theme_color_override("font_color", Color.RED)
	arrow.add_theme_font_size_override("font_size", 22)
	# Center the arrow above the player node (ColorRect is AREA_SIZE×AREA_SIZE)
	arrow.position = Vector2(-2, -28)
	node.add_child(arrow)

## Players always spawn clustered around the arena center, far enough apart
## (80px, well above TAG_RADIUS) that nobody starts pre-tagged. Areas are
## spawned afterward and dodge these fixed spots — see _spawn_areas().
func _position_players() -> void:
	for i in participating_players.size():
		var idx: int = participating_players[i]
		var node := _get_player_node(idx)
		var offset: Vector2 = SPAWN_OFFSETS[i % SPAWN_OFFSETS.size()]
		node.position = SPAWN_CENTER + offset
		node.color = Color.BLUE  # all players same color — IT is shown via arrow instead

## Places areas at the positions chosen by the host and broadcast via RPC.
## Replaces the old _spawn_areas() which ran randf_range() independently per client.
func _spawn_areas_at(area_positions: Array) -> void:
	areas.clear()
	for i in area_positions.size():
		var pos: Vector2 = area_positions[i]
		areas.append({"pos": pos, "occupied_since": 0.0, "unsafe": false, "unsafe_since": -1.0})
		var rect: ColorRect = get_node("Areas/Area%d" % i)
		rect.size = Vector2(AREA_SIZE, AREA_SIZE)
		rect.position = pos - rect.size / 2.0
		rect.color = Color.GREEN
		rect.modulate.a = 1.0
		rect.visible = true

## Rerolls a random area position (up to 30 attempts) until it isn't on top
## of any player's spawn point — fixes areas spawning directly on a player.
func _find_area_spawn_avoiding_players() -> Vector2:
	var pos := Vector2.ZERO
	for attempt in 30:
		pos = Vector2(randf_range(60, 760), randf_range(60, 460))
		var clear := true
		for idx in participating_players:
			if pos.distance_to(_get_player_node(idx).position) < AREA_SIZE / 2.0 + 30.0:
				clear = false
				break
		if clear:
			return pos
	return pos # fallback after 30 attempts — better than an infinite loop

## True if `point` falls within the area's actual square bounds — matches
## the visual ColorRect exactly, rather than the old circular approximation
## that left the square's corners undetected.
func _point_in_area(point: Vector2, area: Dictionary, margin: float = 0.0) -> bool:
	var half: float = AREA_SIZE / 2.0 + margin
	return absf(point.x - area.pos.x) < half and absf(point.y - area.pos.y) < half

func _get_player_node(idx: int) -> ColorRect:
	return get_node("Players/Player %d" % (idx + 1))

func _process(delta: float) -> void:
	if gameplay_locked:
		return

	if not round_active:
		round_active = true
		print("[LangitLupa] Round started.")

	round_time += delta
	$UI/TimerLabel.text = "Time: %.1f" % max(ROUND_DURATION - round_time, 0.0)

	_update_dash_timers(delta)
	_handle_movement(delta)
	_update_area_visuals()

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

	# Authoritative game logic runs on host only — results broadcast to all peers.
	if NetworkManager.is_host:
		if round_time >= ROUND_DURATION:
			NetworkManager.sync_langitlupa_end.rpc()
			return
		_update_areas(delta)
		_check_tagging()

func _get_local_input_dir() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"): dir.y -= 1
	if Input.is_action_pressed("move_down"): dir.y += 1
	if Input.is_action_pressed("move_left"): dir.x -= 1
	if Input.is_action_pressed("move_right"): dir.x += 1
	return dir

func _unhandled_input(event: InputEvent) -> void:
	if gameplay_locked:
		return
	if local_player_index in participating_players and event.is_action_pressed("dash"):
		_try_dash(local_player_index)

## Starts a dash burst for `idx` if they're not tagged out and their
## cooldown has fully elapsed. Direction comes from whatever they're
## currently moving in — applied inside _apply_move via the speed multiplier.
func _try_dash(idx: int) -> void:
	if idx in tagged_players:
		return
	if dash_cooldown_remaining.get(idx, 0.0) > 0.0:
		return
	dash_time_remaining[idx] = DASH_DURATION
	dash_cooldown_remaining[idx] = DASH_COOLDOWN

## Builds and attaches a radial cooldown indicator as a child of the given
## player's node — follows them automatically since it's a local-space child.
func _create_dash_ring(idx: int) -> void:
	var ring := Node2D.new()
	var script := GDScript.new()
	script.source_code = _DASH_RING_SOURCE
	script.reload()
	ring.set_script(script)
	_get_player_node(idx).add_child(ring)
	dash_rings[idx] = ring

func _update_dash_timers(delta: float) -> void:
	for idx in participating_players:
		if dash_cooldown_remaining.get(idx, 0.0) > 0.0:
			dash_cooldown_remaining[idx] = max(0.0, dash_cooldown_remaining[idx] - delta)
		if dash_time_remaining.get(idx, 0.0) > 0.0:
			dash_time_remaining[idx] = max(0.0, dash_time_remaining[idx] - delta)
		if dash_rings.has(idx):
			var ratio: float = dash_cooldown_remaining.get(idx, 0.0) / DASH_COOLDOWN
			dash_rings[idx].set_progress(ratio)

func _init_ai(players: Array[int]) -> void:
	ai_directions.clear()
	ai_change_timer.clear()
	for idx in players:
		if idx == local_player_index:
			continue
		ai_directions[idx] = _random_direction()
		ai_change_timer[idx] = 0.0

func _random_direction() -> Vector2:
	var dir := Vector2(randf_range(-1, 1), randf_range(-1, 1))
	return dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT

func _handle_movement(delta: float) -> void:
	# Local player — always move from keyboard input
	if local_player_index != -1 and local_player_index not in tagged_players:
		var node := _get_player_node(local_player_index)
		var dir := _get_local_input_dir()
		if dir != Vector2.ZERO:
			node.position = _apply_move(local_player_index, node.position, dir, delta)

	# AI players — only host simulates them, and only for player indices that
	# have no real LAN peer assigned (i.e. not in NetworkManager.player_index_to_peer).
	if not NetworkManager.is_host:
		return
	for idx in alive_players:
		if idx == local_player_index or idx in tagged_players:
			continue
		if NetworkManager.player_index_to_peer.has(idx):
			continue  # this player is controlled by a real LAN peer — don't AI them
		ai_change_timer[idx] += delta
		if ai_change_timer[idx] >= AI_DIRECTION_CHANGE_INTERVAL:
			ai_directions[idx] = _random_direction()
			ai_change_timer[idx] = 0.0
			if dash_cooldown_remaining.get(idx, 0.0) <= 0.0 and randf() < AI_DASH_CHANCE:
				_try_dash(idx)
		var node := _get_player_node(idx)
		node.position = _apply_move(idx, node.position, ai_directions[idx], delta)
		if node.position.x < 30 or node.position.x > 770:
			ai_directions[idx].x *= -1
		if node.position.y < 30 or node.position.y > 470:
			ai_directions[idx].y *= -1

func _apply_move(idx: int, pos: Vector2, dir: Vector2, delta: float) -> Vector2:
	var speed := PLAYER_SPEED
	if dash_time_remaining.get(idx, 0.0) > 0.0:
		speed *= DASH_SPEED_MULTIPLIER
	var new_pos: Vector2 = pos + dir.normalized() * speed * delta
	if idx == it_player:
		for area in areas:
			if not area.unsafe and _point_in_area(new_pos, area):
				return pos  # blocked from elevated (still-safe) areas
	return new_pos

func _update_areas(delta: float) -> void:
	# Only called on host (see _process). Broadcasts area state changes.
	for i in areas.size():
		var area: Dictionary = areas[i]
		if area.unsafe:
			continue
		var occupied := false
		for idx in alive_players:
			if idx == it_player or idx in tagged_players:
				continue
			if _point_in_area(_get_player_node(idx).position, area):
				occupied = true
				break
		if occupied:
			area.occupied_since += delta
			if area.occupied_since >= AREA_SAFE_DURATION:
				NetworkManager.sync_langitlupa_area_unsafe.rpc(i)
		else:
			area.occupied_since = 0.0

## Called on every peer by NetworkManager when an area becomes permanently unsafe.
func apply_area_unsafe(area_idx: int) -> void:
	if area_idx >= areas.size():
		return
	areas[area_idx].unsafe = true
	areas[area_idx].unsafe_since = round_time

func _update_area_visuals() -> void:
	for i in areas.size():
		var rect: ColorRect = get_node("Areas/Area%d" % i)
		var area: Dictionary = areas[i]
		if area.unsafe:
			var elapsed: float = round_time - area.unsafe_since
			if elapsed < AREA_FLASH_DURATION:
				rect.visible = true
				rect.color = Color.RED
				rect.modulate.a = 0.5 + 0.5 * sin(round_time * 10.0)
			else:
				rect.visible = false
		else:
			rect.visible = true
			rect.color = Color.GREEN
			rect.modulate.a = 1.0

func _is_player_safe(pos: Vector2) -> bool:
	for area in areas:
		if not area.unsafe and _point_in_area(pos, area):
			return true
	return false

func _check_tagging() -> void:
	# Only called on host (see _process). Broadcasts tag events to all peers.
	var it_pos: Vector2 = _get_player_node(it_player).position
	for idx in alive_players:
		if idx == it_player or idx in tagged_players:
			continue
		var node := _get_player_node(idx)
		if _is_player_safe(node.position):
			continue
		if node.position.distance_to(it_pos) < TAG_RADIUS:
			NetworkManager.sync_langitlupa_tag.rpc(idx)

	if tagged_players.size() >= alive_players.size() - 1:
		print("[LangitLupa] All players tagged — ending round early.")
		NetworkManager.sync_langitlupa_end.rpc()

## Called on every peer by NetworkManager when a tag event is broadcast.
func apply_tag(player_idx: int) -> void:
	if player_idx in tagged_players:
		return  # already tagged — RPC may arrive more than once before host re-checks
	tagged_players.append(player_idx)
	_get_player_node(player_idx).modulate.a = 0.3
	print("[LangitLupa] Player %d tagged!" % player_idx)

## Called on every peer by NetworkManager.sync_langitlupa_end RPC.
func apply_end() -> void:
	if gameplay_locked:
		return  # already ended — RPC may arrive more than once
	_end_game()

func _end_game() -> void:
	round_active = false
	gameplay_locked = true  # stop _process from re-entering and re-triggering this every frame

	# Per design: IT scores 1 point per tagged player. Each surviving
	# non-IT player scores 1 point per surviving non-IT player (including
	# themselves). Tagged players score 0 — they simply get no entry below.
	var total_others: int = alive_players.size() - 1  # everyone except IT
	var tagged_count: int = tagged_players.size()
	var survivor_count: int = total_others - tagged_count

	var scores: Dictionary = {}
	scores[it_player] = tagged_count
	for idx in alive_players:
		if idx == it_player or idx in tagged_players:
			continue
		scores[idx] = survivor_count

	print("[LangitLupa] Round over. Tagged: %s" % [tagged_players])
	_finish(scores)
