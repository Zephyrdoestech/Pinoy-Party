extends Node2D

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var skip_button: Button = $SkipButton

func _ready() -> void:
	BgmManager.stop()
	# Ensure the animation plays automatically
	if not anim_player.is_playing():
		anim_player.play("1st_Cutscene")
	
	# Connect to the finished signal to transition to the main game
	anim_player.animation_finished.connect(_on_animation_finished)

	if multiplayer.has_multiplayer_peer() and not NetworkManager.is_host:
		if skip_button:
			skip_button.queue_free()
	else:
		if skip_button:
			skip_button.pressed.connect(_on_skip_button_pressed)

func _on_skip_button_pressed() -> void:
	anim_player.stop()
	_trigger_synchronized_transition()

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "1st_Cutscene":
		if not multiplayer.has_multiplayer_peer() or NetworkManager.is_host:
			_trigger_synchronized_transition()

func _trigger_synchronized_transition() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		# Tell every connected client machine to change their scene files at once
		rpc("_rpc_change_scene", "res://scenes/Game.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Game.tscn")
		
@rpc("authority", "call_local", "reliable")
func _rpc_change_scene(target_scene_path: String) -> void:
	get_tree().change_scene_to_file(target_scene_path)
