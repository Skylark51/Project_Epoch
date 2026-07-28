# CODEX1 공용 파일 변경

이번 작업에서는 Codex 2가 소유한 공용 파일을 변경하지 않았다.

변경하지 않은 파일:

- `project.godot`
- `src/main.gd`
- `src/main.tscn`
- `src/map/strategic_map.gd`
- `src/presentation/strategy_gateway.gd`
- `themes/`

새 월드 시스템은 `src/world/`, `data/world/`, `tests/`에 독립적으로 추가했다.
기존 메인 화면에 연결할 때 Codex 2는 `WorldSession`을 인스턴스화하거나
기존 `StrategyGateway` 내부의 데이터 공급자를 교체하면 된다.
