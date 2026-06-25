extends BaseMinigame

# ============================================================
# BatoLata — free-movement version
# ============================================================
# Folder:     res://scenes/minigames/BatoLata/
# Script:     bato_lata.gd
# Scene root: BatoLata.tscn (root node named "BatoLata")
#
# Controls:
#   Player 1 (human): move_up/move_down/move_left/move_right (WASD)
#                      + "p1_shoot" (Space) to aim/lock/throw.
#   Players 2-4: AI-controlled (no LAN input yet — see DEVLOG.md
#   "Mini-game Movement & Input Scope" note for the same reasoning
#   applied in LangitLupa).
#
# Verify this filename matches "BatoLata".to_snake_case() on disk
# before adding "BatoLata" to Constants.MINIGAMES.
# ============================================================

enum PState { IDLE, AIMING }

const HUMAN_INDEX := 0

# --- Arena / world geometry ---
const ARENA_SIZE := Vector2(1000, 600)
const SAFETY_LINE_X := 700.0
const CAN_POS := Vector2(920, 300)
const CAN_RADIUS := 24.0
const PLAYER_RADIUS := 16.0
const SLIPPER_RADIUS := 6.0

const STARTING_POS := [
	Vector2(60, 80),
	Vector2(60, 220),
	Vector2(60, 380),
	Vector2(60, 520),
]

# --- Movement / throwing tuning ---
const PLAYER_SPEED := 180.0
const SLIPPER_SPEED := 520.0
const AIM_MIN_ANGLE := -60.0
const AIM_MAX_ANGLE := 60.0
const AIM_SWEEP_SPEED := 120.0   # degrees / second, left -> right then snaps back
const MAX_SHOTS := 2
const ROUND_TIMEOUT := 60.0

const CAN_HIT_SCORE := 1
const TAG_SCORE := 2
const COLLECT_BONUS := 5

@onready var player_nodes: Array = [$Player1, $Player2, $Player3, $Player4]
@onready var result_label: Label = $ResultLabel

var player_state: Array = []
var shots_remaining: Array = []
var aim_angle: Array = []

var ai_target: Array = []
var ai_decision_timer: Array = []   # cooldown before AI's next aim attempt
var ai_aim_timer: Array = []        # countdown while AI is "holding" the aim

var runner_index := -1
var can_resolved := false
var time_elapsed := 0.0

var slippers: Array = []   # [{pos, vel, owner, visual}]


func start_game(players: Array[int]) -> void:
	participating_players = players
	player_state.resize(4)
	shots_remaining.resize(4)
	aim_angle.resize(4)
	ai_target.resize(4)
	ai_decision_timer.resize(4)
	ai_aim_timer.resize(4)

	for i in players:
		player_state[i] = PState.IDLE
		shots_remaining[i] = MAX_SHOTS
		aim_angle[i] = AIM_MIN_ANGLE
		player_nodes[i].position = STARTING_POS[i]
		player_nodes[i].get_node("Arrow").visible = false
		if i != HUMAN_INDEX:
			ai_target[i] = _random_ai_target(i)
			ai_decision_timer[i] = randf_range(1.0, 3.0)

	result_label.text = "Hit the can!"
	set_process(true)
	set_process_unhandled_input(true)


func _process(delta: float) -> void:
	time_elapsed += delta

	_update_human(delta)
	for i in participating_players:
		if i != HUMAN_INDEX:
			_update_ai(i, delta)

	_update_slippers(delta)

	if runner_index != -1:
		if player_nodes[runner_index].position.distance_to(CAN_POS) <= CAN_RADIUS + PLAYER_RADIUS:
			_end_round_collected()
			return

	if not can_resolved and time_elapsed >= ROUND_TIMEOUT:
		_end_round_timeout()


func _unhandled_input(event: InputEvent) -> void:
	if HUMAN_INDEX in participating_players and event.is_action_pressed("p1_shoot"):
		_press_action(HUMAN_INDEX)


# ---------------------------------------------------------
# Shared aim/shoot logic — used identically by human input
# and the AI decision loop below.
# ---------------------------------------------------------

func _press_action(idx: int) -> void:
	if shots_remaining[idx] <= 0:
		return
	if idx == runner_index:
		return # runner is busy escaping, can't aim

	match player_state[idx]:
		PState.IDLE:
			player_state[idx] = PState.AIMING
			aim_angle[idx] = AIM_MIN_ANGLE
			player_nodes[idx].get_node("Arrow").rotation_degrees = AIM_MIN_ANGLE
			player_nodes[idx].get_node("Arrow").visible = true
			if idx != HUMAN_INDEX:
				ai_aim_timer[idx] = randf_range(0.4, 1.0)
		PState.AIMING:
			_throw_slipper(idx, player_nodes[idx].get_node("Arrow").rotation_degrees)
			shots_remaining[idx] -= 1
			player_state[idx] = PState.IDLE
			player_nodes[idx].get_node("Arrow").visible = false
			if idx != HUMAN_INDEX:
				ai_decision_timer[idx] = randf_range(2.0, 4.0)


func _sweep_arrow(idx: int, delta: float) -> void:
	aim_angle[idx] += AIM_SWEEP_SPEED * delta
	if aim_angle[idx] > AIM_MAX_ANGLE:
		aim_angle[idx] = AIM_MIN_ANGLE # snap back to the left and sweep again
	player_nodes[idx].get_node("Arrow").rotation_degrees = aim_angle[idx]


# ---------------------------------------------------------
# Human (Player 1)
# ---------------------------------------------------------

func _update_human(delta: float) -> void:
	if HUMAN_INDEX not in participating_players:
		return

	if player_state[HUMAN_INDEX] == PState.AIMING:
		_sweep_arrow(HUMAN_INDEX, delta)
		return

	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1
	if Input.is_action_pressed("move_up"):
		dir.y -= 1
	if Input.is_action_pressed("move_down"):
		dir.y += 1

	if dir != Vector2.ZERO:
		dir = dir.normalized()
		player_nodes[HUMAN_INDEX].position += dir * PLAYER_SPEED * delta
		_clamp_player(HUMAN_INDEX)


# ---------------------------------------------------------
# AI (Players 2-4) — simple wander + periodic aim attempts.
# Temporary stub, same reasoning as LangitLupa's wandering AI:
# no LAN input yet, so non-local players need *something* driving
# them so the can/tag logic can be tested standalone.
# ---------------------------------------------------------

func _update_ai(idx: int, delta: float) -> void:
	if player_state[idx] == PState.AIMING:
		_sweep_arrow(idx, delta)
		ai_aim_timer[idx] -= delta
		if ai_aim_timer[idx] <= 0.0:
			_press_action(idx) # AI "presses again" to lock in and throw
		return

	# Wander toward current target.
	var node: Node2D = player_nodes[idx]
	var to_target: Vector2 = ai_target[idx] - node.position
	if to_target.length() < 10.0:
		ai_target[idx] = _random_ai_target(idx)
	else:
		node.position += to_target.normalized() * PLAYER_SPEED * delta
		_clamp_player(idx)

	# Periodically decide to take a shot.
	ai_decision_timer[idx] -= delta
	if ai_decision_timer[idx] <= 0.0 and shots_remaining[idx] > 0 and idx != runner_index:
		var should_shoot := false
		if runner_index == -1 and not can_resolved:
			should_shoot = true # going for the can
		elif runner_index != -1 and runner_index != idx:
			should_shoot = true # going for the tag
		if should_shoot:
			_press_action(idx)
		else:
			ai_decision_timer[idx] = randf_range(1.0, 2.0)


func _random_ai_target(idx: int) -> Vector2:
	if idx == runner_index:
		return CAN_POS
	var max_x: float = SAFETY_LINE_X - PLAYER_RADIUS
	return Vector2(
		randf_range(PLAYER_RADIUS, max_x),
		randf_range(PLAYER_RADIUS, ARENA_SIZE.y - PLAYER_RADIUS)
	)


func _clamp_player(idx: int) -> void:
	var node: Node2D = player_nodes[idx]
	node.position.x = clamp(node.position.x, PLAYER_RADIUS, ARENA_SIZE.x - PLAYER_RADIUS)
	node.position.y = clamp(node.position.y, PLAYER_RADIUS, ARENA_SIZE.y - PLAYER_RADIUS)
	if idx != runner_index:
		node.position.x = min(node.position.x, SAFETY_LINE_X - PLAYER_RADIUS)


# ---------------------------------------------------------
# Slippers — real projectiles, real collision.
# ---------------------------------------------------------

func _throw_slipper(owner_idx: int, angle_degrees: float) -> void:
	var dir := Vector2(cos(deg_to_rad(angle_degrees)), sin(deg_to_rad(angle_degrees)))
	var start_pos: Vector2 = player_nodes[owner_idx].position

	var visual := ColorRect.new()
	visual.size = Vector2(SLIPPER_RADIUS * 2.0, SLIPPER_RADIUS * 2.0)
	visual.color = Color(0.85, 0.8, 0.7, 1.0)
	visual.position = start_pos - visual.size / 2.0
	add_child(visual)

	slippers.append({
		"pos": start_pos,
		"vel": dir * SLIPPER_SPEED,
		"owner": owner_idx,
		"visual": visual,
	})


func _update_slippers(delta: float) -> void:
	var to_remove: Array = []

	for s in slippers:
		s.pos += s.vel * delta
		s.visual.position = s.pos - s.visual.size / 2.0

		if s.pos.x < -50.0 or s.pos.x > ARENA_SIZE.x + 50.0 \
				or s.pos.y < -50.0 or s.pos.y > ARENA_SIZE.y + 50.0:
			to_remove.append(s)
			continue

		if not can_resolved and s.pos.distance_to(CAN_POS) <= CAN_RADIUS + SLIPPER_RADIUS:
			_resolve_can_hit(s.owner)
			to_remove.append(s)
			continue

		var hit_someone := false
		for j in participating_players:
			if j == s.owner:
				continue
			# Rule: a player can only be hit once they're beyond the safety line.
			if player_nodes[j].position.x <= SAFETY_LINE_X:
				continue
			if s.pos.distance_to(player_nodes[j].position) <= PLAYER_RADIUS + SLIPPER_RADIUS:
				_resolve_tag(s.owner, j)
				to_remove.append(s)
				hit_someone = true
				break
		if hit_someone:
			continue

	for s in to_remove:
		s.visual.queue_free()
		slippers.erase(s)


func _resolve_can_hit(owner_idx: int) -> void:
	can_resolved = true
	runner_index = owner_idx
	if owner_idx != HUMAN_INDEX:
		ai_target[owner_idx] = CAN_POS
	GameManager.add_score(owner_idx, CAN_HIT_SCORE)
	result_label.text = "Player %d hit the can — RUN!" % (owner_idx + 1)


func _resolve_tag(owner_idx: int, target_idx: int) -> void:
	GameManager.add_score(owner_idx, TAG_SCORE)
	result_label.text = "Player %d got tagged out!" % (target_idx + 1)
	player_nodes[target_idx].position = STARTING_POS[target_idx]
	if target_idx != HUMAN_INDEX:
		ai_target[target_idx] = _random_ai_target(target_idx)
	runner_index = -1
	can_resolved = false


func _end_round_collected() -> void:
	result_label.text = "Player %d collected the can and wins the round!" % (runner_index + 1)
	GameManager.add_score(runner_index, COLLECT_BONUS)
	var scores := {runner_index: COLLECT_BONUS}
	_cleanup_and_finish(scores)


func _end_round_timeout() -> void:
	result_label.text = "Time's up — nobody collected the can."
	_cleanup_and_finish({})


func _cleanup_and_finish(scores: Dictionary) -> void:
	set_process(false)
	set_process_unhandled_input(false)
	for s in slippers:
		s.visual.queue_free()
	slippers.clear()
	_finish(scores)
