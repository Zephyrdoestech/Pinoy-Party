extends Node2D

@export var player_token_scene: PackedScene = preload("res://scenes/player/PlayerToken.tscn")

@onready var board: Node2D = $Board
@onready var dice: Node2D = $Dice
@onready var roll_button: TextureButton = $UI/RollButton
@onready var state_machine: StateMachine = $StateMachine

var tokens: Array[Node2D] = []

# ---------------------------------------------------------------------------
# Board character spritesheets - one per player (0-indexed).
# Path pattern: res://assets/characters/board_characs/charac{N}/charac{N}_walkFront.PNG
# Sheets are 4096x1024px, 4 frames horizontal (hframes=4), imported as
# CompressedTexture2D. player_token.gd slices them into AtlasTexture frames.
# ---------------------------------------------------------------------------
const CHARACTER_SHEETS: Array[String] = [
	"res://assets/characters/board_characs/charac1/charac1_walkFront.PNG",  # Player 1
	"res://assets/characters/board_characs/charac2/charac2_walkFront.PNG",  # Player 2
	"res://assets/characters/board_characs/charac3/charac3_walkFront.PNG",  # Player 3
	"res://assets/characters/board_characs/charac4/charac4_walkFront.PNG",  # Player 4
]

func _ready() -> void:
	GameManager.board_ref = board
	_spawn_tokens()
	roll_button.disabled = true
	roll_button.pressed.connect(_on_roll_pressed)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.dice_rolled.connect(_on_dice_rolled)
	EventBus.game_over.connect(_on_game_over)
	EventBus.player_moved.connect(_on_player_moved)
	NetworkManager.host_left.connect(_on_match_ended.bind("Host disconnected."))
	NetworkManager.player_left_mid_match.connect(_on_player_left_mid_match)
	call_deferred(&"_update_roll_button")
	# StateMachine auto-starts itself via call_deferred in its own _ready().

func _spawn_tokens() -> void:
	for i in GameManager.active_player_count:
		var token: Node2D = player_token_scene.instantiate()
		add_child(token)

		# Load the spritesheet for this player and pass it into setup().
		# All 4 sheets are confirmed present; load() will assert if a path
		# is wrong, which is the desired loud-failure behaviour during dev.
		var sheet: Texture2D = load(CHARACTER_SHEETS[i])
		token.setup(i, board, sheet)
		token.movement_finished.connect(_on_token_movement_finished)
		tokens.append(token)

func _on_token_movement_finished(player_index: int) -> void:
	EventBus.movement_finished.emit(player_index)

func _on_roll_pressed() -> void:
	if roll_button.disabled:
		return
	# Guard lives in State_WaitingForDice - stray clicks while in another
	# state are harmless (dice.roll() just won't have a listener yet).
	dice.roll()
	_update_roll_button()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not roll_button.disabled:
		_on_roll_pressed()

func _on_turn_started(_player_index: int) -> void:
	call_deferred(&"_update_roll_button")

func _on_dice_rolled(_player_index: int, _result: int) -> void:
	_update_roll_button()

func _on_game_over(_winner_index: int) -> void:
	roll_button.disabled = true

func _update_roll_button() -> void:
	roll_button.disabled = not _can_local_player_roll()

func _can_local_player_roll() -> bool:
	if GameManager.state != Enums.GameState.ROLLING:
		return false
	var my_player_index := NetworkManager.get_my_player_index()
	if my_player_index != -1 and my_player_index != GameManager.current_player_index:
		return false
	return dice.get("is_rolling") != true

func _on_player_moved(player_index: int, new_tile_index: int) -> void:
	# Tell the token to animate to its new tile.
	tokens[player_index].move_to(new_tile_index)

func _on_player_left_mid_match(_peer_id: int, player_name: String) -> void:
	_on_match_ended("%s disconnected - match ended." % player_name)

func _on_match_ended(message: String) -> void:
	# Same "build at runtime" approach as GameOverScreen - no scene edits.
	var overlay := CanvasLayer.new()
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_child(vbox)

	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(label)

	var back_button := Button.new()
	back_button.text = "Back to Lobby"
	back_button.pressed.connect(func():
		multiplayer.multiplayer_peer = null
		get_tree().change_scene_to_file("res://scenes/ui/LobbyScreen.tscn")
	)
	vbox.add_child(back_button)
