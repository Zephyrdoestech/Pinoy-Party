# Pinoy Party — Developer Log

> **Purpose:** This file is a living reference document for AI-assisted development. It describes the current architecture, file structure, known issues, and design decisions so that any AI assistant can pick up context without reading every file from scratch.

**Engine:** Godot 4.6 (GDScript, Forward Plus renderer, D3D12 on Windows)  
**Branch:** `Lancer` (active development branch, pushes to `Zephyrdoestech/Pinoy-Party`)  
**Last Updated:** 2026-06-29 (Added post-minigame winner/points results screen to BaseMinigame._finish())

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

> **✅ `_on_minigame_finished()` added (2026-06-27) — this is what actually fixes the "still the same player's turn after a minigame" bug.** `GameManager._ready()` connects to `EventBus.minigame_finished` and, on receipt:
> ```gdscript
> func _on_minigame_finished(scores: Dictionary) -> void:
> 	for idx in scores:
> 		players[idx]["score"] += scores[idx]
> 	current_player_index = (current_player_index + 1) % Constants.MAX_PLAYERS
> ```
> See "Minigame Result Handling Moved to GameManager" under Design Decisions & Gotchas for why this couldn't live in `State_TileEvent` at all — short version: that node is destroyed by the scene change before the signal can ever reach it, so only an autoload can safely react to `minigame_finished`.

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
| `MINIGAMES` | `["LuksongBaka", "SackRace"]` | Registered minigame IDs in active rotation. `LangitLupa` has a complete scene/script but is deliberately withheld pending playtest (see Known Issues). `BatoLata`/"Labay Lata" and `AgawBase` have been **cut from the project** (2026-06-25) — see Planned Minigames. |

### `Enums` (`scripts/enums.gd`)

```gdscript
enum GameState   { WAITING, ROLLING, MOVING, MINIGAME, GAME_OVER }
enum TileType    { BLANK, GAME_TRIGGER, SARI_SARI }   # SARI_SARI is defined but unused
enum PlayerState { IDLE, MOVING, IN_MINIGAME }
```

### `Utils` (`scripts/utils.gd`)
Utility functions, accessed as `Utils.function_name()` via the autoload.

> **⚠️ Not actually static (2026-06-27).** `tile_position()` and `token_offset()` were originally written as `static func`s, which is fine on its own — but Godot 4.6 refuses to let a script be *both* an autoload singleton **and** declare a matching `class_name` (`Error: Class "Utils" hides an autoload singleton`), and without a `class_name`, calling a `static func` through the autoload's instance name throws `"is a static function but was called from an instance"`. Since the project wants to keep `Utils` registered as an autoload (rather than removing the autoload and relying purely on `class_name`), the fix was the opposite of what it looks like it should be: **`static` was removed** from every function in this file, and there is **no `class_name` declaration**. `Utils.foo()` now works because it's an ordinary instance-method call on the autoload, not because anything is static. Don't re-add `static` here, and don't re-add `class_name Utils` — either one reopens this exact error.

- `random_minigame() -> String` — picks a random ID from `Constants.MINIGAMES`
- `tile_position(index) -> Vector2` — converts a tile index to a world position on the board perimeter loop (clockwise: top → right → bottom → left)
- `token_offset(player_index) -> Vector2` — offsets tokens so multiple players on the same tile don't overlap

> **Gotcha — local `preload` shadowing the autoload:** `player_token.gd` once had `const Utils = preload("res://scripts/utils.gd")` at the top of the file. This shadows the global `Utils` autoload identifier *within that script only*, so every `Utils.token_offset()` call in that file resolved to the raw script resource instead of the autoload instance — producing the exact same "cannot call non-static function ... directly, make an instance" error, just from a different cause than the one above. Fixed by deleting the local `preload` line; the autoload is already globally accessible without it. **If this error reappears anywhere else, grep the whole project for `preload("res://scripts/utils.gd")` before assuming it's the static/autoload conflict again** — it can be either cause, and they look identical from the error message alone.

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

> **✅ Resolved 2026-06-27:** `HUD.tscn` and `ScoreBoard.tscn` are now both implemented and added to `Game.tscn`. The duplicate turn-label situation is gone — see "UI System" below for current detail.

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
- Reads the tile type via `GameManager.board_ref.get_tile_type(tile_idx)` (delegates to the real board lookup — see "Dual tile-type resolver" fix below)
- Emits `EventBus.tile_landed`
- `BLANK` → immediately transitions to `State_EndTurn`
- `GAME_TRIGGER` → picks a random minigame, emits `minigame_started`, calls `SceneLoader.go_to_minigame()`, and **returns — it does NOT await `EventBus.minigame_finished` anymore.** See "Minigame Result Handling Moved to GameManager" below for why; the short version is that this node is destroyed by the scene change before the signal could ever reach it, so `GameManager` (an autoload) handles the result instead.

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

> **✅ Sprites wired in (2026-06-24).** The PNG spritesheet export blocker noted in earlier versions of this log is resolved — team exported spritesheets from Pixsquare, and `PlayerToken` was upgraded from a `ColorRect` placeholder to a real `AnimatedSprite2D`. Note this happened on the **same day** as several FSM/minigame fixes in this log, on parallel work — see the 2026-06-23 "Reverted PlayerToken to ColorRect placeholder" entry in Recent Bug Fixes for the immediately-preceding state.

- `setup(index, board, front_sheet)` — assigns `player_index`, stores `board_ref`, calls `_build_frames(charac_num, front_sheet)` to build all 4 directional animations, sets `sprite.scale = Vector2(0.05, 0.05)`, plays `walkFront` as the idle stance, and positions the token via `global_position = board_ref.get_tile_position(current_tile) + Utils.token_offset(player_index)`, reading `current_tile` from `GameManager.players[index]["tile_index"]`. **(Re-fixed 2026-06-26 — see Known Issues.)**
- `_build_frames(charac_num, front_sheet)` — builds a `SpriteFrames` resource at runtime with **4 animations** (`walkFront`, `walkBack`, `walkLeft`, `walkRight`). `walkFront` uses the sheet passed in from `Game.gd`; the other 3 are loaded internally via `res://assets/characters/board_characs/charac{N}/charac{N}_walk{dir}.PNG`. Each animation is sliced into 4 frames via `AtlasTexture.region`.
- `_get_direction_animation(from_index, to_index) -> String` — maps the current tile's board segment to the correct walk animation:
  - Tiles 0–8 (top, moving right) → `walkRight`
  - Tiles 9–16 (right side, moving down) → `walkFront`
  - Tiles 17–25 (bottom, moving left) → `walkLeft`
  - Tiles 26–33 (left side, moving up) → `walkBack`
- `move_to(target_tile_index)` — reads current `tile_index` from GameManager, calls `_step_toward`
- `_step_toward(current, target)` — calls `_get_direction_animation()`, plays the result on `sprite`, then tweens one tile at a time (0.2s per hop via `Constants.MOVE_STEP_DURATION`)
  - At each step: updates `GameManager.players[player_index]["tile_index"]`
  - On arrival: emits local `movement_finished(player_index)` signal

The local `movement_finished` signal is relayed to `EventBus.movement_finished` by `Game.gd._on_token_movement_finished()`.

### `PlayerToken.tscn` node structure
```
PlayerToken (Node2D)          ← player_token.gd
├── Sprite (AnimatedSprite2D)  ← scale (0.05, 0.05); SpriteFrames with 4 directional anims built at runtime
└── Label                      ← debug label (offset 0–40×0–23)
```

### Character Asset Wiring (`Game.gd` + `player_token.gd`)
`Game.gd` loads `walkFront` and passes it into `setup()`. `player_token.gd` loads the remaining 3 directional sheets internally.

| Player | walkFront (via Game.gd) | walkBack / walkLeft / walkRight (loaded in `_build_frames`) |
|--------|------------------------|-----------------------------------------------------------|
| 0 | `charac1/charac1_walkFront.PNG` | `charac1/charac1_walk{dir}.PNG` |
| 1 | `charac2/charac2_walkFront.PNG` | `charac2/charac2_walk{dir}.PNG` |
| 2 | `charac3/charac3_walkFront.PNG` | `charac3/charac3_walk{dir}.PNG` |
| 3 | `charac4/charac4_walkFront.PNG` | `charac4/charac4_walk{dir}.PNG` |

All paths are under `res://assets/characters/board_characs/`.

**Spritesheet spec:** 4096×1024px, 4 frames horizontal (`hframes=4`), 1024×1024px per frame, 8 FPS looping, imported as `CompressedTexture2D`.

> **✅ Folder path confirmed (2026-06-26):** verified against the FileSystem dock — the real path is `res://assets/characters/board_characs/` and `res://assets/characters/minigame_characs/`. This matches what `Game.gd` and `player_token.gd` actually use. The `assets/board_characters/` / `assets/minigame_characters/` naming earlier in this log (Repository Structure tree, and the original pre-sprite "blocked" notes) was simply stale — update the Repository Structure tree to match next time it's touched.

---

## Minigame System

### `BaseMinigame.gd`
Abstract base class for all minigames.

```gdscript
var participating_players: Array[int]  # set by SceneLoader before start_game()
var gameplay_locked: bool              # true until run_intro() finishes — see below
func start_game(players: Array[int])   # override in subclasses
func run_intro(announcement_text: String = "")  # see "Pre-round intro" below
func _finish(scores: Dictionary)       # call at end; emits minigame_finished, then returns to board
static func compute_placement_scores(groups: Array) -> Dictionary  # see "Shared placement scoring" below
```

`_finish(scores)` flow:
1. Emits `EventBus.minigame_finished(scores)` — caught by `GameManager._on_minigame_finished()` (an autoload, not `State_TileEvent` — see Design Decisions & Gotchas for why)
2. `await run_results(scores)` — shows the results screen (see below)
3. Calls `SceneLoader.return_to_board()`

#### Results screen (added 2026-06-29)
`run_results(scores: Dictionary)` — called from `_finish()`, after `minigame_finished` is emitted but before `return_to_board()`. Same "build everything at runtime, no scene edits" approach as `run_intro()`:
- **Phase 1 (2s):** dimmed `CanvasLayer`/`ColorRect` (alpha `0.85`) + centered `Label` announcing the winner (`"Player N Wins!"`), or `"It's a Tie!"` if multiple players share the top score. Winner determined by `_get_winner_index(scores)`, a local helper (highest value in the `scores` dict; returns `-1` on a tie).
- **Phase 2 (2s):** winner label is freed and replaced with a `VBoxContainer` listing every player's points earned this round (`"Player N: +X pts"`), pulled directly from the `scores` dict passed into `_finish()`.
- Total added delay: 2s → 4s between minigame end and returning to the board (was a flat 2s with no visual before this).
- Gameplay is already safe during this window — every minigame's `_end_game()` sets `gameplay_locked = true` before calling `_finish()`, so no input-blocking changes were needed here.
- **Known gap:** ties for first place currently show a generic `"It's a Tie!"` rather than naming the tied players. Not yet implemented.

#### Pre-round intro (added 2026-06-27)
Every minigame gets a shared pre-round sequence for free, applying uniformly without touching each minigame's `.tscn`:
- `run_intro(announcement_text: String = "")` — call from a subclass's `start_game()`, *after* any setup that determines the announcement text or world layout (e.g. picking who is "IT"), and *before* gameplay should be possible.
- Builds a `CanvasLayer` + dimmed `ColorRect` (alpha `0.85` — background is barely visible) + centered `Label`, all created at runtime (no scene edits needed).
- Flow: show `announcement_text` for 2s (skipped entirely if `""`) → 3-2-1 countdown (1s each) → overlay frees itself → `gameplay_locked = false` → emits `intro_finished`.
- **Subclasses MUST check `if gameplay_locked: return` at the top of their own `_process()`** — that's what actually blocks movement/timers/tagging during the intro. `BaseMinigame` also calls `set_process_unhandled_input(false)` for the duration as a belt-and-suspenders measure against stray button presses.
- Currently wired into `LangitLupa` (announces who is IT) and `SackRace` (no announcement, just the countdown). **`LuksongBaka` calls `run_intro()` too** but still runs its own separate `_start_countdown()` 3-2-1 sequence on the bars — these two countdowns are currently redundant/stacked rather than unified; worth deduping later (TODO below).

#### Shared placement scoring (added 2026-06-27)
`compute_placement_scores(groups: Array) -> Dictionary` — used by `LuksongBaka` and `SackRace` (both "elimination" minigames where the result is a 1st/2nd/3rd placement). `groups` must be ordered best-to-worst placement, where each element is an `Array[int]` of player indices tied for that placement block (size 1 = no tie).

**Tie rule:** a tied group is awarded the point value of the **worst** individual rank their group would have spanned had they not tied. Any rank beyond 3rd scores 0. Worked examples (from the original scoring spec):
- 4 players: P1 eliminated alone first, then P2+P3 eliminated together, leaving P4 as sole survivor. Groups (best→worst): `[[P4], [P2, P3], [P1]]`. P4 (rank 1) → 3pts. P2/P3 would span ranks 2–3 → worst-in-span = rank 3 → both get 1pt. P1 would be rank 4 → beyond 3rd → 0pts.
- 4 players: 3 players eliminated simultaneously, 1 survivor. Groups: `[[winner], [the 3 losers]]`. Winner → 3pts. The 3-loser group would span ranks 2–4; clipped to the defined 1st/2nd/3rd tiers, the worst rank *within that overlap* is 3 → all three get 1pt (not 0 — the clip to "ranks that actually have a reward" is what makes this differ from naively reading the bottom of the full span).

Algorithm: walk `groups` in order, tracking a `rank_cursor` starting at 1. For each group, `worst_rank = rank_cursor + group.size() - 1`; if `rank_cursor <= 3`, the reward is `PLACEMENT_POINTS[min(worst_rank, 3)]` (`{1:3, 2:2, 3:1}`) for every member; otherwise the whole group scores 0. Advance `rank_cursor` by the group's size and continue.

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

> **⚠️ Confirmed failure mode (2026-06-24):** This naming mismatch is not just theoretical — it caused a real, hard-to-diagnose bug. The actual `.tscn` file on disk did not match the `to_snake_case()` output exactly, so `get_tree().change_scene_to_file(path)` silently failed: it returned without throwing a catchable error in the surrounding code, `current_scene` remained `Game` (confirmed via the Remote scene tree while paused), and `State_TileEvent` was left permanently stuck awaiting `EventBus.minigame_finished` with zero console output after the `"Loading minigame scene"` print. From the player's perspective, landing on a `GAME_TRIGGER` tile appeared to do nothing — the Roll Dice button stayed clickable and turns kept silently advancing functionally, but the minigame never appeared. **Diagnosis required:** adding a `push_error` check on `change_scene_to_file()`'s return code, instrumenting `_start_minigame_deferred()` with a print at its very first line, and manually visually comparing the on-disk filename against the constructed path character-by-character in the FileSystem dock. **Lesson:** always verify the exact on-disk filename for every new minigame scene before adding it to `Constants.MINIGAMES` — do not assume `to_snake_case()` output matches what was actually saved.

### Implemented Minigame: `LuksongBaka`

A rhythm-based timing minigame (jump-the-rope).

**Mechanics:**
- A marker sweeps across each player's bar from left to right
- A green "safe zone" appears at a random position on the bar
- Players press their jump button (`p1_jump`=1, `p2_jump`=2, `p3_jump`=3, `p4_jump`=4) to jump
- Jumping while the marker is in the zone → "Cleared!" (no longer scores live — see Scoring below)
- Jumping outside the zone or not jumping → "Caught!" (eliminated from this round)
- Each round speeds up (`ROUND_SPEEDUP = 0.85×`) and shrinks the zone (`ZONE_SHRINK = 0.92×`)
- Game ends when ≤1 player remains alive

~~**Known bug in `_unhandled_input`:** always called `_try_jump(0)` regardless of which player pressed.~~ **FIXED (2026-06-24):** The stray unconditional `_try_jump(0)` line (a leftover from a partial merge — see `Recent Bug Fixes`) has been deleted. The per-player loop (`for player_idx in alive_players: ... if event.is_action_pressed(action): _try_jump(player_idx)`) is now the only call path and has been verified correct via live testing.

> **✅ Marker visual reset bug — FIXED (2026-06-27).** Surviving players' markers visually stayed at their previous round's end position throughout the next round's 3-2-1 countdown, then snapped to the start the instant the sweep began. Cause: `_start_countdown()` reset the zone and status label each round but never reset `marker_rect.position.x` — the marker is only ever moved inside `_process()`, which returns immediately while `sweeping` is false (i.e. for the entire countdown). Fixed by adding `marker_rect.position.x = 0.0` to the same per-player reset loop that already resets the zone/status.

> **✅ Start-of-game freeze — FIXED (2026-06-28).** After deduping the redundant double-countdown (see below), `start_game()` was left calling `run_intro()` but never calling `_start_countdown()` afterward — so `_begin_sweep()` (the only place that sets `sweeping = true`) never ran, and `_process()`'s `if not sweeping: return` guard silently stopped everything forever. No error, scene loaded fine, UI rendered, nothing ever moved. **Fix + proper dedupe:** `start_game()` now does `await run_intro()` then calls `_start_countdown()`. `_start_countdown()` itself no longer runs its own separate `3, 2, 1, JUMP!` text loop (that was the original duplicate-countdown issue) — it just does the per-round bar/zone/marker reset and goes straight into `_begin_sweep()`. Net effect: the shared dimmed countdown overlay now plays once, before round 1 only; later rounds get the existing 1-second pause (from `_check_game_over()`) without re-darkening the screen. The now-unused `countdown_label`/`$UI/CountdownLabel` reference was removed from the script (the node itself can be deleted from the scene if desired, it's just inert now).

**Scoring (reworked 2026-06-27):** No more live per-jump points. Score is now placement-only, computed once at `_end_game()` via `BaseMinigame.compute_placement_scores()`. Each round's simultaneous eliminations (both immediate "Caught!" misses via `_try_jump` and end-of-round auto-eliminations for anyone who never jumped) are collected into `eliminated_this_round` and pushed onto `elimination_order` as one tie-group. At game end, the placement groups are built as: the lone survivor (if `alive_players.size() == 1`) first, then `elimination_order` reversed (most recently eliminated = better placement) — fed straight into `compute_placement_scores()`. See that function's doc above for the exact tie-breaking rule and worked examples.

### Implemented Minigame: `SackRace`

A timed mash-race minigame. All 4 players race simultaneously on parallel tracks.

**Mechanics:**
- Each press of a player's jump button (`p1_jump`–`p4_jump`) advances their sack a fixed distance (`HOP_DISTANCE`)
- First to reach `FINISH_DISTANCE` (30 hops) wins; race also ends via `RACE_TIMEOUT` (15s) if nobody finishes, ranking remaining players by progress
- Visual: 4 `ColorRect` nodes under `Tracks/Player 1`–`Player 4` move along the X axis (`HOP_PIXELS` per hop); a `TimerLabel` shows live countdown

**Folder/naming:** `res://scenes/minigames/SackRace/sack_race.gd` + `SackRace.tscn` (root node named `SackRace`). Filenames manually verified against `to_snake_case()` output before being added to `Constants.MINIGAMES`, per the lesson learned from the LuksongBaka scene-path bug above.

> **✅ Double-scoring + missing tie-handling — FIXED (2026-06-27).** `_end_race()` previously called `GameManager.add_score()` directly *and* passed the same scores through `_finish()` — which (via `GameManager._on_minigame_finished()`) applies them a second time, silently doubling every player's points from this minigame. It also had zero tie handling: two players with identical progress at the 15s timeout were given an arbitrary order by `sort_custom` instead of being treated as tied. **Fix:** finishers (who crossed the line) keep their strict order — simultaneous finishes aren't physically possible since only one key-press event ever fires per advance. Anyone who didn't finish is now grouped by `is_equal_approx(progress[a], progress[b])` into real tie-groups, then the whole placement list is fed through `BaseMinigame.compute_placement_scores()` exactly once.

### Implemented Minigame: `LangitLupa`

A real-time tag minigame — meaningfully different from the other two since it requires continuous movement rather than single-button input, and currently only supports one human-controlled player (`local_player_index`) with the rest driven by a temporary wandering-AI stub. See "Mini-game Movement & Input Scope" and "Area Size" sections under Design Decisions & Gotchas for full detail.

**Mechanics:**
- One random participating player is designated "IT" (`it_player`), shown via a distinct color and `ItLabel`
- `NUM_AREAS` (6) "elevated areas" spawn each round; non-IT players are safe from tagging while standing inside one
- An area becomes permanently `unsafe` once any non-IT player has continuously occupied it for `AREA_SAFE_DURATION` (4s) — see "Area visuals" below for exactly what happens on screen when this triggers
- IT is blocked from ever stepping inside a still-safe area (checked in movement resolution)
- IT tags any non-elevated, non-safe player within `TAG_RADIUS` via proximity check each frame
- Round ends after `ROUND_DURATION` (60s), **or immediately once IT has tagged every other player** (added 2026-06-27 — see `_check_tagging()`, no need to wait out the rest of the timer)
- Pre-round sequence now goes through the shared `BaseMinigame.run_intro()` (announces "Player X is IT!" for 2s, then a dimmed 3-2-1) instead of its own local countdown — see `BaseMinigame.gd` above

**Dash mechanic (added 2026-06-27):** every player — human and AI — can dash for a 3× speed burst (`DASH_SPEED_MULTIPLIER`) lasting `DASH_DURATION` (0.15s), on a per-player `DASH_COOLDOWN` (5s). Human triggers it via the `dash` input action (bound to Shift); AI rolls a 30% chance (`AI_DASH_CHANCE`) to dash whenever it picks a new wander direction, only if off cooldown. Dash still respects the "IT can't enter elevated areas" rule since both normal movement and dash bursts flow through the same `_apply_move()`. Each player has a small radial cooldown ring — a `Node2D` with a script built **at runtime** via `GDScript.new()`/`set_source_code()` (no new scene file needed) drawing a shrinking wedge with `draw_arc()`; full circle = just dashed, shrinks to nothing as the cooldown clears.

**Area detection + visuals overhaul (2026-06-28):** three related issues, all in how "elevated areas" are sized, detected, and rendered, fixed together:
- **Detection didn't match the visual.** Areas were checked with `pos.distance_to(area.pos) < AREA_RADIUS` (a circle) while the visible `ColorRect` was an 80×80 square — so the corners of the visible safe zone weren't actually safe, and the circle's "radius" didn't read as matching what was on screen at all. Replaced with `_point_in_area(point, area, margin)`, an exact square-bounds check using half of `AREA_SIZE` — used consistently everywhere an area is checked (`_apply_move`'s IT-blocking, `_update_areas`'s occupancy check, `_is_player_safe`). `AREA_RADIUS` no longer exists in this file.
- **"Permanently unsafe" used to flash red forever** (`modulate.a = 0.5 + 0.5 * sin(round_time * 10.0)`, looping indefinitely) instead of disappearing — this was actually matching the original spec wording ("flashes red, does not refresh") but wasn't the desired final behavior. Now: each area stores `unsafe_since` (the `round_time` it tripped), flashes for `AREA_FLASH_DURATION` (1s) as a brief "this just became unsafe" cue, then sets `visible = false` for good.
- **Players could spawn already standing inside a safe area**, and **areas could spawn directly on top of a player's spawn point** — both fixed together, see "Fixed spawn cluster" below.

**Fixed spawn cluster (2026-06-28):** player spawning was reworked from "fully random, with a 30-attempt reroll to avoid areas" to a fixed, predictable layout — all 4 players now spawn at a constant `SPAWN_CENTER` (`Vector2(400, 250)`) offset by one of four small diagonal `SPAWN_OFFSETS` (±40, ±40), so they're always clustered together but never overlapping (80px between diagonal neighbors, well above `TAG_RADIUS`). `_spawn_areas()` now runs *after* `_position_players()` and calls `_find_area_spawn_avoiding_players()`, rerolling a candidate area position (up to 30 attempts) if it lands within `AREA_SIZE/2 + 30px` of any player's now-known spawn point. Order matters here: areas need players already positioned to check against.

> **✅ Scoring formula was wrong AND double-counted — FIXED (2026-06-27).** Old `_end_game()` gave IT `tagged_count * 2` and every survivor a flat `2` regardless of how many survived, **and** called `GameManager.add_score()` directly while also passing the same dict through `_finish()` — doubling every point awarded. Correct formula per design: IT scores 1 point per tagged player; each surviving non-IT player scores 1 point per surviving non-IT player (so with 4 total players and exactly 1 tagged, IT gets 1 and each of the 2 survivors gets 2). Tagged players get no entry in the scores dict at all (defaults to 0). Scoring now flows through `_finish()` exactly once.

> **✅ Repeat-scoring on round end — FIXED (2026-06-27).** Independently of the formula bug above, scores were being applied dozens of times per round-end instead of once. `_end_game()` only set `round_active = false`, but `_process()`'s only early-return guard was `if gameplay_locked: return` — and `round_active` being false just made the very next frame's `if not round_active: round_active = true` quietly re-arm itself and fall through to `_check_tagging()` again, which still saw the win condition as true and called `_end_game()` again. Since `_finish()` has a 2-second `await` before the scene actually changes, this repeated ~60 times/sec for that whole window, with `GameManager._on_minigame_finished()` adding the score block every single time — producing wildly inflated, framerate-dependent totals with zero errors thrown. **Fix:** `_end_game()` now also sets `gameplay_locked = true` immediately, reusing the same flag that already blocks input during the intro, so `_process()` stops cold the very next frame. (`SackRace` and `LuksongBaka` were checked and don't have this bug — both already use a clean `if not race_active/sweeping: return` instead of a re-arming pattern.)

**Folder/naming:** `res://scenes/minigames/LangitLupa/langit_lupa.gd` + `LangitLupa.tscn` (root node named `LangitLupa`).

pending full live playtest of the area/tag logic via the AI stub, and pending real LAN player movement to replace `local_player_index`'s current hardcoded value of `0`.

> **⚠️ Resolved file-mixup scare (2026-06-26):** at one point `langit_lupa.gd` was found to actually contain `bato_lata.gd`'s content (node lookups for `$Player1`, `$ResultLabel`, slipper-throwing logic — none of which exist in `LangitLupa.tscn`), causing a wall of "Node not found" errors. Root cause not fully confirmed, but most likely an accidental copy-paste mixup or a stray file grab during the branch merge. Restored from the correct source; flagging here in case the same mixup recurs with any other minigame file pair.

---

## UI System

### `hud.gd` (`scenes/ui/HUD.tscn`)
Connects to `EventBus.turn_started`. Builds its own `Label` at runtime in `_ready()` (the scene itself has no child nodes — root `Control` + script only) and updates it with the current player's name and color.

> **✅ Added to `Game.tscn` (2026-06-27).** The old duplicate `TurnLabel` that lived directly in `Game.tscn`'s `UI/CanvasLayer` (updated by `Game.gd._on_turn_started()`) has been removed; `Game.gd` no longer connects to `EventBus.turn_started` at all. `HUD.tscn` is now instanced as a child of `UI` and is the single source of truth for the turn display.

> **Gotcha hit during setup:** `hud.gd extends Control`, but the root node of `HUD.tscn` was left as a `Node2D` (its default when first created) — Godot refuses to attach a `Control`-typed script to a `Node2D` ("Script inherits from native type 'Control', so it can't be assigned to an object of type 'Node2D'"). Fixed by changing the scene's root node type to `Control` via right-click → Change Type in the editor. Worth remembering for `ScoreBoard.tscn` too, or any future runtime-built UI scene — the root node's actual type must match whatever the script `extends`.

### `score_board.gd` (`scenes/ui/ScoreBoard.tscn`)
**Implemented (2026-06-27).** Was a fully empty stub (`_ready()`/`_process()` both just `pass`); now builds one row per player at runtime in `_ready()` — an `HBoxContainer` with a `▶` marker `Label` and a `"Name: score"` `Label` tinted to that player's color. Same "build everything in code, scene has only root + script" approach as `hud.gd`.

- Listens to `EventBus.score_changed(player_index, new_score)` — **new signal, added to `EventBus.gd`** — to update a single row reactively.
- Listens to `EventBus.turn_started` to move the `▶` marker to whoever's currently up.
- Requires `GameManager.add_score()` to emit `EventBus.score_changed(player_index, players[player_index]["score"])` after mutating the score — this had to be added alongside the signal itself, since `add_score()` previously only mutated state silently.
- Instanced as a child of `Game.tscn`'s `UI` layer alongside `HUD`, positioned to avoid overlapping it.

### `game_over_screen.gd` (`scenes/ui/GameOverScreen.tscn`)
**Added (2026-06-28).** Same "build everything at runtime" approach as `hud.gd`/`score_board.gd` — root `Control` + script only, no manually-placed children.

- `_ready()`: builds a full-screen dim `ColorRect` (alpha `0.85`), a centered `VBoxContainer` with a headline `Label`, one score row per player (reusing the same row style as `ScoreBoard`, winner's row rendered larger), and a "Play Again" `Button`. Starts `visible = false` and `mouse_filter = MOUSE_FILTER_STOP` (so it can't block clicks while hidden, but does once shown).
- Connects to `EventBus.game_over(winner_index)` — sets the headline to `"%s Wins!"` colored to match the winner, populates every player's final score, then sets `visible = true`.
- "Play Again" calls `GameManager.reset_for_new_game()` then `get_tree().change_scene_to_file("res://scenes/Game.tscn")` — a full scene reload rather than an in-place reset, to avoid any chance of leftover token positions/sprites carrying over from the finished game.
- **Scope clarification:** this is the *board's* game-over screen, not a per-minigame results screen. `EventBus.game_over` is only ever emitted from `State_EndTurn.gd` (or redundantly from `GameManager.add_score()` — see below) when a player's token reaches the final board tile — never from inside a minigame. Since `SceneLoader.go_to_minigame()` fully destroys `Game.tscn` (and everything instanced inside it, including this screen) while a minigame is active, it is expected and correct that this screen cannot appear during a minigame; it only exists again once `SceneLoader.return_to_board()` rebuilds the board scene.
- Must be instanced as a child of `Game.tscn`'s `UI` layer (same as `HUD`/`ScoreBoard`) for `_ready()` to ever run and connect to the signal — confirmed `GameManager.gd` already has working `_get_winner()` and `reset_for_new_game()` implementations as of 2026-06-28, so if the screen still isn't appearing after a normal full game, the instancing step is the first thing to check.

> **Known redundancy (not yet cleaned up):** `GameManager.add_score()` independently re-checks `_is_game_over()`/emits `game_over` itself, duplicating what `State_EndTurn.gd` already does correctly via the FSM. Harmless today since both paths compute the same winner the same way, but it's a second, less-controlled trigger path that's worth removing once someone's looking at `GameManager.gd` for other reasons — having only one place that can ever emit `game_over` would be safer long-term.

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
- ~~**Luksong Baka input bug**~~ **FIXED (2026-06-24).** See Minigame System section above.
- ~~**Dual tile type resolvers**~~ **FIXED (2026-06-23).** See Minigame System section above.
- ~~**SceneLoader silent failure on minigame load**~~ **FIXED (2026-06-24).** Root cause: on-disk `.tscn` filename for LuksongBaka did not exactly match the `to_snake_case()`-derived path, causing `change_scene_to_file()` to silently fail with no thrown error and no scene swap. Fixed by correcting the filename and adding explicit error-code checking + print instrumentation in `SceneLoader.go_to_minigame()` / `_start_minigame_deferred()` (kept in place for future debugging). **Process takeaway:** any new minigame's filename must be manually verified against the FileSystem dock before being added to `Constants.MINIGAMES` — see the dedicated gotcha note in the Minigame System section.
- ~~**PlayerToken visual reset on minigame return**~~ **FIXED (2026-06-24), REGRESSED (branch merge, 2026-06-26), RE-FIXED (2026-06-26).** See "PlayerToken Visual Reset on Minigame Return" under Design Decisions & Gotchas — this is the same bug coming back via a silent merge, not a new bug.
- **Random minigame crashes** — `Utils.random_minigame()` can still return minigame IDs without scenes if `Constants.MINIGAMES` is ever expanded carelessly (`LangitLupa` has a scene but is deliberately withheld — see below; pending playtest before it joins rotation). `BatoLata` and `AgawBase` have been cut from the project (2026-06-25) and will not be implemented — `Utils.random_minigame()` no longer needs to account for them.

### Stubs / Unimplemented
- `State_EndTurn._save_state()` — TODO: persistence layer
- `State_EndTurn._update_ui()` — TODO: scoreboard refresh signal
- `player.gd` — empty stub
- `TilePath.gd` — empty stub
- Minigames: `LangitLupa` — not yet in active rotation, pending playtest. `BatoLata` and `AgawBase` are **cut from the project** (2026-06-25), see Planned Minigames.
- `Enums.TileType.SARI_SARI` — defined but never assigned to any tile
- Board character sprites — **wired in (2026-06-24).** See "Player Token System" for the AnimatedSprite2D/`_build_frames()` implementation. Note the on-disk asset folder path needs verification — see the flagged mismatch in that section.
- Minigame character assets — present but not yet wired into any minigame scene

### Architecture Decisions Pending
- ~~**Game Over screen** — FSM halts at `State_EndTurn` on game over; no UI or transition is implemented~~ **RESOLVED (2026-06-28)** — see `game_over_screen.gd` under UI System.
- **Local multiplayer input** — all 4 players share one screen/keyboard; no network/controller support
- **LAN multiplayer (planned)** — `LangitLupa` was deliberately built around a single `local_player_index` (currently hardcoded to `0`) controlling one set of generic movement keys (`move_up/down/left/right`), anticipating that each LAN client will eventually control only its own player. This pattern is not yet wired to real networking and should be treated as the template for retrofitting movement-based minigames once LAN play exists.
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

### PlayerToken Visual Reset on Minigame Return (FIXED 2026-06-24, REGRESSED 2026-06-26, RE-FIXED 2026-06-26)
`PlayerToken.setup()` previously hardcoded the token's spawn position to tile 0 unconditionally. This was fine at game start, but `Game.tscn` is destroyed and rebuilt every time a minigame scene loads/returns (per `SceneLoader`), which means `Game.gd._spawn_tokens()` runs again and calls `setup()` again on fresh `PlayerToken` instances after every minigame.

**Symptom:** after returning from a minigame, all player tokens visually snapped back to tile 0, even though `GameManager.players[i]["tile_index"]` correctly still held each player's real position (this data survives scene changes since `GameManager` is an autoload). On the next roll, the token would visibly "travel" from tile 0 to the correct destination, since `move_to()` correctly read the real `tile_index` — masking the bug as something that looked self-correcting rather than obviously wrong.

**Original fix (2026-06-24):** `setup()` read the player's actual current `tile_index` from `GameManager.players[index]["tile_index"]` and placed the token there immediately (snap, no animation) instead of hardcoding tile 0.

**Regression (branch merge, 2026-06-26):** the sprite-wiring branch (see "Sprites wired in" above) had forked from before this fix landed, and rewrote `setup()` to add `_build_frames()`/sprite setup using its own `global_position = board_ref.get_tile_position(0) + ...` line. Since both branches touched the same function for unrelated reasons, Git's line-based merge produced no conflict markers — it just silently kept a version of `setup()` that snapped back to tile 0 again. Caught by re-reading the merged file line-by-line rather than by any tooling; the bug itself produces no error, same as its first occurrence.

**Re-fix (2026-06-26):** restored the `GameManager.players[index]["tile_index"]` read, now combined with `board_ref.get_tile_position(current_tile)` (signature changed to use `global_position`/`board_ref` after the sprite rewrite, so the fix had to be re-applied in the new shape of the function, not just pasted back verbatim):
```gdscript
var current_tile: int = GameManager.players[index]["tile_index"]
global_position = board_ref.get_tile_position(current_tile) + Utils.token_offset(player_index)
```

> **Process takeaway:** a clean (no-conflict) merge is not proof that both branches' fixes survived. When two branches edit the same function for different reasons, Git can merge them without complaint while still dropping one side's actual behavior. Worth a quick side-by-side read of any function both branches touched, even after a "successful" merge.

### Mini-game Movement & Input Scope (LangitLupa)
`LangitLupa` is the first minigame requiring continuous movement input rather than a single button press (`LuksongBaka`, `SackRace`). Since the project plans LAN multiplayer (each physical device controls only its own local player), per-player movement keymaps were deliberately **not** added. Instead, a single generic WASD-style input set (`move_up`, `move_down`, `move_left`, `move_right`) drives only `local_player_index` (currently hardcoded to `0` as a placeholder — TODO: replace with real per-client player assignment once LAN networking exists). The other 3 participating players are currently driven by a temporary wandering-AI stub (see `langit_lupa.gd` — `_init_ai()`, random direction changes every 1.5s, bounces off screen edges) purely so tagging/area logic can be solo-tested before LAN input replaces it.

### Area Size — Single Source of Truth (LangitLupa)
Initially, each elevated-area `ColorRect`'s visual size (set by hand in the editor) and its gameplay detection radius (`AREA_RADIUS` constant in script) were two independently-edited values that could silently drift out of sync. Refactored so `AREA_RADIUS` is now derived from a single `AREA_SIZE` constant (`AREA_RADIUS := AREA_SIZE * 0.5`), and `_spawn_areas()` sets each ColorRect's `size` programmatically at spawn time rather than relying on manual editor edits. This also surfaced and fixed a related alignment bug: `ColorRect.position` is the rect's **top-left corner**, but all distance/safety-check math in the script treats `area.pos` as the **center point** — `_spawn_areas()` now offsets `rect.position = pos - rect.size / 2.0` so the visual rect is actually centered on the logical safe-zone point instead of being offset by half its width/height.

### Minigame Result Handling Moved to GameManager (2026-06-27)
**Symptom:** after any minigame, it was still the same player's turn — `current_player_index` never advanced, even though the minigame itself completed and returned to the board normally.

**Root cause:** `State_TileEvent._handle_minigame()` called `SceneLoader.go_to_minigame()` and then `_wait_for_minigame_result.call_deferred()`, intending to `await EventBus.minigame_finished` and apply scores + transition to `State_EndTurn` once the minigame was done. But `go_to_minigame()` internally calls `change_scene_to_file()`, which destroys the entire `Game.tscn` tree — including the `State_TileEvent` node itself — at the next idle frame. The explicit `call_deferred()` for `_wait_for_minigame_result` gets queued *after* the scene-change's own deferred work, so by the time it would run, the node it's attached to no longer exists. The coroutine never actually starts awaiting anything; nothing ever applies the result.

**Fix:** moved this responsibility to `GameManager`, since autoloads survive scene changes. `GameManager._ready()` connects directly to `EventBus.minigame_finished`; `_on_minigame_finished(scores)` applies the scores and increments `current_player_index`. Because `BaseMinigame._finish()` emits `minigame_finished` *before* calling `SceneLoader.return_to_board()`, `GameManager` is guaranteed to still be "between" the minigame ending and the board scene rebuilding — exactly the window where it needs to act. By the time the fresh `StateMachine` boots up at `State_StartTurn`, `current_player_index` has already moved on.

> **Process takeaway:** any FSM/coroutine logic that needs to survive `change_scene_to_file()` has to live on an autoload, not on a node inside the scene being replaced — no matter how carefully the `await`/`call_deferred` ordering looks on paper. This is the same root category of bug as the LuksongBaka silent scene-load failure and the PlayerToken visual-reset regression: a destructive scene change quietly invalidating in-flight state with no thrown error.

### Tile Index Persistence
`GameManager.players[i]["tile_index"]` is **no longer pre-set by `State_Moving` before the animation runs.** Earlier versions set the destination `tile_index` immediately in `State_Moving.enter()`, *before* the token actually animated — this caused `PlayerToken.move_to()` to see `current_idx == target_idx` immediately, emit `movement_finished` synchronously, before `State_Moving`'s `await` was even reached. The signal fired into the void and the FSM hung forever on every move.

**Current (correct) behavior:** `State_Moving.enter()` only *computes* the target tile and triggers the animation via `EventBus.player_moved`. From there, `tile_index` is actually updated twice, by design, not by accident: `player_token.gd`'s `_step_toward()` writes it incrementally at each hop as the token visually advances tile-by-tile, and `_animate_and_advance()` in `State_Moving` writes it once more at the very end, after the per-player-filtered `movement_finished` signal confirms the animation actually completed. The second write is defensive redundancy (guarantees the final value is correct even if a hop-level write were ever skipped), not the *only* write. `State_TileEvent` reads `tile_index` after this point, so timing is safe either way.

### Movement Completion — Combined Fix (lambda capture + signal theft)
`State_Moving._animate_and_advance()` previously used a raw `await EventBus.movement_finished`, which had two compounding bugs, found and fixed by two different people on two different passes:

1. **Lambda capture-by-value:** GDScript 4 lambdas capture primitives (`bool`, `int`, `float`) by value, not by reference. A naive `var done := false` checked inside a lambda would never actually update the outer scope's `done`. Fixed by using `var done := [false]` (an `Array`, which *is* captured by reference) and mutating `done[0]` inside the lambda.
2. **Signal theft:** Since `EventBus.movement_finished` is global, if multiple players' tokens are mid-animation simultaneously, a raw `await EventBus.movement_finished` could resolve on the **wrong player's** signal emission, since the first emission of any kind satisfies the await.

**Final combined fix** (current code, verified correct):
```gdscript
var done := [false]
var _handler := func(finished_idx: int) -> void:
    if finished_idx == player_idx:
        done[0] = true
EventBus.movement_finished.connect(_handler, CONNECT_ONE_SHOT)
while not done[0]:
    await get_tree().process_frame
if EventBus.movement_finished.is_connected(_handler):
    EventBus.movement_finished.disconnect(_handler)
```
This filters the signal by `player_idx` before considering the wait satisfied, and uses a poll loop instead of a raw await so the filtering logic can run on each frame.

> **Known minor gap:** the `while not done[0]` poll loop has no timeout. If a token's animation ever silently fails to emit `movement_finished` for its player index, this will poll forever rather than fail loudly. Not yet a problem in practice, but worth a defensive timeout if movement reliability issues ever appear.

---

## Recent Bug Fixes

| Date | Commit | Fix |
|------|--------|----- |
| 2026-06-22 | `a6e4b68` | Added DEVLOG.md |
| 2026-06-22 | `809e83c` | Fixed Player 2+ turn freeze — GDScript lambda captured `bool done` by value; switched to `Array[bool] done` for shared reference |
| 2026-06-22 | `8524e1f` | Fixed turn freeze after Player 2 — open `await` loop in State_Moving stole `movement_finished` signals meant for later players; replaced with one-shot lambda + process_frame poll |
| 2026-06-22 | `aa6dd23` | Fixed GDScript warnings — unused params (`_delta`, `_gm`, `_player_idx`), duplicate `call_deferred`, Tile.tscn UID mismatch, `@warning_ignore` on EventBus signals |
| 2026-06-22 | `a774b3a` | Removed `copilot-advanced` addon; added `LICENSE` and `README.md` |
| 2026-06-23 | *(pending)* | Reverted PlayerToken to ColorRect placeholder — PNG spritesheets not yet exported by team. Removed AsepriteWizard/.tres references from PlayerToken.tscn, player_token.gd, and Game.gd. |
| 2026-06-24 | *(pending)* | **(parallel work)** Wired PNG spritesheets into PlayerToken — ColorRect → AnimatedSprite2D; `_build_frames()` slices a 4096×1024 spritesheet into 4×1024px AtlasTexture frames at runtime; no `.tres` bake needed. Pixsquare export unblocked this after the 6/23 revert above. |
| 2026-06-24 | *(pending)* | **(parallel work)** Added directional walk animation to PlayerToken — `_get_direction_animation()` maps tile index to board segment; `_step_toward()` switches `walkRight`/`walkFront`/`walkLeft`/`walkBack` per hop; `_build_frames()` extended to load all 4 directional PNGs. |
| 2026-06-23 | *(pending)* | Fixed dual tile-type resolver bug — added `GameManager.board_ref`, set by `Game.gd`, so `State_TileEvent._get_tile_type()` delegates to the real `board.gd.get_tile_type()` instead of an independent `% 5` placeholder formula. Verified via debug prints. |
| 2026-06-23 | *(pending)* | Found leftover unconditional `_try_jump(0)` line still present inside `luksong_baka.gd`'s `_unhandled_input` loop, left over from a partial merge of the per-player input fix. Caused Player 1 to receive extra phantom jump attempts on every keypress, scaling with the number of alive players. Fix: delete the stray line; the per-player loop above it is already correct standalone. |
| 2026-06-23 | *(pending)* | Confirmed `Constants.MINIGAMES` still includes all 5 IDs while only `LuksongBaka` has an implemented scene. Landing on a GAME_TRIGGER tile that randomly selects `AgawBase`/`BatoLata`/`LangitLupa`/`SackRace` causes `SceneLoader` to fail loading the scene and permanently stalls `State_TileEvent`'s `await EventBus.minigame_finished`. Recommended temporary fix (not yet applied): restrict `Constants.MINIGAMES = ["LuksongBaka"]` until the other 4 are implemented. |
| 2026-06-24 | *(pending)* | Found and fixed the actual root cause of minigames never triggering visually: the on-disk `.tscn` filename for LuksongBaka didn't exactly match the path `SceneLoader` constructed via `to_snake_case()`. `change_scene_to_file()` was failing silently — no thrown error, scene stayed on `Game` (confirmed via Remote scene tree) — leaving `State_TileEvent` stuck forever awaiting a signal that would never fire. Diagnosed via explicit error-code checks and print instrumentation added to `SceneLoader.gd`. |
| 2026-06-24 | *(pending)* | Deleted the stray unconditional `_try_jump(0)` line inside `luksong_baka.gd`'s `_unhandled_input` loop (left over from a prior partial merge). Verified live that only the correct player jumps per keypress. |
| 2026-06-24 | *(pending)* | Fixed `PlayerToken.setup()` hardcoding spawn position to tile 0 on every spawn. Since `Game.tscn` (and therefore all `PlayerToken` instances) is rebuilt on every minigame return, this caused tokens to visually snap back to the start tile after every minigame even though `GameManager`'s tracked `tile_index` was correct. `setup()` now reads the real `tile_index` from `GameManager` and snaps the token there immediately instead of defaulting to tile 0. |
| 2026-06-24 | *(pending)* | Implemented `SackRace` minigame (mash-to-race mechanic) end-to-end, including scene/script naming verified against the `to_snake_case()` lesson above, and added it to `Constants.MINIGAMES`. |
| 2026-06-24 | *(pending)* | Implemented `LangitLupa` minigame (real-time tag with elevated safe-zones) including movement input, area spawn/unsafe-flagging logic, IT-blocked-from-areas rule, and a temporary wandering-AI stub for non-local players (no LAN networking yet). Not yet added to `Constants.MINIGAMES` pending a full playtest. |
| 2026-06-25 | *(pending)* | Cut `BatoLata` (Labay Lata) and `AgawBase` from the planned minigame roster. Two design/prototype passes on `BatoLata` (lane-based fixed-position throwing, then a free-movement WASD + AI-opponent rebuild) were completed before the decision to drop it; neither was merged. Project moves forward with the existing 3-minigame set (`LuksongBaka`, `SackRace`, `LangitLupa`). |
| 2026-06-26 | *(pending)* | Merged the game-logic branch and the sprite/art branch. Confirmed the real asset path is `res://assets/characters/board_characs/` (and `minigame_characs/`) via the FileSystem dock, resolving the naming mismatch flagged after the merge. Also found and re-fixed a regression: the merge silently reintroduced the "PlayerToken visual reset on minigame return" bug (fixed 2026-06-24) because the sprite branch's rewritten `setup()` had forked from before that fix and Git merged the two versions of the function with no conflict. See "PlayerToken Visual Reset on Minigame Return" under Design Decisions & Gotchas. |
| 2026-06-26 | *(pending)* | Found `langit_lupa.gd` contained `bato_lata.gd`'s content (wrong node lookups, BatoLata-specific logic) despite `LangitLupa.tscn` having the correct real scene tree — restored the correct script. |
| 2026-06-27 | *(pending)* | Fixed `Utils` autoload/static conflict. Godot 4.6 errors on a script being both an autoload singleton and declaring a matching `class_name`. Removed `static` from all three functions in `utils.gd` instead (keeping the autoload registration as-is, per project preference) — `Utils.foo()` now works as a plain instance call on the autoload. |
| 2026-06-27 | *(pending)* | Found and fixed a second, unrelated cause of the identical-looking "cannot call non-static function" error: `player_token.gd` had `const Utils = preload("res://scripts/utils.gd")` shadowing the global autoload within that file only. Deleted the local preload. |
| 2026-06-27 | *(pending)* | Fixed the "still the same player's turn after a minigame" bug by moving score application + `current_player_index` advancement from `State_TileEvent` (destroyed before it can act — see Design Decisions & Gotchas) into a new `GameManager._on_minigame_finished()` handler connected to `EventBus.minigame_finished`. |
| 2026-06-27 | *(pending)* | Implemented `HUD.tscn`/`hud.gd` and `ScoreBoard.tscn`/`score_board.gd` (previously an empty stub) — both build their UI at runtime in `_ready()`. Removed the duplicate `TurnLabel` from `Game.tscn`/`Game.gd`. Added `EventBus.score_changed` signal, emitted from `GameManager.add_score()`. |
| 2026-06-27 | *(pending)* | Added a shared pre-round intro to `BaseMinigame.gd` — optional announcement text, then a dimmed-background 3-2-1 countdown, built entirely at runtime (`run_intro()`). Wired into `LangitLupa` (announces who is IT) and `SackRace` (countdown only). `LuksongBaka` calls it too but still has its own separate countdown running alongside it — not yet deduplicated. |
| 2026-06-27 | *(pending)* | LangitLupa: added a dash mechanic (3× speed for 0.15s, 5s cooldown, both human and AI) with a runtime-built radial cooldown indicator per player. Added a fix so players no longer spawn already standing inside a safe elevated area. Added an early-win condition so the round ends the instant IT has tagged every other player, instead of always running the full 60s. |
| 2026-06-27 | *(pending)* | Fixed the marker-snap-back visual bug in `LuksongBaka` — survivors' markers stayed at their previous round's end position throughout the countdown, then snapped to start the instant the sweep began, because `_start_countdown()` reset the zone/status but never the marker's position. Added the missing reset to the same loop. |
| 2026-06-27 | *(pending)* | Reworked scoring across all three minigames to match the finalized design spec, and fixed a double-scoring bug present in **all three** (`GameManager.add_score()` called directly *and* the same scores dict passed through `_finish()`, which already applies it via the new `GameManager._on_minigame_finished()` hook — doubling every point awarded). Added `BaseMinigame.compute_placement_scores()`, a shared tie-aware placement algorithm now used by both `LuksongBaka` and `SackRace`. Rewrote `LangitLupa`'s scoring formula (IT = tagged count, survivors = survivor count each, tagged = 0) to match spec exactly. |
| 2026-06-27 | *(pending)* | Fixed a repeat-scoring bug in `LangitLupa` distinct from the formula bug above: `_end_game()` wasn't setting `gameplay_locked`, so `_process()` re-armed itself every frame for the full 2-second `_finish()` delay and kept re-triggering `_end_game()` (and therefore re-emitting `minigame_finished`) dozens of times per round-end, producing wildly inflated scores with no errors thrown. Fixed by having `_end_game()` set `gameplay_locked = true` immediately. Confirmed `SackRace` and `LuksongBaka` don't share this bug — both already guard cleanly. |
| 2026-06-28 | *(pending)* | Added `GameOverScreen.tscn`/`game_over_screen.gd` — full-screen results overlay listening to `EventBus.game_over`, with a "Play Again" button that resets `GameManager` state and reloads `Game.tscn`. Confirmed `GameManager.gd` already has correct `_get_winner()` and `reset_for_new_game()` implementations. Clarified scope: this screen belongs to the board (`Game.tscn`), not to individual minigames — it's destroyed along with the rest of `Game.tscn` whenever a minigame is active, by design, same as everything else in that scene tree. |
| 2026-06-28 | *(pending)* | Fixed the `LuksongBaka` start-of-game freeze (see "Implemented Minigame: `LuksongBaka`" above) — a side effect of an earlier attempt to dedupe its double-countdown that removed the call to `_start_countdown()` without anything left to replace it. Properly deduped this time: `run_intro()` provides the one-time pre-game countdown, `_start_countdown()` no longer has its own separate text countdown. |
| 2026-06-28 | *(pending)* | Overhauled `LangitLupa`'s elevated-area system: detection now uses an exact square-bounds check (`_point_in_area()`) instead of a circle that didn't match the visible square's corners; unsafe areas now flash briefly then disappear instead of flashing forever; player spawning switched from random-with-rerolls to a fixed center cluster (`SPAWN_CENTER` + `SPAWN_OFFSETS`), with areas now spawned afterward and rerolled away from those known spawn points. |
| 2026-06-29 | *(pending)* | Added a post-minigame results screen to `BaseMinigame._finish()` — previously just a blank 2s wait before returning to the board. Now shows a 2s winner announcement (`run_results()`'s phase 1) followed by a 2s per-player points breakdown (phase 2), both built at runtime in the same dimmed-overlay style as `run_intro()`. Applies to all three minigames for free since they all funnel through `_finish()`. |

---

## Planned Minigames

| ID | Status | Description |
|----|--------|-------------|
| `LuksongBaka` | ✅ Implemented | Jump the rope timing minigame |
| `SackRace` | ✅ Implemented | Mash-to-race sack race |
| `LangitLupa` | ✅ Implemented | Real-time tag with elevated safe-zones; scene/script complete, pending playtest + LAN movement |
| `BatoLata` (Labay Lata) | 🚫 Cut (2026-06-25) | Hit-the-can-and-run minigame; two prototype passes (lane-based, then free-movement w/ AI) were built and discarded before the decision to cut. No longer planned. |
| `AgawBase` | 🚫 Cut (2026-06-25) | Base stealing — never started, no longer planned. |
