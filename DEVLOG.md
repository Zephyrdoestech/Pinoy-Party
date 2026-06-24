# Pinoy Party — Developer Log

> **Purpose:** This file is a living reference document for AI-assisted development. It describes the current architecture, file structure, known issues, and design decisions so that any AI assistant can pick up context without reading every file from scratch.

**Engine:** Godot 4.6 (GDScript, Forward Plus renderer, D3D12 on Windows)  
**Branch:** `Lancer` (active development branch, pushes to `Zephyrdoestech/Pinoy-Party`)  
**Last Updated:** 2026-06-22

---

## Table of Contents
- [Project Overview](#project-overview)
- [Repository Structure](#repository-structure)
- [Autoloads (Singletons)](#autoloads-singletons)
- [Scene Graph](#scene-graph)
- [State Machine (FSM)](#state-machine-fsm)
- [Board System](#board-system)
- [Player Token System](#player-token-system)
- [Minigame System](#minigame-system)
- [UI System](#ui-system)
- [Input Mappings](#input-mappings)
- [Known Issues & TODOs](#known-issues--todos)
- [Design Decisions & Gotchas](#design-decisions--gotchas)
- [Recent Bug Fixes](#recent-bug-fixes)
- [Planned Minigames](#planned-minigames)

---

## Project Overview

Pinoy Party is a local-multiplayer board game inspired by Filipino children's street games. Up to 4 players take turns rolling a dice, moving tokens around a looping tile board, and competing in minigames when a player lands on a `GAME_TRIGGER` tile. The game ends when any player reaches the final tile; the player with the highest score wins.

**Core loop:**
1. `State_StartTurn` — identifies the current player
2. `State_WaitingForDice` — waits for the Roll button press
3. `State_Moving` — animates the player token tile-by-tile
4. `State_TileEvent` — resolves the tile type (BLANK → skip, GAME_TRIGGER → minigame)
5. `State_EndTurn` — checks win condition, advances player index, loops back to 1

---

## Repository Structure

```
Pinoy-Party/                        ← repo root
└── pinoy-party/                    ← Godot project root (res://)
    ├── project.godot
    ├── autoload/
    │   ├── EventBus.gd             ← Global signal bus (singleton)
    │   ├── GameManager.gd          ← Global game state (singleton)
    │   ├── SceneLoader.gd          ← Scene transitions (singleton)
    │   ├── Constants.gd            ← Compile-time constants (singleton)
    │   ├── Enums.gd                ← Shared enums (singleton)
    │   └── Utils.gd                ← Static utility functions (singleton)
    ├── scenes/
    │   ├── Game.tscn               ← Main scene (entry point)
    │   ├── Game.gd
    │   ├── board/
    │   │   ├── Board.tscn / board.gd       ← Procedural tile generation
    │   │   ├── Tile.tscn / tile.gd         ← Individual tile node
    │   │   ├── Dice.tscn / dice.gd         ← Dice roll animation
    │   │   └── TilePath.gd                 ← Stub (unused)
    │   ├── player/
    │   │   ├── PlayerToken.tscn / player_token.gd  ← Animated board token
    │   │   └── Player.tscn / player.gd             ← Stub (unused)
    │   ├── minigames/
    │   │   ├── BaseMinigame.gd             ← Abstract base class for all minigames
    │   │   └── LuksongBaka/
    │   │       ├── LuksongBaka.tscn
    │   │       └── luksong_baka.gd         ← Only implemented minigame
    │   └── ui/
    │       ├── HUD.tscn / hud.gd           ← Turn indicator label
    │       └── ScoreBoard.tscn / score_board.gd  ← Stub (unused)
    ├── scripts/
    │   ├── constants.gd
    │   ├── enums.gd
    │   ├── utils.gd
    │   └── state_machine/
    │       ├── State.gd                    ← Base state class
    │       ├── StateMachine.gd             ← FSM controller
    │       └── states/
    │           ├── State_StartTurn.gd
    │           ├── State_WaitingForDice.gd
    │           ├── State_Moving.gd
    │           ├── State_TileEvent.gd
    │           └── State_EndTurn.gd
    └── assets/
        ├── board_characters/
        │   └── character1–4/               ← Board token sprite assets (4 characters)
        └── minigame_characters/
            └── mg_charac1–4/              ← Minigame character sprite assets (4 characters)
```

---

## Autoloads (Singletons)

All autoloads are registered in `project.godot` and accessible globally by name.

### `EventBus` (`autoload/EventBus.gd`)
Global signal bus. All cross-system communication goes through here. No direct node references across systems.

| Signal | Parameters | Who emits | Who listens |
|--------|-----------|-----------|-------------|
| `dice_rolled` | `player_index: int, result: int` | `GameManager.on_dice_rolled()` | `State_WaitingForDice` |
| `player_moved` | `player_index: int, tile_index: int` | `State_Moving` | `Game.gd`, `PlayerToken` |
| `tile_landed` | `player_index: int, tile_type: int` | `State_TileEvent` | UI (future) |
| `minigame_started` | `minigame_id: String` | `State_TileEvent` | UI (future) |
| `minigame_finished` | `scores: Dictionary` | `BaseMinigame._finish()` | `State_TileEvent` (await) |
| `turn_started` | `player_index: int` | `State_StartTurn`, `GameManager.start_turn()` | `HUD`, `Game.gd` |
| `game_over` | `winner_index: int` | `State_EndTurn`, `GameManager` | UI (future) |
| `movement_finished` | `player_index: int` | `Game.gd` (relays from PlayerToken) | `State_Moving` |

> **Note:** All signals use `@warning_ignore("unused_signal")` because they are connected externally, not within EventBus itself.

### `GameManager` (`autoload/GameManager.gd`)
Holds all mutable game state. The FSM reads/writes this.

```gdscript
var state: Enums.GameState          # Legacy state enum (WAITING, ROLLING, MOVING, MINIGAME, GAME_OVER)
var current_player_index: int       # 0-based, wraps 0–3
var players: Array[Dictionary]      # [{name, tile_index, score, color, state}] × 4
var pending_roll: int               # Written by State_WaitingForDice, read by State_Moving
```

**Player dictionary schema:**
```gdscript
{
  "name":       "Player 1",          # String
  "tile_index": 0,                   # int, 0-based position on the board loop
  "score":      0,                   # int, total score points accumulated
  "color":      Color.RED,           # Color (RED/BLUE/GREEN/YELLOW per player)
  "state":      Enums.PlayerState.IDLE  # IDLE | MOVING | IN_MINIGAME
}
```

**Legacy methods** (kept for compatibility, called by `dice.gd`):
- `on_dice_rolled(result)` → emits `EventBus.dice_rolled`
- `start_turn()` → emits `EventBus.turn_started`
- `on_move_complete()` → emits `EventBus.player_moved` (may be unused)
- `add_score(player_index, points)` → mutates score, checks game over

### `SceneLoader` (`autoload/SceneLoader.gd`)
Handles scene transitions for minigames.

- `go_to_minigame(minigame_id, players)` — calls `get_tree().change_scene_to_file()` then deferred `start_game()`
- `return_to_board()` — transitions back to `res://scenes/Game.tscn`

> **Important:** After `change_scene_to_file()`, the StateMachine in Game.tscn is destroyed. When returning to the board, a brand-new StateMachine starts from `State_StartTurn` for the **same** `current_player_index` that was active when the minigame launched. State_TileEvent's `await EventBus.minigame_finished` is also destroyed, but `_finish()` in BaseMinigame already emitted it before transitioning, so this is safe.

### `Constants` (`scripts/constants.gd`)

| Constant | Value | Meaning |
|----------|-------|---------|
| `MAX_PLAYERS` | 4 | Number of players |
| `TOTAL_TILES` | 34 | Total tiles in the board loop |
| `DICE_FACES` | 6 | Max dice roll value |
| `TILE_SPACING` | 70 | Pixels between tile centers |
| `TOP_TILES` | 9 | Tiles along top/bottom edges |
| `SIDE_TILES` | 8 | Tiles along left/right edges |
| `MOVE_STEP_DURATION` | 0.2 | Seconds per tile hop animation |
| `DICE_ROLL_TICKS` | 15 | Frames of dice animation |
| `MINIGAMES` | `["LuksongBaka", ...]` | Registered minigame IDs (only LuksongBaka is implemented) |

### `Enums` (`scripts/enums.gd`)

```gdscript
enum GameState   { WAITING, ROLLING, MOVING, MINIGAME, GAME_OVER }
enum TileType    { BLANK, GAME_TRIGGER, SARI_SARI }   # SARI_SARI is defined but unused
enum PlayerState { IDLE, MOVING, IN_MINIGAME }
```

### `Utils` (`scripts/utils.gd`)
Static utility functions. Accessed as `Utils.function_name()` (static call, not instance).

- `random_minigame() -> String` — picks a random ID from `Constants.MINIGAMES`
- `tile_position(index) -> Vector2` — converts a tile index to a world position on the board perimeter loop (clockwise: top → right → bottom → left)
- `token_offset(player_index) -> Vector2` — offsets tokens so multiple players on the same tile don't overlap

---

## Scene Graph

### `Game.tscn` (main scene)
```
Game (Node2D)                         ← Game.gd
├── Board (Node2D)                    ← board.gd, generates tiles procedurally
├── Dice (Node2D)                     ← dice.gd, at position (751, 330)
├── StateMachine (Node)               ← StateMachine.gd
│   ├── State_StartTurn (Node)
│   ├── State_WaitingForDice (Node)
│   ├── State_Moving (Node)
│   ├── State_TileEvent (Node)
│   └── State_EndTurn (Node)
└── UI (CanvasLayer)
    ├── RollButton (Button)           ← at (665, 397)–(785, 437)
    └── TurnLabel (Label)             ← at (666, 362)–(916, 392)
```

> **Note:** `HUD.tscn` and `ScoreBoard.tscn` exist but are **not yet added to Game.tscn**. `HUD.gd` connects to `EventBus.turn_started` and would update its own turn label — there is a **duplicate** turn label responsibility between `Game.gd` and `HUD.gd`.

PlayerToken nodes are **spawned at runtime** by `Game.gd._spawn_tokens()` and added as children of the Game node. They are not in the `.tscn` file.

---

## State Machine (FSM)

The FSM lives in `scripts/state_machine/`. `StateMachine.gd` discovers child State nodes at `_ready()`, connects their `transition_requested` signals, and routes `_physics_process` → `current_state.tick()`.

### State: `State_StartTurn`
- Reads `GameManager.current_player_index`
- Resets player's `state` to `IDLE`
- Emits `EventBus.turn_started`
- Immediately transitions to `State_WaitingForDice`

### State: `State_WaitingForDice`
- Sets `GameManager.state = ROLLING`
- Connects `EventBus.dice_rolled` with `CONNECT_ONE_SHOT`
- `_on_dice_rolled()` guard: rejects rolls for the wrong player index
- On valid roll: stores `GameManager.pending_roll`, transitions to `State_Moving`
- `exit()` safely disconnects if still connected

> **Watch out:** The `CONNECT_ONE_SHOT` is consumed on the FIRST emission regardless of whether the guard fires. If the guard returns early, the connection is already gone and the state is stuck. In practice this shouldn't happen since only one player rolls at a time.

### State: `State_Moving`
- Reads `GameManager.pending_roll` and `players[player_idx]["tile_index"]`
- Computes `new_tile = min(old_tile + roll, TOTAL_TILES - 1)`
- Calls `_animate_and_advance(player_idx, new_tile)` via `call_deferred`

**`_animate_and_advance` (coroutine):**
1. Emits `EventBus.player_moved` → PlayerToken starts animating
2. Uses an `Array[bool]` as a done-flag (needed because GDScript lambdas capture primitives by VALUE, not reference)
3. Connects `EventBus.movement_finished` with a one-shot lambda that sets `done[0] = true` when the right player finishes
4. Polls `process_frame` until `done[0]` is true
5. Updates `GameManager.players[player_idx]["tile_index"] = new_tile`
6. Transitions to `State_TileEvent`

> **Critical design note:** `_animate_and_advance` is a deferred coroutine. It outlives the state if a forced transition happens. The one-shot + done-array pattern prevents stale coroutines from stealing signals for future players' movements.

### State: `State_TileEvent`
- Reads the tile type from `_get_tile_type(tile_idx)` (placeholder stub — every 5th tile triggers a minigame)
- **TODO:** Replace `_get_tile_type()` with `Board.get_tile_type(tile_idx)` for accuracy
- Emits `EventBus.tile_landed`
- `BLANK` → immediately transitions to `State_EndTurn`
- `GAME_TRIGGER` → picks a random minigame, emits `minigame_started`, calls `SceneLoader.go_to_minigame()`, awaits `EventBus.minigame_finished`

> **Note:** There are currently TWO tile type resolution systems — `State_TileEvent._get_tile_type()` (every 5th tile) and `Board._determine_tile_type()` (every 4th tile). They disagree. The board's visual color (red = GAME_TRIGGER) reflects `Board._determine_tile_type()`, but the state machine uses its own `_get_tile_type()`. These need to be unified.

### State: `State_EndTurn`
- Calls `_save_state(_gm)` — **stub, does nothing**
- Calls `_update_ui(_gm, _player_idx)` — **stub, does nothing**
- `_check_game_over(gm)` — returns true if any player's `tile_index >= TOTAL_TILES - 1`
- If game over: emits `EventBus.game_over`, **does not transition** (FSM halts)
- Otherwise: advances `current_player_index = (current_player_index + 1) % MAX_PLAYERS`
- Transitions back to `State_StartTurn`

---

## Board System

### `board.gd`
Procedurally generates `TOTAL_TILES` (34) tile nodes on `_ready()`. Each tile's world position is computed by `Utils.tile_position(i)` — a clockwise perimeter loop starting top-left.

**Tile type assignment** (`_determine_tile_type`):
- Index 0 and 33 (start/finish): `BLANK`
- Every 4th tile (4, 8, 12, ...): `GAME_TRIGGER` (red)
- All others: `BLANK` (gray)

Exposes `get_tile_position(index)` and `get_tile_type(index)` for external use.

### `tile.gd`
Simple display node. Has `tile_index` and `tile_type`. Calls `_update_visual()` to set `ColorRect` color (gray = BLANK, red = GAME_TRIGGER).

### `dice.gd`
- `roll()`: guards against double-rolling with `is_rolling` flag
- Animates `DICE_ROLL_TICKS` random values at 50ms intervals
- Settles on a final `randi_range(1, DICE_FACES)` result
- Calls `GameManager.on_dice_rolled(result)` which emits `EventBus.dice_rolled`

---

## Player Token System

### `player_token.gd`
Each of the 4 players gets a `PlayerToken` node spawned by `Game.gd._spawn_tokens()`.

- `setup(index, board, sheet)` — assigns `player_index`, stores `board_ref`, calls `_build_frames(sheet)` to construct `SpriteFrames` at runtime, sets `sprite.scale = Vector2(0.05, 0.05)`, plays `walkFront`, positions at tile 0
- `_build_frames(sheet)` — builds a `SpriteFrames` resource entirely at runtime: creates 4 `AtlasTexture` regions (each 1024×1024px) sliced from the 4096×1024 spritesheet. No `.tres` bake needed.
- `move_to(target_tile_index)` — reads current `tile_index` from GameManager, calls `_step_toward`
- `_step_toward(current, target)` — recursively tweens one tile at a time (0.2s per hop via `Constants.MOVE_STEP_DURATION`)
  - At each step: updates `GameManager.players[player_index]["tile_index"]`
  - On arrival: emits local `movement_finished(player_index)` signal

The local `movement_finished` signal is relayed to `EventBus.movement_finished` by `Game.gd._on_token_movement_finished()`.

### `PlayerToken.tscn` node structure
```
PlayerToken (Node2D)      ← player_token.gd
├── Sprite (AnimatedSprite2D) ← scale (0.05, 0.05) set in script; SpriteFrames built at runtime
└── Label (Label)            ← debug label (offset 0–40×0–23)
```

### Character Asset Wiring (`Game.gd`)
`CHARACTER_SHEETS` maps player index → confirmed PNG path:
```
Player 0 → res://assets/characters/board_characs/charac1/charac1_walkFront.PNG
Player 1 → res://assets/characters/board_characs/charac2/charac2_walkFront.PNG
Player 2 → res://assets/characters/board_characs/charac3/charac3_walkFront.PNG
Player 3 → res://assets/characters/board_characs/charac4/charac4_walkFront.PNG
```

**Spritesheet spec:** 4096×1024px, 4 frames horizontal (hframes=4, vframes=1), 1024×1024px per frame, 8 FPS looping. Imported as `CompressedTexture2D` (standard PNG importer). `_build_frames()` slices frames via `AtlasTexture.region`.


---

## Minigame System

### `BaseMinigame.gd`
Abstract base class for all minigames.

```gdscript
var participating_players: Array[int]  # set by SceneLoader before start_game()
func start_game(players: Array[int])   # override in subclasses
func _finish(scores: Dictionary)       # call at end; emits minigame_finished, then returns to board
```

`_finish(scores)` flow:
1. Emits `EventBus.minigame_finished(scores)` — caught by `State_TileEvent`'s await
2. Waits 2 seconds (to show results)
3. Calls `SceneLoader.return_to_board()`

> **Important:** `minigame_finished` must be emitted BEFORE `return_to_board()` is called, because `change_scene_to_file()` destroys the FSM and all awaiting coroutines.

### `SceneLoader.gd` (minigame flow)
```
go_to_minigame(id, players):
  change_scene_to_file("res://scenes/minigames/{id}/{id_snake}.tscn")
  call_deferred → _start_minigame_deferred(players)
    await process_frame
    if current_scene is BaseMinigame:
      current_scene.start_game(players)
```

> **Gotcha:** SceneLoader uses `minigame_id.to_snake_case()` to build the script filename. So `"LuksongBaka"` → `"luksong_baka.gd"`. New minigames must follow this naming convention exactly.

### Implemented Minigame: `LuksongBaka`

A rhythm-based timing minigame (jump-the-rope).

**Mechanics:**
- A marker sweeps across each player's bar from left to right
- A green "safe zone" appears at a random position on the bar
- Players press their jump button (`p1_jump`=1, `p2_jump`=2, `p3_jump`=3, `p4_jump`=4) to jump
- Jumping while the marker is in the zone → "Cleared!" (+1 score via `GameManager.add_score`)
- Jumping outside the zone or not jumping → "Caught!" (eliminated from this round)
- Last player standing gets +3 bonus points
- Each round speeds up (`ROUND_SPEEDUP = 0.85×`) and shrinks the zone (`ZONE_SHRINK = 0.92×`)
- Game ends when ≤1 player remains alive

**Known bug in `_unhandled_input`:**
```gdscript
# Line 136 — always calls _try_jump(0) regardless of which player pressed
_try_jump(0)  # TODO: map to correct player_index per local/network input scheme
```
This causes Player 1 (index 0) to auto-jump whenever any player presses their button.

**Score integration:** Uses `GameManager.add_score()` during gameplay for "Cleared!" jumps. The `_end_game()` `scores` dictionary only tracks the +3 survivor bonus; the per-round `+1` points are already applied live.

### Planned Minigames (not yet implemented)
`Constants.MINIGAMES = ["LuksongBaka", "LangitLupa", "BatoLata", "AgawBase", "SackRace"]`

Only `LuksongBaka` has a scene + script. The others are listed in constants but will crash `SceneLoader` if selected. `Utils.random_minigame()` can return any of them.

---

## UI System

### `hud.gd` (`scenes/ui/HUD.tscn`)
Connects to `EventBus.turn_started`. Updates a `TurnLabel` with the player's name and color.

> **Not yet added to `Game.tscn`**. There is a duplicate `TurnLabel` inside the `UI/CanvasLayer` in `Game.tscn` that `Game.gd` updates directly via `_on_turn_started()`. Once `HUD.tscn` is added to the scene, the Game.gd label should be removed.

### `score_board.gd` (`scenes/ui/ScoreBoard.tscn`)
**Empty stub** — `_ready()` and `_process()` both just `pass`. Not connected to anything.

---

## Input Mappings

Defined in `project.godot`:

| Action | Key | Player |
|--------|-----|--------|
| `p1_jump` | `1` | Player 1 |
| `p2_jump` | `2` | Player 2 |
| `p3_jump` | `3` | Player 3 |
| `p4_jump` | `4` | Player 4 |

The standard Godot `ui_accept` (Space/Enter) triggers dice roll in both `dice.gd` and `Game.gd._unhandled_input()`.

---

## Known Issues & TODOs

### Bugs
- **Luksong Baka input bug** — `luksong_baka.gd:136` always calls `_try_jump(0)` regardless of which player pressed. Fix: replace with `_try_jump(player_idx)`.
- **Dual tile type resolvers** — `State_TileEvent._get_tile_type()` uses a different rule (every 5th tile) than `Board._determine_tile_type()` (every 4th tile). The board visuals and the state machine disagree on which tiles trigger minigames.
- **Random minigame crashes** — `Utils.random_minigame()` can return minigame IDs that don't have scenes yet (`LangitLupa`, `BatoLata`, `AgawBase`, `SackRace`). `SceneLoader.go_to_minigame()` will error.

### Stubs / Unimplemented
- `State_EndTurn._save_state()` — TODO: persistence layer
- `State_EndTurn._update_ui()` — TODO: scoreboard refresh signal
- `score_board.gd` — empty stub
- `player.gd` — empty stub
- `TilePath.gd` — empty stub
- `ScoreBoard.tscn` — not connected to game scene
- `HUD.tscn` — exists but not added to `Game.tscn`
- Minigames: `LangitLupa`, `BatoLata`, `AgawBase`, `SackRace` — not implemented
- `Enums.TileType.SARI_SARI` — defined but never assigned to any tile
- Board character PNG spritesheets in `assets/characters/board_characs/` — **wired** into `PlayerToken` via `AnimatedSprite2D` + runtime-built `SpriteFrames`
- Minigame character assets in `assets/characters/minigame_characs/` — present but not yet wired into any scene


### Architecture Decisions Pending
- **Game Over screen** — FSM halts at `State_EndTurn` on game over; no UI or transition is implemented
- **Local multiplayer input** — all 4 players share one screen/keyboard; no network/controller support
- **Score display** — scores are tracked in `GameManager.players` but never shown to the user

---

## Design Decisions & Gotchas

### GDScript Lambda Capture Behavior
GDScript 4 lambdas capture **primitive types** (`bool`, `int`, `float`) **by value**. Mutations inside a lambda do NOT affect the outer scope variable. Use an `Array` as a mutable container:

```gdscript
# WRONG — done stays false in outer scope
var done := false
var fn := func(): done = true  

# CORRECT — array is a reference type
var done := [false]
var fn := func(): done[0] = true
```

### Coroutine Lifetimes in FSM
State functions that use `call_deferred` + `await` outlive the state. If a transition happens while a coroutine is waiting, the old coroutine keeps running. Always use one-shot signal connections or done-flags scoped to the specific player/entity to prevent signal theft.

### EventBus Signal Bridge
`PlayerToken` emits a **local** `movement_finished` signal. `Game.gd` bridges it to `EventBus.movement_finished`. State_Moving listens on the EventBus. This means if a PlayerToken is ever added to the scene without connecting its local signal in `Game._spawn_tokens()`, State_Moving will hang forever.

### SceneLoader `to_snake_case()` Dependency
Minigame scene paths are built as `res://scenes/minigames/{ID}/{ID.to_snake_case()}.tscn`. The `.tscn` root node name must also match the ID. New minigames must:
1. Create folder `scenes/minigames/{ID}/`
2. Create `{ID_snake_case}.gd` extending `BaseMinigame`
3. Create `{ID}.tscn` with root node named exactly `{ID}`
4. Add the ID string to `Constants.MINIGAMES`

### Tile Index Persistence
`GameManager.players[i]["tile_index"]` is updated **step-by-step inside the tween callback** in `player_token.gd`. It reaches the final value only after the full animation completes. `State_Moving` also writes it once more after the animation finishes (defensive redundancy). `State_TileEvent` reads it after movement, so timing is safe.

---

## Recent Bug Fixes

| Date | Commit | Fix |
|------|--------|----- |
| 2026-06-22 | `a6e4b68` | Added DEVLOG.md |
| 2026-06-22 | `809e83c` | Fixed Player 2+ turn freeze — GDScript lambda captured `bool done` by value; switched to `Array[bool] done` for shared reference |
| 2026-06-22 | `8524e1f` | Fixed turn freeze after Player 2 — open `await` loop in State_Moving stole `movement_finished` signals meant for later players; replaced with one-shot lambda + process_frame poll |
| 2026-06-22 | `aa6dd23` | Fixed GDScript warnings — unused params (`_delta`, `_gm`, `_player_idx`), duplicate `call_deferred`, Tile.tscn UID mismatch, `@warning_ignore` on EventBus signals |
| 2026-06-22 | `a774b3a` | Removed `copilot-advanced` addon; added `LICENSE` and `README.md` |
| 2026-06-24 | *(pending)* | Wired PNG spritesheets into PlayerToken — ColorRect → AnimatedSprite2D; `_build_frames()` slices 4096×1024 spritesheet into 4×1024px AtlasTexture frames at runtime; no .tres bake needed |


---

## Planned Minigames

| ID | Status | Description |
|----|--------|-------------|
| `LuksongBaka` | ✅ Implemented | Jump the rope timing minigame |
| `LangitLupa` | ❌ Not started | Heaven and Earth (jump/duck) |
| `BatoLata` | ❌ Not started | Tin can toss |
| `AgawBase` | ❌ Not started | Base stealing |
| `SackRace` | ❌ Not started | Sack race |
