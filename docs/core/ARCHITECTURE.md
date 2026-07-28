# Project Epoch core architecture

## Reasoning log

| Work | Level | Reason |
|---|---|---|
| Repository audit, state model, public boundary | Extra High | Cross-system ownership and UI isolation |
| Data loader and validation | High | Referential integrity and JSON normalization |
| Command queue and 17-phase turn order | Extra High | Determinism and ordering constraints |
| Economy, military, diplomacy, peace | Extra High | Coupled state transitions |
| AI planners | Extra High | Valid, non-random strategic behavior |
| Save schema and tests | High | Migration and round-trip guarantees |
| Sample data and documentation | Low | Repetitive data and handoff |

`GameSession` is the facade. It owns `GameState`, `CommandQueue`, `TurnProcessor`,
`SaveManager`, and the event hub. UI code reads snapshots and submits commands; it
does not mutate state. Systems are `RefCounted` scripts loaded explicitly, avoiding
global `class_name` registration and circular dependencies.

Turn phases are: validation, diplomacy, administration, recruitment, movement,
battle, occupation, peace, economy, manpower, growth, stability, collapse, events,
AI planning, date, autosave request. Every phase returns structured log entries.

The battle seed derives solely from scenario seed, turn, source/target Province and
command ID. Replaying the same save and commands therefore reproduces the result.
