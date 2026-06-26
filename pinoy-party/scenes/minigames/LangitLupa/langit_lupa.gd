class_name LangitLupa
extends BaseMinigame

const PLAYER_SPEED := 150.0
const TAG_RADIUS := 30.0
const AREA_SIZE := 80.0              # visual width/height of each area (square)
const AREA_RADIUS := AREA_SIZE * 0.5 # detection radius derived from size, not set separately
const AREA_SAFE_DURATION := 4.0
const NUM_AREAS := 6
const ROUND_DURATION := 60.0
const COUNTDOWN_DURATION := 3.0

# TODO: once LAN play is in, this should come from the network session
# (i.e. "which player am I controlling on this device"). Hardcoded for now.
var local_player_index := 0

var areas: Array = []
var it_player: int = -1
var alive_players: Array[int] = []
var tagged_players: Array[int] = []
var round_time := 0.0
var round_active := false
var countdown_time := 0.0
var countdown_active := false

var ai_directions: Dictionary = {}   # idx -> Vector2
var ai_change_timer: Dictionary = {} # idx -> float
const AI_DIRECTION_CHANGE_INTERVAL := 1.5

func start_game(players: Array[int]) -> void:
	participating_players = players
	alive_players = players.duplicate()
	tagged_players.clear()
	round_time = 0.0
	round_active = false
	countdown_time = 0.0
	countdown_active = true
	it_player = players[randi() % players.size()]
	$UI/ItLabel.text = "Player %d is IT!" % (it_player + 1)
	print("[LangitLupa] Player %d is IT." % it_player)
	_spawn_areas()
	_position_players()
	_init_ai(players)

func _spawn_areas() -> void:
	areas.clear()
	for i in NUM_AREAS:
		var pos := Vector2(randf_range(60, 760), randf_range(60, 460))
		areas.append({"pos": pos, "occupied_since": 0.0, "unsafe": false})
		var rect: ColorRect = get_node("Areas/Area%d" % i)
		rect.size = Vector2(AREA_SIZE, AREA_SIZE)
		rect.position = pos - rect.size / 2.0  # center the rect on the logical position
		rect.color = Color.GREEN
		rect.modulate.a = 1.0

func _position_players() -> void:
	for idx in participating_players:
		_get_player_node(idx).position = Vector2(randf_range(100, 700), randf_range(100, 400))
		_get_player_node(idx).color = Color.RED if idx == it_player else Color.BLUE

func _get_player_node(idx: int) -> ColorRect:
	return get_node("Players/Player %d" % (idx + 1))

func _process(delta: float) -> void:
	if countdown_active:
		countdown_time += delta
		var remaining := COUNTDOWN_DURATION - countdown_time
		$UI/TimerLabel.text = "Get ready: %.1f" % max(remaining, 0.0)
		if countdown_time >= COUNTDOWN_DURATION:
			countdown_active = false
			round_active = true
			print("[LangitLupa] Round started.")
		return

	if not round_active:
		return
	round_time += delta
	$UI/TimerLabel.text = "Time: %.1f" % max(ROUND_DURATION - round_time, 0.0)
	if round_time >= ROUND_DURATION:
		_end_game()
		return
	_handle_movement(delta)
	_update_areas(delta)
	_check_tagging()

func _get_local_input_dir() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"): dir.y -= 1
	if Input.is_action_pressed("move_down"): dir.y += 1
	if Input.is_action_pressed("move_left"): dir.x -= 1
	if Input.is_action_pressed("move_right"): dir.x += 1
	return dir

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
	# Local player
	if local_player_index not in tagged_players:
		var node := _get_player_node(local_player_index)
		var dir := _get_local_input_dir()
		if dir != Vector2.ZERO:
			node.position = _apply_move(local_player_index, node.position, dir, delta)

	# AI-controlled players
	for idx in alive_players:
		if idx == local_player_index or idx in tagged_players:
			continue
		ai_change_timer[idx] += delta
		if ai_change_timer[idx] >= AI_DIRECTION_CHANGE_INTERVAL:
			ai_directions[idx] = _random_direction()
			ai_change_timer[idx] = 0.0
		var node := _get_player_node(idx)
		node.position = _apply_move(idx, node.position, ai_directions[idx], delta)
		# bounce off walls so they don't wander off-screen forever
		if node.position.x < 30 or node.position.x > 770:
			ai_directions[idx].x *= -1
		if node.position.y < 30 or node.position.y > 470:
			ai_directions[idx].y *= -1

func _apply_move(idx: int, pos: Vector2, dir: Vector2, delta: float) -> Vector2:
	var new_pos: Vector2 = pos + dir.normalized() * PLAYER_SPEED * delta
	if idx == it_player:
		for area in areas:
			if new_pos.distance_to(area.pos) < AREA_RADIUS:
				return pos  # blocked from elevated areas
	return new_pos

func _update_areas(delta: float) -> void:
	for area in areas:
		if area.unsafe:
			continue
		var occupied := false
		for idx in alive_players:
			if idx == it_player or idx in tagged_players:
				continue
			if _get_player_node(idx).position.distance_to(area.pos) < AREA_RADIUS:
				occupied = true
				break
		if occupied:
			area.occupied_since += delta
			if area.occupied_since >= AREA_SAFE_DURATION:
				area.unsafe = true
		else:
			area.occupied_since = 0.0
	_update_area_visuals()

func _update_area_visuals() -> void:
	for i in areas.size():
		var rect: ColorRect = get_node("Areas/Area%d" % i)
		if areas[i].unsafe:
			rect.color = Color.RED
			rect.modulate.a = 0.5 + 0.5 * sin(round_time * 10.0)
		else:
			rect.color = Color.GREEN
			rect.modulate.a = 1.0

func _is_player_safe(pos: Vector2) -> bool:
	for area in areas:
		if not area.unsafe and pos.distance_to(area.pos) < AREA_RADIUS:
			return true
	return false

func _check_tagging() -> void:
	var it_pos: Vector2 = _get_player_node(it_player).position
	for idx in alive_players:
		if idx == it_player or idx in tagged_players:
			continue
		var node := _get_player_node(idx)
		if _is_player_safe(node.position):
			continue
		if node.position.distance_to(it_pos) < TAG_RADIUS:
			tagged_players.append(idx)
			node.modulate.a = 0.3
			print("[LangitLupa] Player %d tagged!" % idx)

func _end_game() -> void:
	round_active = false
	var scores: Dictionary = {}
	for idx in participating_players:
		if idx == it_player:
			if tagged_players.size() > 0:
				scores[idx] = tagged_players.size() * 2
				GameManager.add_score(idx, scores[idx])
		elif idx not in tagged_players:
			scores[idx] = 2
			GameManager.add_score(idx, 2)
	print("[LangitLupa] Round over. Tagged: %s" % [tagged_players])
	_finish(scores)
