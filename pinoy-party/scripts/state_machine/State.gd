# scripts/state_machine/State.gd
# ---------------------------------------------------------------------------
# Base class for every turn-phase state.
# Each concrete state is a child Node of StateMachine.tscn / StateMachine.gd.
# ---------------------------------------------------------------------------
class_name State
extends Node

## Emitted when the state wants to hand control to another state.
## StateMachine listens to this and performs the transition.
signal transition_requested(next_state_name: StringName)

## Typed back-reference set by StateMachine immediately after adding this
## node as a child, before _ready() is called on any state.
var state_machine: StateMachine


# ---------------------------------------------------------------------------
# Virtual interface – override in each concrete state.
# ---------------------------------------------------------------------------

## Called once when the state becomes active.
func enter() -> void:
	pass


## Called once when the state is about to be deactivated.
func exit() -> void:
	pass


## Called every physics frame while this state is active.
## @param delta  Time elapsed since last frame (seconds).
func tick(delta: float) -> void:
	pass


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

## Convenience wrapper so concrete states can just call:
##   request_transition(&"State_WaitingForDice")
## instead of emitting the signal directly.
func request_transition(next_state_name: StringName) -> void:
	transition_requested.emit(next_state_name)
