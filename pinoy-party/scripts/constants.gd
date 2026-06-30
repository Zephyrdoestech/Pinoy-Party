# scripts/constants.gd
extends Node

const MAX_PLAYERS       := 4
const TOTAL_TILES       := 34
const DICE_FACES        := 6
const TILE_SPACING      := 70
const TILES_PER_ROW     := 7   # no longer used by tile_position(), kept in case other code references it
const TOP_TILES         := 9   # tiles along top/bottom edges of the board loop
const SIDE_TILES        := 8   # tiles along left/right edges of the board loop
const MOVE_STEP_DURATION := 0.2  # seconds per tile hop
const DICE_ROLL_TICKS   := 15

# Mini-game IDs — matches folder names under scenes/minigames/
const MINIGAMES := ["LangitLupa"]
