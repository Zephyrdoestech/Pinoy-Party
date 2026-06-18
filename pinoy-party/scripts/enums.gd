# scripts/enums.gd
extends Node

enum GameState   { WAITING, ROLLING, MOVING, MINIGAME, GAME_OVER }
enum TileType    { BLANK, GAME_TRIGGER, SARI_SARI }
enum PlayerState { IDLE, MOVING, IN_MINIGAME }
