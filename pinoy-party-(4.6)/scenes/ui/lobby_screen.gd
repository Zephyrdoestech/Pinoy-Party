extends Control

@onready var host_join_panel := $HostJoinPanel
@onready var lobby_panel := $LobbyPanel
@onready var player_cards := $LobbyPanel/PlayerCards
@onready var code_label := $LobbyPanel/CodeLabel
@onready var start_button := $LobbyPanel/StartButton
@onready var status_label := $StatusLabel

func _ready() -> void:
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.roster_updated.connect(_on_roster_changed)
	NetworkManager.join_failed.connect(_on_join_failed)
	start_button.pressed.connect(_on_start_pressed)
	$HostJoinPanel/HostButton.pressed.connect(_on_host_pressed)
	$HostJoinPanel/JoinButton.pressed.connect(_on_join_pressed)

	host_join_panel.visible = true
	lobby_panel.visible = false
	status_label.text = ""

	NetworkManager.start_listening_for_lobbies()

func _on_host_pressed() -> void:
	NetworkManager.host_lobby($HostJoinPanel/NameInput.text)

func _on_join_pressed() -> void:
	print("_on_join_pressed fired")
	var join_ip_input: LineEdit = $HostJoinPanel/JoinIPInput
	var join_code_input: LineEdit = $HostJoinPanel/JoinCodeInput
	var name_input: LineEdit = $HostJoinPanel/NameInput

	var typed_ip: String = join_ip_input.text.strip_edges()
	var code: String = join_code_input.text
	var player_name: String = name_input.text

	if typed_ip != "":
		NetworkManager.join_lobby(code, typed_ip, player_name)
	else:
		NetworkManager.join_lobby_by_code(code, player_name)

func _on_lobby_created(code: String) -> void:
	host_join_panel.visible = false
	lobby_panel.visible = true
	code_label.text = "Code: %s" % code
	_rebuild_cards()

func _on_roster_changed(_id: int = -1) -> void:
	host_join_panel.visible = false
	lobby_panel.visible = true
	_rebuild_cards()

func _rebuild_cards() -> void:
	for child in player_cards.get_children():
		child.queue_free()
	for peer_id in NetworkManager.connected_players:
		var card := _build_card(NetworkManager.connected_players[peer_id]["name"])
		player_cards.add_child(card)

	var player_count := NetworkManager.connected_players.size()
	start_button.visible = NetworkManager.is_host
	start_button.disabled = player_count < 2

func _build_card(player_name: String) -> Control:
	var vbox := VBoxContainer.new()
	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(96, 96)
	var label := Label.new()
	label.text = player_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(icon)
	vbox.add_child(label)
	return vbox

func _on_join_failed(reason: String) -> void:
	status_label.text = reason
	host_join_panel.visible = true
	lobby_panel.visible = false

func _on_start_pressed() -> void:
	NetworkManager.start_game()
