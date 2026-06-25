# Pinoy Party — Developer Log

> **Purpose:** This file is a living reference document for AI-assisted development. It describes the current architecture, file structure, known issues, and design decisions so that any AI assistant can pick up context without reading every file from scratch.

**Engine:** Godot 4.6 (GDScript, Forward Plus renderer, D3D12 on Windows)  
**Branch:** `Lancer` (active development branch, pushes to `Zephyrdoestech/Pinoy-Party`)  
**Last Updated:** 2026-06-25

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
| `MINIGAMES` | `["LuksongBaka", "SackRace"]` | Registered minigame IDs in active rotation. `LangitLupa` has a complete scene/script but is deliberately withheld pending playtest (see Known Issues). `BatoLata`/"Labay Lata" and `AgawBase` have been **cut from the project** (2026-06-25) — see Planned Minigames. |

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

- `setup(index, board)` — assigns `player_index`, stores `board_ref`, sets `ColorRect.color` from `GameManager.players[i]["color"]`, positions at tile 0
- `move_to(target_tile_index)` — reads current `tile_index` from GameManager, calls `_step_toward`
- `_step_toward(current, target)` — recursively tweens one tile at a time (0.2s per hop via `Constants.MOVE_STEP_DURATION`)
  - At each step: updates `GameManager.players[player_index]["tile_index"]`
  - On arrival: emits local `movement_finished(player_index)` signal

The local `movement_finished` signal is relayed to `EventBus.movement_finished` by `Game.gd._on_token_movement_finished()`.

### `PlayerToken.tscn` node structure
```
PlayerToken (Node2D)   ← player_token.gd
├── ColorRect          ← 50×50px placeholder, color set from GameManager.players[i]["color"]
└── Label              ← debug label (offset 0–40×0–23)
```

> **⚠️ Sprite blocked — PNG spritesheets not yet available.** See Known Issues.

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

> **⚠️ Confirmed failure mode (2026-06-24):** This naming mismatch is not just theoretical — it caused a real, hard-to-diagnose bug. The actual `.tscn` file on disk did not match the `to_snake_case()` output exactly, so `get_tree().change_scene_to_file(path)` silently failed: it returned without throwing a catchable error in the surrounding code, `current_scene` remained `Game` (confirmed via the Remote scene tree while paused), and `State_TileEvent` was left permanently stuck awaiting `EventBus.minigame_finished` with zero console output after the `"Loading minigame scene"` print. From the player's perspective, landing on a `GAME_TRIGGER` tile appeared to do nothing — the Roll Dice button stayed clickable and turns kept silently advancing functionally, but the minigame never appeared. **Diagnosis required:** adding a `push_error` check on `change_scene_to_file()`'s return code, instrumenting `_start_minigame_deferred()` with a print at its very first line, and manually visually comparing the on-disk filename against the constructed path character-by-character in the FileSystem dock. **Lesson:** always verify the exact on-disk filename for every new minigame scene before adding it to `Constants.MINIGAMES` — do not assume `to_snake_case()` output matches what was actually saved.

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

~~**Known bug in `_unhandled_input`:** always called `_try_jump(0)` regardless of which player pressed.~~ **FIXED (2026-06-24):** The stray unconditional `_try_jump(0)` line (a leftover from a partial merge — see `Recent Bug Fixes`) has been deleted. The per-player loop (`for player_idx in alive_players: ... if event.is_action_pressed(action): _try_jump(player_idx)`) is now the only call path and has been verified correct via live testing.

**Score integration:** Uses `GameManager.add_score()` during gameplay for "Cleared!" jumps. The `_end_game()` `scores` dictionary only tracks the +3 survivor bonus; the per-round `+1` points are already applied live.

### Implemented Minigame: `SackRace`

A timed mash-race minigame. All 4 players race simultaneously on parallel tracks.

**Mechanics:**
- Each press of a player's jump button (`p1_jump`–`p4_jump`) advances their sack a fixed distance (`HOP_DISTANCE`)
- First to reach `FINISH_DISTANCE` (20 hops) wins; race also ends via `RACE_TIMEOUT` (15s) if nobody finishes, ranking remaining players by progress
- Scoring: finish order awards `3, 2, 1, 0` points (1st through 4th) via `GameManager.add_score()`
- Visual: 4 `ColorRect` nodes under `Tracks/Player 1`–`Player 4` move along the X axis (`HOP_PIXELS` per hop); a `TimerLabel` shows live countdown

**Folder/naming:** `res://scenes/minigames/SackRace/sack_race.gd` + `SackRace.tscn` (root node named `SackRace`). Filenames manually verified against `to_snake_case()` output before being added to `Constants.MINIGAMES`, per the lesson learned from the LuksongBaka scene-path bug above.

### Implemented Minigame: `LangitLupa`

A real-time tag minigame — meaningfully different from the other two since it requires continuous movement rather than single-button input, and currently only supports one human-controlled player (`local_player_index`) with the rest driven by a temporary wandering-AI stub. See "Mini-game Movement & Input Scope" and "Area Size" sections under Design Decisions & Gotchas for full detail.

**Mechanics:**
- One random participating player is designated "IT" (`it_player`), shown via a distinct color and `ItLabel`
- `NUM_AREAS` (6) "elevated areas" spawn at random positions each round; non-IT players are safe from tagging while standing inside one
- An area becomes permanently `unsafe` (flagged, flashes red, does not refresh) once any non-IT player has continuously occupied it for `AREA_SAFE_DURATION` (4s)
- IT is blocked from ever stepping inside an area (checked in movement resolution)
- IT tags any non-elevated, non-safe player within `TAG_RADIUS` via proximity check each frame
- Round ends after `ROUND_DURATION` (60s); survivors (non-IT, untagged) each score 2 points; IT scores `2 × number tagged` if anyone was caught
- A 3-second "Get ready" countdown (`COUNTDOWN_DURATION`) blocks movement/tagging at round start

**Folder/naming:** `res://scenes/minigames/LangitLupa/langit_lupa.gd` + `LangitLupa.tscn` (root node named `LangitLupa`).

pending full live playtest of the area/tag logic via the AI stub, and pending real LAN player movement to replace `local_player_index`'s current hardcoded value of `0`.

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
- ~~**Luksong Baka input bug**~~ **FIXED (2026-06-24).** See Minigame System section above.
- ~~**Dual tile type resolvers**~~ **FIXED (2026-06-23).** See Minigame System section above.
- ~~**SceneLoader silent failure on minigame load**~~ **FIXED (2026-06-24).** Root cause: on-disk `.tscn` filename for LuksongBaka did not exactly match the `to_snake_case()`-derived path, causing `change_scene_to_file()` to silently fail with no thrown error and no scene swap. Fixed by correcting the filename and adding explicit error-code checking + print instrumentation in `SceneLoader.go_to_minigame()` / `_start_minigame_deferred()` (kept in place for future debugging). **Process takeaway:** any new minigame's filename must be manually verified against the FileSystem dock before being added to `Constants.MINIGAMES` — see the dedicated gotcha note in the Minigame System section.
- ~~**PlayerToken visual reset on minigame return**~~ **FIXED (2026-06-24).** See "PlayerToken Visual Reset on Minigame Return" under Design Decisions & Gotchas.
- **Random minigame crashes** — `Utils.random_minigame()` can still return minigame IDs without scenes if `Constants.MINIGAMES` is ever expanded carelessly (`LangitLupa` has a scene but is deliberately withheld — see below; pending playtest before it joins rotation). `BatoLata` and `AgawBase` have been cut from the project (2026-06-25) and will not be implemented — `Utils.random_minigame()` no longer needs to account for them.

### Stubs / Unimplemented
- `State_EndTurn._save_state()` — TODO: persistence layer
- `State_EndTurn._update_ui()` — TODO: scoreboard refresh signal
- `score_board.gd` — empty stub
- `player.gd` — empty stub
- `TilePath.gd` — empty stub
- `ScoreBoard.tscn` — not connected to game scene
- `HUD.tscn` — exists but not added to `Game.tscn`
- Minigames: `LangitLupa` — not yet in active rotation, pending playtest. `BatoLata` and `AgawBase` are **cut from the project** (2026-06-25), see Planned Minigames.
- `Enums.TileType.SARI_SARI` — defined but never assigned to any tile
- Board character `.aseprite` assets in `assets/board_characters/` — **not yet wired**. AsepriteWizard bake approach dropped (team uses Pixsquare on iPad which cannot produce `.tres` SpriteFrames). PNG spritesheet export from Pixsquare is the required next step before sprites can be wired. See Known Issues.
- Minigame character assets in `assets/minigame_characters/` — present but not yet wired into any scene
- **Board token sprites blocked** — `assets/board_characters/` contains only `.aseprite` files. Team must export PNG spritesheets from Pixsquare for each character before `PlayerToken` can display character art. Current placeholder is a solid-color `ColorRect`.

### Architecture Decisions Pending
- **Game Over screen** — FSM halts at `State_EndTurn` on game over; no UI or transition is implemented
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

### PlayerToken Visual Reset on Minigame Return (FIXED 2026-06-24)
`PlayerToken.setup()` previously hardcoded the token's spawn position to tile 0 unconditionally. This was fine at game start, but `Game.tscn` is destroyed and rebuilt every time a minigame scene loads/returns (per `SceneLoader`), which means `Game.gd._spawn_tokens()` runs again and calls `setup()` again on fresh `PlayerToken` instances after every minigame.

**Symptom:** after returning from a minigame, all player tokens visually snapped back to tile 0, even though `GameManager.players[i]["tile_index"]` correctly still held each player's real position (this data survives scene changes since `GameManager` is an autoload). On the next roll, the token would visibly "travel" from tile 0 to the correct destination, since `move_to()` correctly read the real `tile_index` — masking the bug as something that looked self-correcting rather than obviously wrong.

**Fix:** `setup()` now reads the player's actual current `tile_index` from `GameManager.players[index]["tile_index"]` and places the token there immediately (snap, no animation) instead of hardcoding tile 0.

### Mini-game Movement & Input Scope (LangitLupa)
`LangitLupa` is the first minigame requiring continuous movement input rather than a single button press (`LuksongBaka`, `SackRace`). Since the project plans LAN multiplayer (each physical device controls only its own local player), per-player movement keymaps were deliberately **not** added. Instead, a single generic WASD-style input set (`move_up`, `move_down`, `move_left`, `move_right`) drives only `local_player_index` (currently hardcoded to `0` as a placeholder — TODO: replace with real per-client player assignment once LAN networking exists). The other 3 participating players are currently driven by a temporary wandering-AI stub (see `langit_lupa.gd` — `_init_ai()`, random direction changes every 1.5s, bounces off screen edges) purely so tagging/area logic can be solo-tested before LAN input replaces it.

### Area Size — Single Source of Truth (LangitLupa)
Initially, each elevated-area `ColorRect`'s visual size (set by hand in the editor) and its gameplay detection radius (`AREA_RADIUS` constant in script) were two independently-edited values that could silently drift out of sync. Refactored so `AREA_RADIUS` is now derived from a single `AREA_SIZE` constant (`AREA_RADIUS := AREA_SIZE * 0.5`), and `_spawn_areas()` sets each ColorRect's `size` programmatically at spawn time rather than relying on manual editor edits. This also surfaced and fixed a related alignment bug: `ColorRect.position` is the rect's **top-left corner**, but all distance/safety-check math in the script treats `area.pos` as the **center point** — `_spawn_areas()` now offsets `rect.position = pos - rect.size / 2.0` so the visual rect is actually centered on the logical safe-zone point instead of being offset by half its width/height.

### Tile Index Persistence
`GameManager.players[i]["tile_index"]` is **no longer pre-set by `State_Moving` before the animation runs.** Earlier versions set the destination `tile_index` immediately in `State_Moving.enter()`, *before* the token actually animated — this caused `PlayerToken.move_to()` to see `current_idx == target_idx` immediately, emit `movement_finished` synchronously, before `State_Moving`'s `await` was even reached. The signal fired into the void and the FSM hung forever on every move.

**Current (correct) behavior:** `State_Moving.enter()` only *computes* the target tile and triggers the animation via `EventBus.player_moved`. `tile_index` is written exactly once, at the end of `_animate_and_advance()`, after the per-player-filtered `movement_finished` signal confirms the animation actually completed. `State_TileEvent` reads `tile_index` after this point, so timing is safe.

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
| 2026-06-23 | *(pending)* | Fixed dual tile-type resolver bug — added `GameManager.board_ref`, set by `Game.gd`, so `State_TileEvent._get_tile_type()` delegates to the real `board.gd.get_tile_type()` instead of an independent `% 5` placeholder formula. Verified via debug prints. |
| 2026-06-23 | *(pending)* | Found leftover unconditional `_try_jump(0)` line still present inside `luksong_baka.gd`'s `_unhandled_input` loop, left over from a partial merge of the per-player input fix. Caused Player 1 to receive extra phantom jump attempts on every keypress, scaling with the number of alive players. Fix: delete the stray line; the per-player loop above it is already correct standalone. |
| 2026-06-23 | *(pending)* | Confirmed `Constants.MINIGAMES` still includes all 5 IDs while only `LuksongBaka` has an implemented scene. Landing on a GAME_TRIGGER tile that randomly selects `AgawBase`/`BatoLata`/`LangitLupa`/`SackRace` causes `SceneLoader` to fail loading the scene and permanently stalls `State_TileEvent`'s `await EventBus.minigame_finished`. Recommended temporary fix (not yet applied): restrict `Constants.MINIGAMES = ["LuksongBaka"]` until the other 4 are implemented. |
| 2026-06-24 | *(pending)* | Found and fixed the actual root cause of minigames never triggering visually: the on-disk `.tscn` filename for LuksongBaka didn't exactly match the path `SceneLoader` constructed via `to_snake_case()`. `change_scene_to_file()` was failing silently — no thrown error, scene stayed on `Game` (confirmed via Remote scene tree) — leaving `State_TileEvent` stuck forever awaiting a signal that would never fire. Diagnosed via explicit error-code checks and print instrumentation added to `SceneLoader.gd`. |
| 2026-06-24 | *(pending)* | Deleted the stray unconditional `_try_jump(0)` line inside `luksong_baka.gd`'s `_unhandled_input` loop (left over from a prior partial merge). Verified live that only the correct player jumps per keypress. |
| 2026-06-24 | *(pending)* | Fixed `PlayerToken.setup()` hardcoding spawn position to tile 0 on every spawn. Since `Game.tscn` (and therefore all `PlayerToken` instances) is rebuilt on every minigame return, this caused tokens to visually snap back to the start tile after every minigame even though `GameManager`'s tracked `tile_index` was correct. `setup()` now reads the real `tile_index` from `GameManager` and snaps the token there immediately instead of defaulting to tile 0. |
| 2026-06-24 | *(pending)* | Implemented `SackRace` minigame (mash-to-race mechanic) end-to-end, including scene/script naming verified against the `to_snake_case()` lesson above, and added it to `Constants.MINIGAMES`. |
| 2026-06-24 | *(pending)* | Implemented `LangitLupa` minigame (real-time tag with elevated safe-zones) including movement input, area spawn/unsafe-flagging logic, IT-blocked-from-areas rule, and a temporary wandering-AI stub for non-local players (no LAN networking yet). Not yet added to `Constants.MINIGAMES` pending a full playtest. |
| 2026-06-25 | *(pending)* | Cut `BatoLata` (Labay Lata) and `AgawBase` from the planned minigame roster. Two design/prototype passes on `BatoLata` (lane-based fixed-position throwing, then a free-movement WASD + AI-opponent rebuild) were completed before the decision to drop it; neither was merged. Project moves forward with the existing 3-minigame set (`LuksongBaka`, `SackRace`, `LangitLupa`). |

---

## Planned Minigames

| ID | Status | Description |
|----|--------|-------------|
| `LuksongBaka` | ✅ Implemented | Jump the rope timing minigame |
| `SackRace` | ✅ Implemented | Mash-to-race sack race |
| `LangitLupa` | ✅ Implemented | Real-time tag with elevated safe-zones; scene/script complete, pending playtest + LAN movement |
| `BatoLata` (Labay Lata) | 🚫 Cut (2026-06-25) | Hit-the-can-and-run minigame; two prototype passes (lane-based, then free-movement w/ AI) were built and discarded before the decision to cut. No longer planned. |
| `AgawBase` | 🚫 Cut (2026-06-25) | Base stealing — never started, no longer planned. |
