# autoload/EventBus.gd
extends Node

signal dice_rolled(player_index: int, result: int)
signal player_moved(player_index: int, tile_index: int)
signal tile_landed(player_index: int, tile_type: int)
signal minigame_started(minigame_id: String)
signal minigame_finished(scores: Dictionary)
signal turn_started(player_index: int)
signal game_over(winner_index: int)
signal movement_finished(player_index: int)
