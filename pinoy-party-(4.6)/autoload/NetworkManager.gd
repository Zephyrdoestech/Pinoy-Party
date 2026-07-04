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
	rpc("_on_game_start")

@rpc("authority", "reliable", "call_local")
func _on_game_start() -> void:
	game_starting.emit()
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _generate_code() -> String:
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ"  # no I/O to avoid confusion
	var code := ""
	for i in 5:
		code += CHARS[randi() % CHARS.length()]
	return code
