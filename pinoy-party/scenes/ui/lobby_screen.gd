extends Control

const LOBBY_FONT := preload("res://assets/fonts/GrapeSoda.ttf")
const PLAYER_ICONS: Array[Texture2D] = [
	preload("res://assets/board_assets/LeaderBoard/player_icons1.png"),
	preload("res://assets/board_assets/LeaderBoard/player_icons2.png"),
	preload("res://assets/board_assets/LeaderBoard/player_icons3.png"),
	preload("res://assets/board_assets/LeaderBoard/player_icons4.png")
]
const TYPING_SFX := preload("res://assets/sfx/type_sfx.mp3")
const BUTTON_CLICK_SFX := preload("res://assets/sfx/button_click_sfx.mp3")
const HOVER_SFX := preload("res://assets/sfx/hover_sfx.mp3")
const PLAYER_NAME_COLOR := Color(0.12, 0.20, 0.34)

var host_join_panel: VBoxContainer
var lobby_container: Control
var lobby_panel: Control
var player_cards: HBoxContainer
var code_label: Label
var start_button: TextureButton
var status_label: Label
var join_status_label: Label
var typing_sfx: AudioStreamPlayer
var button_click_sfx: AudioStreamPlayer
var hover_sfx: AudioStreamPlayer

func _ready() -> void:
	host_join_panel = _find_required_node("HostJoinPanel", ["UIContainer/UIControl/HostJoinPanel"]) as VBoxContainer
	lobby_container = _find_required_node("LobbyContainer", ["LobbyContainer", "CenterContainer"]) as Control
	lobby_panel = _find_required_node("LobbyPanel", [
		"LobbyContainer/Control/VBoxContainer/LobbyPanel",
		"CenterContainer/VBoxContainer/LobbyPanel"
	]) as Control
	player_cards = _find_required_node("PlayerCards", [
		"LobbyContainer/Control/VBoxContainer/LobbyPanel/CenterContainer/PlayerCards",
		"CenterContainer/VBoxContainer/LobbyPanel/CenterContainer/PlayerCards",
		"LobbyPanel/PlayerCards"
	]) as HBoxContainer
	code_label = _find_required_node("CodeLabel", [
		"LobbyContainer/Control/VBoxContainer/LobbyPanel/Control/CodeLabel",
		"LobbyContainer/Control/VBoxContainer/LobbyPanel/CodeLabel",
		"CenterContainer/VBoxContainer/LobbyPanel/CodeLabel",
		"LobbyPanel/CodeLabel"
	]) as Label
	start_button = _find_required_node("StartButton", [
		"LobbyContainer/Control/VBoxContainer/StartButton",
		"CenterContainer/VBoxContainer/StartButton",
		"LobbyPanel/StartButton"
	]) as TextureButton
	status_label = _find_required_node("StatusLabel", [
		"LobbyContainer/Control/VBoxContainer/StatusLabel",
		"StatusLabel"
	]) as Label
	join_status_label = _find_required_node("JoinStatusLabel", [
		"UIContainer/UIControl/HostJoinPanel/JoinStatusLabel"
	]) as Label

	if host_join_panel == null or lobby_container == null or lobby_panel == null or player_cards == null or code_label == null or start_button == null or status_label == null or join_status_label == null:
		return

	button_click_sfx = _get_or_create_audio_player("ButtonSfx", BUTTON_CLICK_SFX)
	typing_sfx = _get_or_create_audio_player("TypingSfx", TYPING_SFX)
	hover_sfx = _get_or_create_audio_player("HoverSfx", HOVER_SFX)

	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.roster_updated.connect(_on_roster_changed)
	NetworkManager.join_failed.connect(_on_join_failed)
	NetworkManager.host_left.connect(_on_host_left)
	start_button.pressed.connect(_on_start_pressed)
	var host_button := host_join_panel.get_node("HostButton") as BaseButton
	var join_button := host_join_panel.get_node("JoinButton") as BaseButton
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	_connect_hover_sfx(start_button)
	_connect_hover_sfx(host_button)
	_connect_hover_sfx(join_button)
	_connect_typing_sfx(host_join_panel.get_node("NameInput") as LineEdit)
	_connect_typing_sfx(host_join_panel.get_node("JoinIPInput") as LineEdit)
	_connect_typing_sfx(host_join_panel.get_node("JoinCodeInput") as LineEdit)

	if multiplayer.has_multiplayer_peer() and NetworkManager.lobby_code != "":
		if NetworkManager.is_host:
			_on_lobby_created(NetworkManager.lobby_code)
			NetworkManager._start_broadcasting()
		else:
			_on_roster_changed()
	else:
		host_join_panel.visible = true
		lobby_container.visible = false
		lobby_panel.visible = false
		start_button.visible = false
	_show_error("")
	status_label.add_theme_font_override("font", LOBBY_FONT)
	status_label.add_theme_font_size_override("font_size", 24)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	join_status_label.add_theme_font_override("font", LOBBY_FONT)
	join_status_label.add_theme_font_size_override("font_size", 24)
	join_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	NetworkManager.start_listening_for_lobbies()

func _on_host_pressed() -> void:
	_play_button_click_sfx()
	var name_input: LineEdit = host_join_panel.get_node("NameInput")
	var player_name: String = name_input.text.strip_edges()
	if player_name.is_empty():
		_show_error("Please enter your name!")
		return
	NetworkManager.host_lobby(player_name)

func _on_join_pressed() -> void:
	_play_button_click_sfx()
	var join_ip_input: LineEdit = host_join_panel.get_node("JoinIPInput")
	var join_code_input: LineEdit = host_join_panel.get_node("JoinCodeInput")
	var name_input: LineEdit = host_join_panel.get_node("NameInput")

	var typed_ip: String = join_ip_input.text.strip_edges()
	var code: String = join_code_input.text.strip_edges()
	var player_name: String = name_input.text.strip_edges()

	if player_name.is_empty():
		_show_error("Please enter your name!")
		return
	if code.is_empty() and typed_ip.is_empty():
		_show_error("Please enter a Lobby Code!")
		return

	_show_error("Connecting...")
	
	if typed_ip != "":
		NetworkManager.join_lobby(code, typed_ip, player_name)
	else:
		NetworkManager.join_lobby_by_code(code, player_name)

func _on_lobby_created(code: String) -> void:
	host_join_panel.visible = false
	lobby_container.visible = true
	lobby_panel.visible = true
	code_label.text = "Code: %s" % code
	_rebuild_cards()

func _on_roster_changed(_id: int = -1) -> void:
	host_join_panel.visible = false
	lobby_container.visible = true
	lobby_panel.visible = true
	if NetworkManager.lobby_code != "":
		code_label.text = "Code: %s" % NetworkManager.lobby_code
	_rebuild_cards()

func _rebuild_cards() -> void:
	for child in player_cards.get_children():
		child.queue_free()
	var current_index := 0
	for peer_id in NetworkManager.connected_players:
		var player_name: String = NetworkManager.connected_players[peer_id]["name"]
		
		# Pass the current index alongside the name
		var card := _build_card(player_name, current_index)
		player_cards.add_child(card)
		current_index += 1 

	var player_count := NetworkManager.connected_players.size()
	start_button.visible = lobby_container.visible and NetworkManager.is_host
	start_button.disabled = player_count < 2
	
	if NetworkManager.is_host:
		if player_count < 2:
			_show_error("Cannot start game: Waiting for other players...")
		else:
			_show_error("All players ready! You may start.")
	else:
		_show_error("Waiting for Host to start the game...")

func _build_card(player_name: String, player_index: int) -> Control:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(136, 132)
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var icon := TextureRect.new()
	if player_index < PLAYER_ICONS.size():
		icon.texture = PLAYER_ICONS[player_index]
	else:
		icon.texture = PLAYER_ICONS[0]
	icon.custom_minimum_size = Vector2(80, 80)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var label := Label.new()
	label.text = player_name
	label.custom_minimum_size = Vector2(136, 36)
	label.add_theme_font_override("font", LOBBY_FONT)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", PLAYER_NAME_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(icon)
	vbox.add_child(label)
	return vbox

func _on_join_failed(reason: String) -> void:
	_show_error(reason)
	host_join_panel.visible = true
	lobby_container.visible = false
	lobby_panel.visible = false
	start_button.visible = false

func _on_host_left() -> void:
	_show_error("Host disconnected. Lobby closed.")
	host_join_panel.visible = true
	lobby_container.visible = false
	lobby_panel.visible = false
	start_button.visible = false

func _show_error(msg: String) -> void:
	if status_label != null:
		status_label.text = msg
	if join_status_label != null:
		join_status_label.text = msg

func _on_start_pressed() -> void:
	_play_button_click_sfx()
	NetworkManager.start_game()

func _connect_typing_sfx(input: LineEdit) -> void:
	if input == null:
		return
	input.text_changed.connect(_on_input_text_changed.bind(input))

func _on_input_text_changed(_new_text: String, input: LineEdit) -> void:
	if input == null or not input.has_focus():
		return
	_play_typing_sfx()

func _play_typing_sfx() -> void:
	if typing_sfx == null or typing_sfx.stream == null:
		return
	typing_sfx.stop()
	typing_sfx.play()

func _play_button_click_sfx() -> void:
	if button_click_sfx == null or button_click_sfx.stream == null:
		return
	button_click_sfx.stop()
	button_click_sfx.play()

func _play_hover_sfx() -> void:
	if hover_sfx == null or hover_sfx.stream == null:
		return
	hover_sfx.stop()
	hover_sfx.play()

func _connect_hover_sfx(button: BaseButton) -> void:
	if button == null:
		return
	button.mouse_entered.connect(_play_hover_sfx)

func _get_or_create_audio_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var existing := get_node_or_null(player_name) as AudioStreamPlayer
	if existing != null:
		if existing.stream == null:
			existing.stream = stream
		return existing

	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	add_child(player)
	return player

func _find_required_node(node_name: String, paths: Array[String]) -> Node:
	for path in paths:
		var node := get_node_or_null(path)
		if node != null:
			return node

	var found := find_child(node_name, true, false)
	if found != null:
		return found

	push_error("LobbyScreen missing required node: %s" % node_name)
	return null
