extends Node2D

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var skip_button: Button = $SkipButton

func _ready() -> void:
	# Ensure the animation plays automatically
	if not anim_player.is_playing():
		anim_player.play("1st_Cutscene")
	
	# Connect to the finished signal to transition to the main game
	anim_player.animation_finished.connect(_on_animation_finished)
	
	if skip_button:
		skip_button.pressed.connect(_on_skip_button_pressed)

func _on_skip_button_pressed() -> void:
	anim_player.stop()
	_on_animation_finished("1st_Cutscene")

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "1st_Cutscene":
		get_tree().change_scene_to_file("res://scenes/Game.tscn")
