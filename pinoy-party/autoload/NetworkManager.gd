extends Node

signal lobby_created(code: String)
signal player_joined(peer_id: int, player_name: String)
signal player_left(peer_id: int)
signal join_failed(reason: String)
signal game_starting
signal roster_updated

const PORT := 7777
const MAX_PLAYERS := 4
const DISCOVERY_PORT := 7778

var _discovery_socket: PacketPeerUDP
var _broadcast_timer: Timer
var discovered_lobbies: Dictionary = {}  # code -> {ip: String, last_seen: float}
var lobby_code: String = ""
var is_host: bool = false
var connected_players: Dictionary = {}  # peer_id -> {name: String}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)

func host_lobby(player_name: String) -> void:
	lobby_code = _generate_code()
	is_host = true

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		join_failed.emit("Could not create server")
		return

	multiplayer.multiplayer_peer = peer
	connected_players[1] = {"name": player_name}
	lobby_created.emit(lobby_code)

	_start_broadcasting()

func _start_broadcasting() -> void:
	_discovery_socket = PacketPeerUDP.new()
	_discovery_socket.set_broadcast_enabled(true)

	_broadcast_timer = Timer.new()
	_broadcast_timer.wait_time = 1.0
	_broadcast_timer.timeout.connect(_send_broadcast)
	add_child(_broadcast_timer)
	_broadcast_timer.start()

func _send_broadcast() -> void:
	var msg := "PINOYPARTY|%s" % lobby_code
	_discovery_socket.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	var err := _discovery_socket.put_packet(msg.to_utf8_buffer())
	print("Broadcasting lobby code: ", lobby_code, " err=", err)

func start_listening_for_lobbies() -> void:
	discovered_lobbies.clear()
	_discovery_socket = PacketPeerUDP.new()
	var err := _discovery_socket.bind(DISCOVERY_PORT)
	print("Discovery bind result: ", err)
	set_process(true)

func _process(_delta: float) -> void:
	if _discovery_socket == null or is_host:
		return
	while _discovery_socket.get_available_packet_count() > 0:
		var packet := _discovery_socket.get_packet()
		var sender_ip := _discovery_socket.get_packet_ip()
		var msg := packet.get_string_from_utf8()
		var parts := msg.split("|")
		if parts.size() == 2 and parts[0] == "PINOYPARTY":
			discovered_lobbies[parts[1]] = {"ip": sender_ip, "last_seen": Time.get_ticks_msec()}

func join_lobby_by_code(code: String, player_name: String) -> void:
	code = code.to_upper()
	if not discovered_lobbies.has(code):
		join_failed.emit("No lobby found with that code on this network")
		return
	join_lobby(code, discovered_lobbies[code]["ip"], player_name)

func stop_discovery() -> void:
	set_process(false)
	if _discovery_socket:
		_discovery_socket.close()
	if _broadcast_timer:
		_broadcast_timer.stop()
		_broadcast_timer.queue_free()

func join_lobby(code: String, ip: String, player_name: String) -> void:
	print("join_lobby called: code=", code, " ip=", ip, " name=", player_name)
	lobby_code = code.to_upper()
	is_host = false
	_pending_name = player_name

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	print("create_client result: ", err)
	if err != OK:
		join_failed.emit("Could not reach host")
		return
	multiplayer.multiplayer_peer = peer

var _pending_name: String = ""

func _on_connected_ok() -> void:
	print("Connected to host, registering as: ", _pending_name)
	rpc_id(1, "_register_player", _pending_name, lobby_code)

func _on_connection_failed() -> void:
	print("Connection failed")
	join_failed.emit("Connection failed")

@rpc("any_peer", "reliable")
func _register_player(player_name: String, code: String) -> void:
	print("_register_player called on host: name=", player_name, " code=", code)
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if code.to_upper() != lobby_code:
		rpc_id(sender_id, "_kick", "Wrong lobby code")
		return
	connected_players[sender_id] = {"name": player_name}
	_broadcast_player_list()
	player_joined.emit(sender_id, player_name)

@rpc("authority", "reliable")
func _kick(reason: String) -> void:
	join_failed.emit(reason)
	multiplayer.multiplayer_peer = null

func _broadcast_player_list() -> void:
	rpc("_sync_player_list", connected_players)

@rpc("authority", "reliable", "call_local")
func _sync_player_list(players: Dictionary) -> void:
	connected_players = players
	roster_updated.emit()

func _on_peer_connected(id: int) -> void:
	if not is_host:
		stop_discovery()

func _on_peer_disconnected(id: int) -> void:
	if connected_players.has(id):
		connected_players.erase(id)
		if is_host:
			_broadcast_player_list()
		player_left.emit(id)

func start_game() -> void:
	if not is_host:
		return
	stop_discovery()
	_build_player_index_map()
	rpc("_on_game_start")

@rpc("authority", "reliable", "call_local")
func _on_game_start() -> void:
	game_starting.emit()
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

# --- Player index <-> peer id mapping ---
# Built once on the host when the match starts, then broadcast to everyone.
# Index order = ascending peer id, so it's deterministic without extra negotiation.
var player_index_to_peer: Dictionary = {}  # int -> peer_id
var peer_to_player_index: Dictionary = {}  # peer_id -> int

func _build_player_index_map() -> void:
	player_index_to_peer.clear()
	peer_to_player_index.clear()
	var sorted_peers := connected_players.keys()
	sorted_peers.sort()
	for i in sorted_peers.size():
		player_index_to_peer[i] = sorted_peers[i]
		peer_to_player_index[sorted_peers[i]] = i
	rpc("_sync_player_index_map", player_index_to_peer, sorted_peers.size())

@rpc("authority", "reliable", "call_local")
func _sync_player_index_map(mapping: Dictionary, player_count: int) -> void:
	player_index_to_peer = mapping
	peer_to_player_index.clear()
	for idx in mapping:
		peer_to_player_index[mapping[idx]] = idx
	GameManager.active_player_count = player_count
	GameManager._setup_players()

func get_my_player_index() -> int:
	var my_peer := multiplayer.get_unique_id()
	if peer_to_player_index.has(my_peer):
		return peer_to_player_index[my_peer]
	return -1

# --- Dice roll sync ---
# Any client can request a roll; only the host actually generates the result
# and broadcasts it, so every peer sees the identical outcome.
@rpc("any_peer", "reliable")
func request_roll() -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	print("request_roll received, raw sender_id=", sender_id)
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	_process_roll_request(sender_id)

func _process_roll_request(sender_id: int) -> void:
	var sender_player_idx: int = peer_to_player_index.get(sender_id, -1)
	print("Resolved sender_id=", sender_id, " to player_idx=", sender_player_idx, " (current turn=", GameManager.current_player_index, ")")
	if sender_player_idx != GameManager.current_player_index:
		print("Rejected roll — not this peer's turn")
		return
	var result := randi_range(1, Constants.DICE_FACES)
	print("Rolled: ", result, " — broadcasting to all peers")
	rpc("_apply_roll_result", result)

@rpc("authority", "reliable", "call_local")
func _apply_roll_result(result: int) -> void:
	print("_apply_roll_result received: ", result)
	GameManager.on_dice_rolled(result)

# --- Minigame launch sync ---
# Only the host picks the random minigame ID (so all clients agree), then
# broadcasts the choice. Every peer (including the host, via call_local)
# loads the scene from this single shared call instead of each client
# independently calling Utils.random_minigame()/SceneLoader.go_to_minigame().
func start_minigame_synced(participating_players: Array[int]) -> void:
	if not is_host:
		return
	var minigame_id: String = Utils.random_minigame()
	rpc("_launch_minigame", minigame_id, participating_players)

@rpc("authority", "reliable", "call_local")
func _launch_minigame(minigame_id: String, participating_players: Array) -> void:
	print("Launching synced minigame: ", minigame_id)
	EventBus.minigame_started.emit(minigame_id)
	SceneLoader.go_to_minigame(minigame_id, participating_players)

# --- SackRace hop sync ---
# Same shape as dice rolls: a client requests a hop for the player it
# controls, the host validates it, then broadcasts so every peer's copy of
# the minigame advances that player's progress identically and at the same
# moment. Host calls process_sack_race_hop() directly (self-targeted RPCs
# aren't allowed — see the dice roll gotcha), clients go through the RPC.
@rpc("any_peer", "reliable")
func request_sack_race_hop(player_idx: int) -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	var sender_player_idx: int = peer_to_player_index.get(sender_id, -1)
	if sender_player_idx != player_idx:
		return  # client tried to hop for a player it doesn't control — ignore
	process_sack_race_hop(player_idx)

func process_sack_race_hop(player_idx: int) -> void:
	rpc("_apply_sack_race_hop", player_idx)

@rpc("authority", "reliable", "call_local")
func _apply_sack_race_hop(player_idx: int) -> void:
	var scene := get_tree().current_scene
	if scene is SackRace:
		scene.apply_hop(player_idx)

# --- LuksongBaka sync ---
@rpc("any_peer", "reliable")
func request_luksong_jump(player_idx: int, client_marker_t: float) -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	if peer_to_player_index.get(sender_id, -1) != player_idx:
		return  # client tried to jump for a player it doesn't control
	process_luksong_jump(player_idx, client_marker_t)

func process_luksong_jump(player_idx: int, client_marker_t: float) -> void:
	var scene := get_tree().current_scene
	if not scene is LuksongBaka:
		return
	# Host evaluates using its own marker_t, not the client's, so the
	# in_zone decision is always authoritative — client_marker_t is only
	# used as a fallback if the host scene somehow has no marker state.
	var host_marker_t: float = scene.marker_t
	var zone_start: float = scene.zone_start
	var zone_width: float = scene.zone_width
	var in_zone: bool = host_marker_t >= zone_start and host_marker_t <= (zone_start + zone_width)
	rpc("_apply_luksong_jump", player_idx, in_zone)

@rpc("authority", "reliable", "call_local")
func _apply_luksong_jump(player_idx: int, in_zone: bool) -> void:
	var scene := get_tree().current_scene
	if scene is LuksongBaka:
		scene.apply_jump_result(player_idx, in_zone)

@rpc("authority", "reliable", "call_local")
func sync_luksong_round(zone_start: float) -> void:
	var scene := get_tree().current_scene
	if scene is LuksongBaka:
		scene._begin_round(zone_start)

@rpc("authority", "reliable", "call_local")
func sync_luksong_round_end(auto_eliminated: Array) -> void:
	var scene := get_tree().current_scene
	if scene is LuksongBaka:
		scene.apply_round_end(auto_eliminated)

# --- LangitLupa sync ---

# Host broadcasts it_player and area positions once at match start.
@rpc("authority", "reliable", "call_local")
func sync_langitlupa_start(it_player: int, area_positions: Array) -> void:
	var scene := get_tree().current_scene
	if scene is LangitLupa:
		scene.apply_langitlupa_start(it_player, area_positions)

# Client sends its position to host each sync tick.
# Host calls process_langitlupa_position() directly (avoids self-RPC throw).
@rpc("any_peer", "unreliable")  # unreliable is fine — positions update at 20Hz anyway
func send_langitlupa_position(player_idx: int, pos: Vector2) -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if peer_to_player_index.get(sender_id, -1) != player_idx:
		return  # client tried to move a player it doesn't control
	process_langitlupa_position(player_idx, pos)

# Host receives a position update and broadcasts it to all peers.
func process_langitlupa_position(player_idx: int, pos: Vector2) -> void:
	rpc("_apply_langitlupa_position", player_idx, pos)

@rpc("authority", "unreliable", "call_local")
func _apply_langitlupa_position(player_idx: int, pos: Vector2) -> void:
	var scene := get_tree().current_scene
	if scene is LangitLupa:
		# Don't overwrite local player's position — they own it locally
		if player_idx != scene.local_player_index:
			scene._get_player_node(player_idx).position = pos

# Host detected a tag — broadcast to all peers.
@rpc("authority", "reliable", "call_local")
func sync_langitlupa_tag(player_idx: int) -> void:
	var scene := get_tree().current_scene
	if scene is LangitLupa:
		scene.apply_tag(player_idx)

# Host detected an area going unsafe — broadcast to all peers.
@rpc("authority", "reliable", "call_local")
func sync_langitlupa_area_unsafe(area_idx: int) -> void:
	var scene := get_tree().current_scene
	if scene is LangitLupa:
		scene.apply_area_unsafe(area_idx)

# Host decided the round is over — broadcast to all peers.
@rpc("authority", "reliable", "call_local")
func sync_langitlupa_end() -> void:
	var scene := get_tree().current_scene
	if scene is LangitLupa:
		scene.apply_end()

func _generate_code() -> String:
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ"  # no I/O to avoid confusion
	var code := ""
	for i in 5:
		code += CHARS[randi() % CHARS.length()]
	return code
