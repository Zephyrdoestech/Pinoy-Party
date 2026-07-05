# scripts/state_machine/StateMachine.gd
# ---------------------------------------------------------------------------
# Node-based Finite State Machine controller.
#
# Scene tree layout expected inside GameManager.tscn (or wherever you attach
# this script):
#
#   GameManager (Node)
#   └── StateMachine          ← this script
#       ├── State_StartTurn
#       ├── State_WaitingForDice
#       ├── State_Moving
#       ├── State_TileEvent
#       └── State_EndTurn
#
# The StateMachine:
#   • Collects child State nodes on _ready().
#   • Enters the first state automatically (or call start() manually).
#   • Routes _physics_process → active state's tick().
#   • Listens to each state's transition_requested signal and switches states.
# ---------------------------------------------------------------------------
class_name StateMachine
extends Node

## Name of the state to activate when start() is called.
@export var initial_state: StringName = &"State_StartTurn"

## Read-only: the currently active State node (null before start() is called).
var current_state: State = null

## Internal map:  StringName → State
var _states: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Collect every direct child that is a State and wire up its signal.
	for child in get_children():
		if child is State:
			child.state_machine = self
			_states[StringName(child.name)] = child
			child.transition_requested.connect(_on_transition_requested)

	# Defer start so all siblings/_ready() calls finish first.
	call_deferred(&"_start")


func _physics_process(delta: float) -> void:
	if current_state:
		current_state.tick(delta)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Manually kick off the FSM (called automatically via call_deferred in _ready).
## Safe to call again if you need to reset the machine to its initial state.
func _start() -> void:
	_enter_state(initial_state)


## Force an immediate transition to a state by name.
## Useful for external systems (e.g., a minigame result arriving) that need to
## push the FSM into a specific phase without going through the normal flow.
func force_transition(state_name: StringName) -> void:
	_enter_state(state_name)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _on_transition_requested(next_state_name: StringName) -> void:
	_enter_state(next_state_name)


func _enter_state(next_state_name: StringName) -> void:
	if not _states.has(next_state_name):
		push_error(
			"StateMachine: unknown state '%s'. Available: %s"
			% [next_state_name, _states.keys()]
		)
		return

	# Exit current state.
	if current_state:
		current_state.exit()

	current_state = _states[next_state_name]

	# Enter new state.
	current_state.enter()
