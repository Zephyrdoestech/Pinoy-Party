extends Node2D

@onready var label: Label = $Label

var is_rolling: bool = false

func roll() -> void:
	if is_rolling:
		return
	is_rolling = true

	for i in Constants.DICE_ROLL_TICKS:
		label.text = str(randi_range(1, Constants.DICE_FACES))
		await get_tree().create_timer(0.05).timeout

	var result: int = randi_range(1, Constants.DICE_FACES)
	label.text = str(result)
	is_rolling = false

	GameManager.on_dice_rolled(result)
	# GameManager.on_dice_rolled() emits EventBus.dice_rolled(current_player_index, result),
	# which PlayerToken listens for to trigger its own movement.
