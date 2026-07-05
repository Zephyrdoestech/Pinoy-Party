# Pinoy Party — Developer Log

> **Purpose:** This file is a living reference document for AI-assisted development. It describes the current architecture, file structure, known issues, and design decisions so that any AI assistant can pick up context without reading every file from scratch.

**Engine:** Godot 4.6 (GDScript, Forward Plus renderer, D3D12 on Windows)  
**Branch:** `Lancer` (active development branch, pushes to `Zephyrdoestech/Pinoy-Party`)  
**Last Updated:** 2026-07-04 (LangitLupa fully reworked from top-down tag into a side-view platformer with rising flood and goal-touch placement scoring)

---

## Table of Contents
- [Project Overview](#project-overview)
- [Repository Structure](#repository-structure)
- [Autoloads (Singletons)](#autoloads-singletons)
- [LAN Multiplayer Lobby](#lan-multiplayer-lobby)
- [Scene Graph](#scene-graph)
- [State Machine (FSM)](#state-machine-fsm)
- [Board System](#board-system)
- [Player Token System](#player-token-system)
- [Minigame System](#minigame-system)
- [Trivia Tile System](#trivia-tile-system)
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

> **✅ Real player names propagated from lobby (2026-07-02).** `_setup_players()` previously hardcoded `"Player %d"` for every player, ignoring the name typed into `LobbyScreen`. It now calls `NetworkManager.get_player_name(i, "Player %d" % (i + 1))`, a reverse lookup (`player_index_to_peer` → `connected_players[peer_id]["name"]`) with the old hardcoded string kept as the fallback for local/offline play (where no lobby ever ran). Safe with respect to `_setup_players()`'s two call sites — the early autoload-boot call correctly falls through to the fallback since the roster doesn't exist yet, and the later NetworkManager-triggered rebuild picks up real names once the roster has synced. `HUD`, `ScoreBoard`, and the trivia results screen all read names from `GameManager.players[i]["name"]` already, so they picked up real names automatically with no changes of their own needed.

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
| `MINIGAMES` | `["LuksongBaka", "SackRace", "LangitLupa"]` | Registered minigame IDs in active rotation. `LangitLupa` joined the rotation (2026-06-30) after its earlier "pending playtest" hold — the minigame-launch sync work confirmed it loads and scores correctly over LAN, same as the other two. `BatoLata`/"Labay Lata" and `AgawBase` have been **cut from the project** (2026-06-25) — see Planned Minigames. Trivia is a separate `TileType`, not part of this rotation — see "Trivia Tile System". |
| `MOVEMENT_TIMEOUT_SEC` | 5.0 | (2026-07-02) Max wait for `movement_finished` in `State_Moving` before forcing the move to complete anyway — see "Movement Completion" gotcha. |
| `TRIVIA_QUESTIONS_PATH` | `"res://data/trivia_questions.json"` | (2026-07-02) See "Trivia Tile System". |
| `TRIVIA_POINTS` | 1 | (2026-07-02) Points awarded for a correct trivia answer. |
| `TRIVIA_ANSWER_TIME_SEC` | 15.0 | (2026-07-02) Answer window before auto-reveal. |
| `TRIVIA_REVEAL_TIME_SEC` | 3.0 | (2026-07-02) How long the results overlay stays up before returning to the board. |

### `Enums` (`scripts/enums.gd`)

```gdscript
enum GameState   { WAITING, ROLLING, MOVING, MINIGAME, GAME_OVER }
enum TileType    { BLANK, GAME_TRIGGER, TRIVIA }   # SARI_SARI retired (2026-07-02) in favor of TRIVIA — see "Trivia Tile System"
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

## LAN Multiplayer Lobby

**Added 2026-06-30.** A pre-game lobby screen now lets up to 4 players connect over LAN before `Game.tscn` ever loads. This is a separate system from the board/minigame loop — **the board and minigame state are not yet networked** (see Known Issues & TODOs below). Right now this only gets all players into the same `Game.tscn` at the same time; it does not yet sync dice rolls, movement, scores, or minigame state across clients.

### `NetworkManager` (`autoload/NetworkManager.gd`)
New autoload, registered alongside `GameManager` etc. Wraps Godot's high-level multiplayer API (`ENetMultiplayerPeer`).

```gdscript
const PORT := 7777                # ENet game connection port
const DISCOVERY_PORT := 7778      # UDP broadcast discovery port
const MAX_PLAYERS := 4

var lobby_code: String            # 5-letter code, host-generated
var is_host: bool
var connected_players: Dictionary # peer_id -> {name: String}
var discovered_lobbies: Dictionary # code -> {ip: String, last_seen: float}, joiner-side only
```

**Hosting (`host_lobby(player_name)`):** generates a 5-letter code (`_generate_code()`, excludes `I`/`O` to avoid visual confusion with `1`/`0`), calls `ENetMultiplayerPeer.create_server()` on `PORT`, registers itself as peer 1 in `connected_players`, then starts broadcasting its code over UDP via `_start_broadcasting()` (a `Timer` firing `_send_broadcast()` once a second).

**Joining:** two paths exist —
- `join_lobby_by_code(code, name)` — looks up the code in `discovered_lobbies` (populated by listening for the host's UDP broadcasts) and resolves it to an IP automatically.
- `join_lobby(code, ip, name)` — direct IP connect, no discovery involved. `lobby_screen.gd`'s join flow uses this automatically whenever the IP field is non-empty, falling back to the by-code/discovery path otherwise — see "Manual IP fallback" below for why this exists.

Once connected, the joining client calls `rpc_id(1, "_register_player", player_name, lobby_code)` to register with the host. The host's `_register_player` validates the code matches, adds the peer to `connected_players`, and calls `_broadcast_player_list()` to sync everyone's roster.

**Starting the match:** host-only `start_game()` stops discovery broadcasting, builds the player-index map (see "Gameplay Sync" below), then `rpc("_on_game_start")` (with `call_local`) tells every peer — including the host itself — to `change_scene_to_file("res://scenes/Game.tscn")` simultaneously.

> **✅ Gameplay sync now implemented (2026-06-30) — dice rolls, turn order, player count, and minigame launch.** The original limitation (every peer running a fully independent, unsynced `GameManager`) is resolved for these systems. See the new "Gameplay Sync" section below for the full design. **Still not synced: input *inside* minigames** — `LuksongBaka`, `SackRace`, and `LangitLupa` each still read raw local keyboard input per client, so once a minigame scene loads, a key press on one window has no effect on any other window's copy of that minigame. This is the next piece of work — see Known Issues & TODOs.

### Gameplay Sync (added 2026-06-30)

Same host-authority pattern throughout: a client **requests** an action via RPC, the host validates/computes the result, then **broadcasts** the result to every peer (including itself, via `call_local`) so all copies of `GameManager` end up in the identical state. Three systems use this pattern so far.

**Player index ↔ peer ID mapping.** Built once by the host in `_build_player_index_map()`, called from `start_game()` before the scene change. Sorts `connected_players` peer IDs ascending and assigns player index 0, 1, 2... in that order — deterministic with no extra negotiation needed. Synced to every peer via `_sync_player_index_map(mapping, player_count)` (`authority`/`call_local`). `NetworkManager.get_my_player_index()` lets any client ask "which player am I" by looking up its own `multiplayer.get_unique_id()` in the synced map.

> **✅ Player count now respected for turn order (2026-06-30).** `_sync_player_index_map` also carries the real connected player count, stored in `GameManager.active_player_count`, which immediately triggers `GameManager._setup_players()` to rebuild the `players` array at the correct size. Previously `GameManager._ready()` always built exactly 4 players and every turn-wraparound (`State_EndTurn`, `GameManager._on_minigame_finished`, `GameManager._advance_turn`) used the hardcoded `Constants.MAX_PLAYERS` — so a 2-player LAN match would softlock waiting forever for a nonexistent Player 3's turn. All three wraparound sites now use `GameManager.active_player_count` instead, and `Game.gd._spawn_tokens()` only spawns tokens for `active_player_count` players instead of always 4. **Process note:** `GameManager._ready()` runs at autoload init, before the lobby even exists, so it can't know the real count up front — `_setup_players()` had to be extracted into its own callable function so `NetworkManager` can re-run it once the synced count actually arrives, rather than trying to set `active_player_count` early enough for `_ready()` to use it correctly.

**Dice rolls.** `dice.gd`'s `roll()` no longer generates its own result locally — the `DICE_ROLL_TICKS` tick animation still plays locally for visual feedback, but the actual number comes from the host. If the local player is the host, `NetworkManager._process_roll_request()` is called directly; otherwise `NetworkManager.request_roll.rpc_id(1)` sends the request to the host. Either path ends in the host broadcasting `_apply_roll_result(result)` (`authority`/`call_local`), which calls the existing `GameManager.on_dice_rolled(result)` — so `EventBus.dice_rolled` fires identically on every peer, and `dice.gd` listens for that to update its own label and clear `is_rolling`, rather than setting those directly inside `roll()` anymore.

> **✅ Gotcha — `rpc_id` targeting yourself throws, doesn't silently no-op (2026-06-30).** Initial implementation always called `NetworkManager.request_roll.rpc_id(1)` regardless of whether the local player was the host. When the host itself owns the current turn, `rpc_id(1, ...)` targets peer 1, which is the host's own peer ID — and Godot's `@rpc("any_peer")` mode explicitly throws `"RPC 'request_roll' on yourself is not allowed by selected mode"` rather than just routing the call locally. This is also why `multiplayer.get_remote_sender_id()` returns `0` instead of a real peer ID for self-targeted calls in modes where they *are* allowed — both are the same underlying class of gotcha (self-targeted RPCs don't behave like normal RPCs). **Fix:** `dice.gd` now branches on `NetworkManager.is_host` and calls `NetworkManager._process_roll_request(multiplayer.get_unique_id())` directly when true, only going through the real `rpc_id(1, ...)` path for non-host clients. `request_roll()` itself still defensively treats a `sender_id == 0` as "the host calling itself," in case any other call site hits the same situation later.

**Minigame selection + launch.** Previously, `State_TileEvent._handle_minigame()` called `Utils.random_minigame()` and `SceneLoader.go_to_minigame()` directly — meaning every client independently rolled its own random minigame ID. With only 2 minigames in rotation this could coincidentally match about half the time, which is exactly what made the bug easy to miss during early testing; it surfaces for real once `LangitLupa` is also in the pool (3-way odds make a mismatch the common case, not the exception). `State_TileEvent` now calls `NetworkManager.start_minigame_synced(participating_players)` instead — every peer calls this, but the function itself is guarded with `if not is_host: return`, so only the host's instance actually calls `Utils.random_minigame()`. The chosen ID is broadcast via `_launch_minigame(minigame_id, participating_players)` (`authority`/`call_local`), which is what actually calls `EventBus.minigame_started.emit()` and `SceneLoader.go_to_minigame()` on every peer at once. Verified via live two-window testing (2026-06-30): host's console is the only one that prints `"Launching synced minigame: ..."`, both windows load the identical scene at the same moment, and final scoring matches on both sides.

> **✅ All three minigames now fully synced (2026-06-30).** `LuksongBaka` and `SackRace` use the discrete request→validate→broadcast pattern. `LangitLupa` uses a 20Hz position broadcast (each client owns their player's movement locally, sends position to host, host relays to all peers) with host-authoritative tagging, area-unsafe detection, and round-end — see `LangitLupa` section under Minigame System for full detail.

### UDP Broadcast Discovery
Host and joiner both run a `PacketPeerUDP`, but for different purposes — host's is dedicated to sending (`_start_broadcasting`/`_send_broadcast`), joiner's is bound for receiving (`start_listening_for_lobbies`, polled every frame in `_process()` while not `is_host`). Broadcast message format: `"PINOYPARTY|{code}"`.

> **✅ Gotcha confirmed during one-machine testing (2026-06-30):** two instances on the **same machine** cannot both `bind()` `DISCOVERY_PORT` for listening — only the first call succeeds, the second fails silently with a nonzero error code (no thrown exception, just a returned `Error`). This makes broadcast discovery fundamentally untestable with two processes sharing one IP; it requires two physically separate machines on the same LAN to verify properly. **This is not a bug to fix** — it's an inherent limitation of UDP port binding, expected to work fine across real machines since each has its own IP.

**Manual IP fallback (added for same-machine testing):** `lobby_screen.gd`'s `_on_join_pressed()` checks the `JoinIPInput` field — if non-empty, it calls `join_lobby()` directly with that IP instead of going through `join_lobby_by_code()`/discovery. This was added specifically so the one-laptop-two-`.exe`-instances testing flow (see Recent Bug Fixes) has a working path despite the port-binding limitation above; `127.0.0.1` as the IP is what makes single-machine testing possible at all. Kept in the shipped UI as a small "or enter IP manually" affordance even post-testing, in case discovery ever flakes on a real network (e.g. router client-isolation blocking broadcast traffic between devices).

### `lobby_screen.gd` (`scenes/ui/LobbyScreen.tscn`)
Set as the project's **Main Scene** (Project Settings → Application → Run), replacing the previous direct-to-`Game.tscn` entry point.

```
LobbyScreen (Control)              ← lobby_screen.gd
├── HostJoinPanel (VBoxContainer)
│   ├── NameInput (LineEdit)
│   ├── HostButton (Button)
│   ├── JoinCodeInput (LineEdit)
│   ├── JoinIPInput (LineEdit)     ← optional, see "Manual IP fallback" above
│   └── JoinButton (Button)
├── LobbyPanel (Control)
│   ├── CodeLabel (Label)
│   ├── PlayerCards (HBoxContainer) ← built at runtime, one card per connected player
│   └── StartButton (Button)        ← host-only; disabled until ≥2 players
└── StatusLabel (Label)             ← error/status text (e.g. "No lobby found...")
```

`_ready()` explicitly sets initial panel visibility (`HostJoinPanel` visible, `LobbyPanel` hidden) and connects `HostButton`/`JoinButton`/`StartButton` press signals **in code** rather than relying on editor-side signal wiring — see the dedicated gotcha below for why.

**Roster syncing:** listens to a single `NetworkManager.roster_updated` signal (not `player_joined`/`player_left` — see gotcha below) to rebuild `PlayerCards` and toggle `StartButton.visible`/`disabled` based on `is_host` and player count.

> **✅ Gotcha — editor-wired signals silently missing (2026-06-29).** Initial testing found that clicking "Host" did nothing at all. Root cause: `HostButton.pressed` was never actually connected to `_on_host_pressed()` — the function existed, but nothing called it, because the signal connection was expected to be made manually in the editor's Signals tab and never was. **Fix:** connect all three buttons' `pressed` signals explicitly in `_ready()` instead of depending on editor wiring, matching how `start_button` was already connected. **Process takeaway:** when a button "does nothing" with no error at all, check whether its signal is actually connected before assuming the handler logic is broken — a disconnected signal produces zero console output, identical in symptom to a silently-failing handler.

> **✅ Gotcha — `player_joined`/`player_left` only ever fire on the host (2026-06-30).** Initial roster-sync logic connected `_on_roster_changed` to `NetworkManager.player_joined` and `player_left`. Both signals are only emitted from inside `_register_player()`/`_on_peer_disconnected()`, which have an `if not is_host: return` guard — meaning **joining clients never receive either signal**, even though their own `connected_players` dictionary correctly updates via the `_sync_player_list` RPC. Symptom: the host's UI updated fine when a player joined, but the joiner's screen stayed stuck on the host/join panel forever, never flipping to show the lobby — despite the underlying data being correct on both sides. **Fix:** added a new `roster_updated` signal, emitted from inside `_sync_player_list` itself (which already runs via `@rpc("authority", "reliable", "call_local")`, so it fires on every peer including the host). `lobby_screen.gd` now listens to `roster_updated` exclusively for rebuilding the UI. **Process takeaway:** any signal meant to drive UI state needs to fire on **every peer that needs to react**, not just the one where the underlying logic happens to run — RPC call sites and signal emission sites aren't automatically the same set of machines.

> **Gotcha — type inference fails on `$NodePath.property` inside `:=` assignments.** `var typed_ip := $HostJoinPanel/JoinIPInput.text.strip_edges()` threw `"Cannot infer the type of 'typed_ip' variable because the value doesn't have a set type"` for three separate variables in `_on_join_pressed()`. Fixed by declaring an explicitly-typed intermediate variable for the node reference first (`var join_ip_input: LineEdit = $HostJoinPanel/JoinIPInput`), then accessing `.text` off that typed variable rather than chaining straight off the `$Path` shorthand inside a `:=` assignment.

### Testing Notes (one-laptop setup)
No second machine available during initial development, so testing relied on running two exported `.exe` copies of the same debug build side-by-side as independent OS processes (not two editor instances — editor multi-instance runs can cause port/breakpoint conflicts). Key findings, all confirmed live:
- Direct IP join (`127.0.0.1`) works correctly between two same-machine instances; this is the primary tested path so far.
- Broadcast discovery cannot be validated on one machine (see UDP Broadcast Discovery section above) — needs real two-machine LAN testing before considering it verified.
- Two hosts cannot both bind `PORT` (`7777`) on the same machine — attempting to click "Host" on a second instance after one is already hosting throws `"ERROR: Couldn't create an ENet host"` and emits `join_failed.emit("Could not create server")`. Expected behavior, not a bug — confirms `create_server()`'s error path is being surfaced correctly to the UI rather than failing silently.
- Debug `print()` statements were added at each step of the join pipeline (`_on_join_pressed`, `join_lobby`, `_on_connected_ok`, `_register_player`) specifically to localize failures during this testing — worth keeping in place for now given how many of this project's past bugs (per Recent Bug Fixes throughout this log) have been silent-failure types with no thrown error.

---



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

A rhythm-based timing minigame (jump-the-rope). **Fully LAN-synced (2026-06-30)** — zone position, jump results, and round-end detection are all host-authoritative. Each client controls only their own player via the shared `jump` (spacebar) action. Marker sweep visuals remain local for performance.

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

A timed mash-race minigame. All players race simultaneously on parallel tracks. **Fully LAN-synced (2026-06-30)** — each client controls only their own player via the shared `jump` (spacebar) action; hop progress is host-authoritative and broadcast to all peers.

**Mechanics:**
- Each press of a player's jump button (`p1_jump`–`p4_jump`) advances their sack a fixed distance (`HOP_DISTANCE`)
- First to reach `FINISH_DISTANCE` (30 hops) wins; race also ends via `RACE_TIMEOUT` (15s) if nobody finishes, ranking remaining players by progress
- Visual: 4 `ColorRect` nodes under `Tracks/Player 1`–`Player 4` move along the X axis (`HOP_PIXELS` per hop); a `TimerLabel` shows live countdown

**Folder/naming:** `res://scenes/minigames/SackRace/sack_race.gd` + `SackRace.tscn` (root node named `SackRace`). Filenames manually verified against `to_snake_case()` output before being added to `Constants.MINIGAMES`, per the lesson learned from the LuksongBaka scene-path bug above.

> **✅ Double-scoring + missing tie-handling — FIXED (2026-06-27).** `_end_race()` previously called `GameManager.add_score()` directly *and* passed the same scores through `_finish()` — which (via `GameManager._on_minigame_finished()`) applies them a second time, silently doubling every player's points from this minigame. It also had zero tie handling: two players with identical progress at the 15s timeout were given an arbitrary order by `sort_custom` instead of being treated as tied. **Fix:** finishers (who crossed the line) keep their strict order — simultaneous finishes aren't physically possible since only one key-press event ever fires per advance. Anyone who didn't finish is now grouped by `is_equal_approx(progress[a], progress[b])` into real tie-groups, then the whole placement list is fed through `BaseMinigame.compute_placement_scores()` exactly once.

### Implemented Minigame: `LangitLupa` (reworked 2026-07-04 — now a side-view platformer)

**Full rework from the original top-down tag minigame.** No more IT/tagging, no more
random elevated safe-zones, no more round timer. New design: a side-view platformer
where players climb from a fixed spawn platform (bottom-left) to a fixed goal platform
(top-right) while a rising flood eliminates anyone it catches.

**Mechanics:**
- Movement is `move_left`/`move_right` + `jump` (coyote-jump window: `COYOTE_TIME` =
  0.15s after leaving a platform edge still allows a jump).
- `SpawnPlatform`/`GoalPlatform` positions are computed every round from the viewport
  size (`_auto_position_spawn_and_goal()`), not manually placed — bottom-left / top-right
  with a `SCREEN_MARGIN` inset.
- Middle platforms are a **static, deterministic zigzag grid** (`_generate_platforms()`),
  not randomized — since it's fully deterministic from `SpawnPlatform`/`GoalPlatform`'s
  positions, every peer generates the identical layout locally with **no network sync
  needed** for platform placement at all (this replaced an earlier randomized-with-seed
  version that proved unreliable — see Recent Bug Fixes).
- The flood (`Flood` node) rises at `FLOOD_RISE_SPEED` px/sec, computed identically on
  every peer from a synced `round_start_msec` — no per-frame position sync needed either,
  same "compute locally from a shared timestamp" pattern as the trivia timer.
- **Scoring:** touching the top of `GoalPlatform` awards placement points (3/2/1 for
  1st/2nd/3rd), tracked via `finished_players`. Flood-caught players are removed from
  `alive_players` with no score. Round ends once only one player remains un-finished and
  un-flooded (`alive_players.size() <= 1`), reusing the same end-check for both flood
  elimination and goal-finish.
- Non-participating player slots (2-player matches) are hidden via
  `_hide_inactive_players()` rather than left visibly idle on screen.

**Folder/naming:** unchanged — `res://scenes/minigames/LangitLupa/langit_lupa.gd` +
`LangitLupa.tscn`.

> **✅ Major bug — `Players` container had a nonzero saved Position offset (2026-07-04).**
> After the platformer rework, players consistently "fell through the floor" and were
> instantly caught by the flood, with debug prints showing physically impossible
> teleports to a fixed, unexplained position. Root cause, found only after ruling out
> every other script in the call chain (`NetworkManager`, `BaseMinigame`, `SceneLoader`,
> `State_TileEvent`, collision shapes, node instance identity): `_position_players()`
> wrote each player's **local** `.position`, but `_physics_process()`/`_check_flood()`
> read **global** `.global_position` — normally identical, except the `Players` node
> itself had a leftover nonzero Position from earlier editor work, so every player's
> real global position was offset by a constant amount from what the spawn code assumed.
> **Fix:** reset `Players`' own Position to `(0, 0)` in the editor. No script changes
> needed. **Process takeaway:** when local vs. global position diverge unexpectedly,
> check every ancestor node's transform, not just the node being scripted — this class
> of bug produces numbers that look computed/mysterious but are actually just a constant
> offset hiding in the scene tree.

> **✅ Gotcha — `WorldBoundaryShape2D` left on hand-placed platform colliders (2026-07-04).**
> `SpawnPlatform`, `GoalPlatform`, and `Flood`'s `CollisionShape2D` nodes defaulted to
> `WorldBoundaryShape2D` (an infinite physics plane) instead of `RectangleShape2D` when
> first created in the editor. Symptom looked like falling through solid-looking
> platforms. Fixed by explicitly setting Shape to `RectangleShape2D` sized to match each
> platform's visual `ColorRect`.

> **✅ Gotcha — visual child nodes dragged independently of their parent (2026-07-04).**
> Multiple times during this rework, a `ColorRect`/`CollisionShape2D` child was dragged
> in the 2D editor while its parent (`SpawnPlatform`, `GoalPlatform`, a `Player`) stayed
> at its original position — meaning script-driven repositioning of the parent had no
> visible effect, since the rendered/collided geometry was really anchored to the
> child's own independent offset. **Process takeaway:** when something "won't move" via
> script despite the code being correct, check whether the visible piece is actually a
> child with its own manually-set Position, not the node being scripted.

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

## Trivia Tile System

**Added 2026-07-02.** A separate tile type from `GAME_TRIGGER` — `Enums.TileType.TRIVIA`, generated by `board.gd._determine_tile_type()` on its own tile pattern (offset from the `% 4 == 0` GAME_TRIGGER pattern so they never collide). Only the player who lands on the tile answers; everyone else's screen shows the question dimmed/disabled with a "`{name} is answering...`" label, so it's visible but clearly non-interactive.

**Flow:**
1. `State_TileEvent._handle_trivia()` calls `NetworkManager.start_trivia_synced(GameManager.current_player_index)`.
2. Unlike `_handle_minigame()`, this does **not** trigger a scene change — trivia plays as a full-screen overlay directly on top of the board — so `State_TileEvent` is never destroyed and `await EventBus.trivia_finished` followed by `request_transition(&"State_EndTurn")` works safely and directly, with no need for `GameManager` to babysit turn-advancement the way it does for minigames.
3. Host picks a random question from `res://data/trivia_questions.json` (host-only, broadcast via `_apply_trivia_start` RPC — `authority`/`call_local`).
4. Only the designated answering player's answer is accepted; `request_trivia_answer` on the host rejects any other player index, and rejects stale answers after the round has moved on (see round-ID guard below).
5. Reveal is immediate once the answering player submits (or after `Constants.TRIVIA_ANSWER_TIME_SEC` if they never do), broadcasting `_apply_trivia_reveal(scores, correct_index)`.
6. `GameManager._on_trivia_finished()` applies the score via `add_score()` only — it does **not** advance the turn (see "Turn advancement" gotcha below).

**Controls:** each client's `TriviaController` overlay reads its own local keyboard only — `W`/`S`/arrow keys move a `▶` selector between options, `Space`/`Enter` locks in the answer. No new input actions were added to `project.godot`; this is handled via raw `InputEventKey` checks in `_unhandled_input()`, scoped to the local player only (no cross-talk between LAN clients' windows, verified via live two-window testing).

### `TriviaController` (new autoload)
Registered alongside `GameManager`/`NetworkManager`. Builds its overlay entirely at runtime (same "no scene edits" approach as `HUD`/`ScoreBoard`/`GameOverScreen`) — a dimmed `ColorRect` + a fixed-width centered `VBoxContainer` panel (explicitly sized, not left to `PRESET_CENTER`'s default — an early version let text overflow the window edge because an unconstrained container centers its origin, not its content). Listens to `EventBus.trivia_started(question, options, answering_player_idx)`; non-answering clients get their buttons disabled and dimmed instead of hidden, so the question stays readable but clearly not theirs to answer.

### Data: `res://data/trivia_questions.json`
Array of `{question: String, options: Array[String] (4 entries), correct_index: int}`. Expandable without touching any script. `NetworkManager._load_trivia_questions()` guards against a malformed file (`JSON.parse_string()` returning `null` on parse failure) by falling back to an empty array rather than propagating a `null` into `.is_empty()` checks.

> **✅ Gotcha — turn advancement duplicated, then split incorrectly (2026-07-02).** `_handle_trivia()` was first written by copying `_handle_minigame()`'s "don't await, let `GameManager` handle it" pattern — reasonable-looking, since that's the established pattern for `GAME_TRIGGER`. But that pattern only works for minigames because `SceneLoader.go_to_minigame()` destroys `Game.tscn` (and `State_TileEvent` with it), forcing a *new* `StateMachine` to boot at `State_StartTurn` for the already-advanced `current_player_index`. Trivia never changes scenes — `State_TileEvent` survives the whole round — so `GameManager` silently advancing `current_player_index` in the background did nothing to move the FSM forward. Symptom: dice still rolled and produced results, but tokens never moved, because the FSM was permanently stuck inside `State_TileEvent`, waiting for a transition nobody ever requested. **Fix:** `_handle_trivia()` now awaits `EventBus.trivia_finished` directly and transitions to `State_EndTurn` itself; `GameManager._on_trivia_finished()` was trimmed to only apply the score, no longer touching `current_player_index` (State_EndTurn already handles that + game-over checking). **Process takeaway:** the "let an autoload handle it" pattern is only correct when the node issuing the async call is actually going to be destroyed — copying it onto a node that survives just creates a coroutine with nothing left to resume it.

> **✅ Gotcha — stale round timer force-ending the next round (2026-07-02).** `start_trivia_synced()`'s answer-timeout (`await get_tree().create_timer(TRIVIA_ANSWER_TIME_SEC).timeout`) had nothing canceling it if the round resolved early, which it almost always does now that only one player ever answers. If that same player landed on a **second** trivia tile before the first round's timer had finished counting down, the stale timer would fire mid-way through round 2 and force a premature reveal — using round 2's (still-empty) `_trivia_answers`, which read as "it already picked an answer for me" from the player's perspective. Same stale-coroutine shape as `State_Moving`'s signal-theft bug and `LangitLupa`'s `_end_game()` re-arming bug. **Fix:** added `_trivia_round_id`, incremented at the start of every round and captured locally before the `await`; the timer only calls `_reveal_trivia_results()` if `_trivia_round_id` hasn't changed since it started waiting. `process_trivia_answer()` also now rejects any answer for a `player_idx` that doesn't match the *current* `_trivia_answering_player`, closing the same race from the other direction.

---

## LAN Multiplayer Lobby — Disconnect Handling

**Added 2026-07-02.** Previously, `_on_peer_disconnected()` only updated the lobby roster — there was no handling at all for a disconnect **mid-match**, and no handling whatsoever for the client-side case of the host disconnecting (a different Godot signal, `multiplayer.server_disconnected`, which `NetworkManager` wasn't listening to). Both cases used to mean every remaining client just hangs, waiting on input from a peer that's gone, with zero feedback — same silent-freeze shape as most bugs in this log.

**Scope, deliberately limited:** detect the disconnect and end the match cleanly with a message — not host migration, not pause-and-resume. For a couch/LAN party game, ending the match with a clear reason is the right level of effort; resumable matches would be a substantially bigger project.

- `NetworkManager.match_in_progress: bool` — set `true` in `_on_game_start()`, `false` again once a disconnect is handled.
- `NetworkManager.host_left` (signal) — emitted from a new `_on_server_disconnected()` handler, connected to `multiplayer.server_disconnected` in `_ready()`. Only ever fires on clients (the host has no "server" to lose).
- `NetworkManager.player_left_mid_match(peer_id, player_name)` (signal) — emitted from `_on_peer_disconnected()` when `is_host and match_in_progress`, via a new `_notify_player_left_mid_match` RPC (`authority`/`call_local`) so every remaining peer — not just the host — finds out.
- `Game.gd` connects to both in `_ready()` and shows a runtime-built full-screen overlay (same pattern as `GameOverScreen`) with the disconnect reason and a "Back to Lobby" button that clears `multiplayer.multiplayer_peer` and reloads `LobbyScreen.tscn`.

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

> **✅ Same hardcoded-player-count bug as the turn-wraparound fix, found here too (2026-07-02).** Row building (`_ready()`), `_refresh_all()`, and the turn-marker loop (`_on_turn_started()`) all iterated `Constants.MAX_PLAYERS` (always 4) instead of `GameManager.active_player_count`. In a 2-player LAN match this threw `Out of bounds get index '2'` trying to read `GameManager.players[2]`, which doesn't exist for that match size. Fixed by swapping all three loops to `GameManager.active_player_count`, consistent with how `Game.gd._spawn_tokens()` and the FSM's turn-wraparound sites were already fixed for the same underlying issue back on 2026-06-30.

### `game_over_screen.gd` (`scenes/ui/GameOverScreen.tscn`)
**Added (2026-06-28).** Same "build everything at runtime" approach as `hud.gd`/`score_board.gd` — root `Control` + script only, no manually-placed children.

- `_ready()`: builds a full-screen dim `ColorRect` (alpha `0.85`), a centered `VBoxContainer` with a headline `Label`, one score row per player (reusing the same row style as `ScoreBoard`, winner's row rendered larger), and a "Play Again" `Button`. Starts `visible = false` and `mouse_filter = MOUSE_FILTER_STOP` (so it can't block clicks while hidden, but does once shown).
- Connects to `EventBus.game_over(winner_index)` — sets the headline to `"%s Wins!"` colored to match the winner, populates every player's final score, then sets `visible = true`.
- "Play Again" calls `GameManager.reset_for_new_game()` then `get_tree().change_scene_to_file("res://scenes/Game.tscn")` — a full scene reload rather than an in-place reset, to avoid any chance of leftover token positions/sprites carrying over from the finished game.
- **Scope clarification:** this is the *board's* game-over screen, not a per-minigame results screen. `EventBus.game_over` is only ever emitted from `State_EndTurn.gd` (or redundantly from `GameManager.add_score()` — see below) when a player's token reaches the final board tile — never from inside a minigame. Since `SceneLoader.go_to_minigame()` fully destroys `Game.tscn` (and everything instanced inside it, including this screen) while a minigame is active, it is expected and correct that this screen cannot appear during a minigame; it only exists again once `SceneLoader.return_to_board()` rebuilds the board scene.
- Must be instanced as a child of `Game.tscn`'s `UI` layer (same as `HUD`/`ScoreBoard`) for `_ready()` to ever run and connect to the signal — confirmed `GameManager.gd` already has working `_get_winner()` and `reset_for_new_game()` implementations as of 2026-06-28, so if the screen still isn't appearing after a normal full game, the instancing step is the first thing to check.

> **✅ Redundancy cleaned up (2026-07-02).** `GameManager.add_score()` no longer checks `_is_game_over()`/emits `game_over` itself. `State_EndTurn._check_game_over()` was also found to be independently re-implementing the same win-condition check rather than calling `GameManager._is_game_over()` — collapsed to delegate to it instead. `EventBus.game_over` now has exactly one emission site.

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
- **Random minigame crashes** — `Utils.random_minigame()` can still return minigame IDs without scenes if `Constants.MINIGAMES` is ever expanded carelessly. `BatoLata` and `AgawBase` have been cut from the project (2026-06-25) and will not be implemented — `Utils.random_minigame()` no longer needs to account for them.


### Stubs / Unimplemented
- `State_EndTurn._save_state()` — TODO: persistence layer
- `State_EndTurn._update_ui()` — TODO: scoreboard refresh signal
- `player.gd` — empty stub
- `TilePath.gd` — empty stub
- Minigames: `LangitLupa` — not yet in active rotation, pending playtest. `BatoLata` and `AgawBase` are **cut from the project** (2026-06-25), see Planned Minigames.
- ~~`Enums.TileType.SARI_SARI` — defined but never assigned to any tile~~ **RETIRED (2026-07-02)** — replaced by `TileType.TRIVIA`, see "Trivia Tile System".
- Board character sprites — **wired in (2026-06-24).** See "Player Token System" for the AnimatedSprite2D/`_build_frames()` implementation. Note the on-disk asset folder path needs verification — see the flagged mismatch in that section.
- Minigame character assets — present but not yet wired into any minigame scene

### Architecture Decisions Pending
- ~~**Game Over screen** — FSM halts at `State_EndTurn` on game over; no UI or transition is implemented~~ **RESOLVED (2026-06-28)** — see `game_over_screen.gd` under UI System.
- **Local multiplayer input** — all 4 players share one screen/keyboard; no network/controller support. Unaffected by the new LAN lobby — that's a separate matchmaking layer, not a replacement for this.
- **LAN multiplayer — fully synced (2026-06-30).** Lobby, turn order, dice rolls, movement, minigame selection/launch, and all three minigames' in-game input are host-authoritative and verified over live 2-window LAN testing. See "Gameplay Sync" under LAN Multiplayer Lobby for the full design.
- ~~**Score display**~~ **RESOLVED** — `ScoreBoard` shows live scores; was already implemented as of 2026-06-27, this line was stale.
- **Disconnect handling** — now detects and cleanly ends a mid-match disconnect (2026-07-02); does not attempt host migration or resume — see "LAN Multiplayer Lobby — Disconnect Handling".

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

> **✅ Timeout added (2026-07-02).** The poll loop now caps at `Constants.MOVEMENT_TIMEOUT_SEC` (5.0s — generous headroom above the worst case of 6 tiles × `MOVE_STEP_DURATION`). If `movement_finished` never fires for the expected player (dropped signal, packet loss, a token that failed to spawn), the loop force-completes instead of hanging forever, logs a `push_warning`, and still writes the authoritative `tile_index` so the game state stays correct even if the token's visual position fell short.

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
| 2026-06-30 | *(pending)* | Implemented LAN multiplayer lobby: new `NetworkManager` autoload (ENet hosting/joining, 5-letter code generation, UDP broadcast discovery on a separate port from the game connection) and `lobby_screen.gd`/`LobbyScreen.tscn`, set as the new Main Scene. See full "LAN Multiplayer Lobby" section above. |
| 2026-06-30 | *(pending)* | Fixed Host/Join buttons doing nothing on click — their `pressed` signals were never connected to anything; editor-side wiring was assumed but never actually done. Connected all three lobby buttons explicitly in `_ready()` instead. |
| 2026-06-30 | *(pending)* | Fixed joining clients never seeing the lobby roster update (host's UI updated fine, joiner's stayed frozen on the host/join panel). Root cause: UI was listening to `player_joined`/`player_left`, both gated `if not is_host: return` and therefore never emitted on the joiner's own instance. Added a new `roster_updated` signal emitted from `_sync_player_list` (already `call_local`, fires on every peer) and switched `lobby_screen.gd` to listen to that instead. |
| 2026-06-30 | *(pending)* | Confirmed via live one-machine testing that two instances can't both bind the UDP discovery port, making broadcast discovery untestable without a second physical machine; added a manual-IP fallback path (`join_lobby()` directly, bypassing discovery, whenever the IP field is filled in) specifically to unblock same-machine testing of the core connection/registration logic. |
| 2026-06-30 | *(pending)* | Synced dice rolls: `dice.gd` no longer generates its own result locally, instead requesting a roll from the host (directly if the local player *is* the host, since self-targeted `rpc_id()` calls throw rather than no-op) and reacting to the broadcast `EventBus.dice_rolled` signal like every other peer. Fixed two related self-targeted-RPC gotchas found during live two-window testing: `rpc_id(1, ...)` from the host to itself throws `"RPC ... on yourself is not allowed by selected mode"`, and `multiplayer.get_remote_sender_id()` returns `0` instead of a real peer ID in that same situation. |
| 2026-06-30 | *(pending)* | Fixed a softlock where a 2-player LAN match would hang forever waiting for a nonexistent Player 3's turn. Root cause: `GameManager` always built exactly 4 players and every turn-wraparound used hardcoded `Constants.MAX_PLAYERS`, with no awareness of how many real players actually joined the lobby. Added `GameManager.active_player_count`, synced from `NetworkManager`'s player-index map (which already knew the real count from `connected_players.size()`), and switched all turn-wraparound sites plus `Game.gd._spawn_tokens()` to use it instead. |
| 2026-06-30 | *(pending)* | Synced minigame selection and launch: `State_TileEvent._handle_minigame()` previously let every client independently call `Utils.random_minigame()`, so two LAN clients could (and increasingly would, as more minigames are added to rotation) load completely different minigames at the same time. Added `NetworkManager.start_minigame_synced()`, host-guarded so only the host's instance picks the random ID, broadcasting the choice via `_launch_minigame()` so every peer loads the identical scene at the same moment. Verified via live two-window testing — confirmed working, though gameplay *inside* the minigame is still fully local per client (separate, larger piece of work, not yet started). |
| 2026-06-30 | *(pending)* | Synced `SackRace` in-minigame input. Replaced per-player `p1_jump`–`p4_jump` key scheme with a single `jump` action (spacebar), gated by `NetworkManager.get_my_player_index()` so each client only advances their own player. Hop requests route through the host (`request_sack_race_hop` → validated → `process_sack_race_hop` → broadcast `_apply_sack_race_hop` → `apply_hop()` on every peer) using the same request→validate→broadcast pattern as dice rolls. Host validates that the requesting peer actually owns the player index it claims to control. Verified via live two-window testing — both windows stay in sync and only the correct player's sack advances per keypress. |
| 2026-06-30 | *(pending)* | Synced `LuksongBaka` in-minigame input. Three things needed host authority: zone position (was randomized independently per client), jump results (host evaluates `marker_t` authoritatively to decide Cleared/Caught), and round-end detection (host decides when the sweep ends and who was auto-eliminated). Marker sweep visuals stay local per client (time-based, stays approximately in sync on LAN). Same `jump` spacebar action as SackRace, same per-player ownership gate. Added `sync_luksong_round`, `request_luksong_jump`/`_apply_luksong_jump`, and `sync_luksong_round_end` RPCs to `NetworkManager`. Verified via live two-window testing. |
| 2026-06-30 | *(pending)* | Fixed `"Could not find type 'LuksongBaka' in the current scope"` errors in `NetworkManager.gd`. Root cause: `luksong_baka.gd` was missing a `class_name LuksongBaka` declaration, so Godot couldn't resolve the type name used in `is LuksongBaka` checks — unlike `sack_race.gd` which already had `class_name SackRace` at the top. Fix: add `class_name LuksongBaka` to the top of `luksong_baka.gd`. Worth checking any future minigame script added to `NetworkManager`'s `is` checks has its `class_name` declared. |
| 2026-06-30 | *(pending)* | Synced `LangitLupa` in-minigame input. Three categories of sync: (1) one-time setup — host picks `it_player` and all 6 area positions, broadcasts via `sync_langitlupa_start`; (2) 20Hz position broadcast — each client moves their own player locally and sends position to host, host relays to all peers via unreliable RPC, non-local nodes snap to incoming positions; (3) authoritative events — host detects tags and area-unsafe transitions, broadcasts via reliable RPC so all clients apply them identically. AI only runs on host, only for player indices with no real LAN peer assigned. |
| 2026-06-30 | *(pending)* | Fixed IT player not showing as colored on the host's screen in LangitLupa. Root cause: `_position_players()` ran before `it_player` was ever set (it's assigned later in `apply_langitlupa_start()` once the host broadcasts the choice), so the `RED if idx == it_player` check always evaluated false. Fix: removed color-based IT identification entirely and replaced it with a runtime-built red `▼` Label added as a child of the IT player's node inside `apply_langitlupa_start()`, which is guaranteed to run after `it_player` is known on every peer. |
| 2026-07-01 | *(pending)* | Added mid-match disconnect handling to `NetworkManager` — `host_left` signal (via previously-unhandled `multiplayer.server_disconnected`) and `player_left_mid_match` signal (via a new `_notify_player_left_mid_match` RPC), both wired into `Game.gd` to show a runtime-built overlay and return to `LobbyScreen.tscn`. Scope deliberately limited to "detect and end cleanly," not host migration or resume. |
| 2026-07-01 | *(pending)* | Added `Constants.MOVEMENT_TIMEOUT_SEC` cap to `State_Moving`'s movement-completion poll loop, closing the previously-flagged "no timeout" gap. Removed the redundant `game_over` emission from `GameManager.add_score()` and collapsed `State_EndTurn._check_game_over()` to delegate to `GameManager._is_game_over()` instead of maintaining a second copy of the win condition. |
| 2026-07-02 | *(pending)* | Implemented the Trivia tile system end-to-end: new `Enums.TileType.TRIVIA` (replacing unused `SARI_SARI`), `res://data/trivia_questions.json`, new `TriviaController` autoload (runtime-built overlay, W/S/arrow + Space/Enter keyboard nav), and host-authoritative single-answerer sync in `NetworkManager` (`start_trivia_synced`, `request_trivia_answer`/`process_trivia_answer`, `_apply_trivia_reveal`). See "Trivia Tile System" for full design and the two gotchas found during implementation (turn-advancement pattern copied incorrectly from minigames; stale round-timer bleeding into a player's next trivia round). |
| 2026-07-02 | *(pending)* | Propagated real lobby-entered player names into `GameManager.players[i]["name"]` via a new `NetworkManager.get_player_name()` reverse lookup, replacing the hardcoded `"Player %d"` used everywhere previously (HUD, ScoreBoard, trivia results all picked this up automatically). Also fixed `score_board.gd` iterating hardcoded `Constants.MAX_PLAYERS` instead of `GameManager.active_player_count`, the same category of bug already fixed elsewhere for 2-player matches. |
| 2026-07-04 | *(pending)* | Reworked `LangitLupa` from top-down tag minigame into a side-view platformer: left/right + coyote-jump movement, fixed spawn/goal platforms auto-positioned from viewport size, static deterministic zigzag platform grid (no more random layout, no seed sync needed), rising flood hazard replacing the round timer, and goal-touch placement scoring (3/2/1) replacing tag-based scoring. |
| 2026-07-04 | *(pending)* | Fixed a major "instant death" bug in reworked `LangitLupa` — the `Players` container node had a leftover nonzero saved Position, causing local vs. global position mismatches between `_position_players()` (writes local) and the physics/flood-check code (reads global). Also fixed `WorldBoundaryShape2D` left on several hand-placed platform colliders (should have been `RectangleShape2D`), and multiple cases of visual/collision child nodes dragged independently of their parent in the editor, masking script-correct repositioning. |
---

## Planned Minigames

| ID | Status | Description |
|----|--------|-------------|
| `LuksongBaka` | ✅ Implemented | Jump the rope timing minigame |
| `SackRace` | ✅ Implemented | Mash-to-race sack race |
| `LangitLupa` | ✅ Implemented, in rotation, side-view platformer | Reworked 2026-07-04 from the original top-down tag minigame into a climbing platformer with a rising flood hazard and goal-touch placement scoring (3/2/1). Static deterministic platform grid, no network sync needed for layout. |host-authoritative, 20Hz position broadcast, host-authoritative tagging/area-unsafe/round-end. IT player indicated by a red ▼ arrow above their node (replaces the broken color scheme). |
| `BatoLata` (Labay Lata) | 🚫 Cut (2026-06-25) | Hit-the-can-and-run minigame; two prototype passes (lane-based, then free-movement w/ AI) were built and discarded before the decision to cut. No longer planned. |
| `AgawBase` | 🚫 Cut (2026-06-25) | Base stealing — never started, no longer planned. |
