# Core testing

Run with Godot 4.6+:

```powershell
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_runner.gd
```

The suite validates scenario data, adjacency, command rejection, recruitment,
turn advancement, deterministic battle output, war/peace, a 20-turn simulation,
save/load semantic equality, and validity of AI-generated commands.

The core test script does not load `src/main.gd`. At audit time that pre-existing,
UI-owned file had parser errors and is outside Codex 1's permitted edit boundary.
