# CODEX1 기존 구조 분석

## 조사 시점

- 브랜치: `integration/codex1-codex2`
- 엔진: Godot 4.7 기능 플래그, GL Compatibility 렌더러
- 실행 진입점: `project.godot` → `res://src/main.tscn` → `src/main.gd`
- 기본 해상도: 1280×720, `canvas_items` stretch

## 현재 구조

- `src/core/`: 국가·Province 기반 상태, 명령 큐, 턴 처리, 세이브
- `src/systems/`: 기존 경제·군사·전투·외교·평화 시스템
- `src/ai/`: 기존 국가 AI 계획기
- `src/presentation/strategy_gateway.gd`: Codex 2 UI와 기존 `GameSession` 사이 어댑터
- `src/map/strategic_map.gd`: Codex 2의 폴리곤 지도 렌더링과 입력
- `src/main.gd`, `src/main.tscn`: 화면 생성과 현재 실행 진입점
- `data/`: 3개국·9개 Province 샘플 및 밸런스 데이터

## 재사용 판정

재사용:

- Godot 프로젝트 설정과 씬 실행 구조
- 명령 큐, 기존 전쟁·외교 코어
- 버전 기반 JSON 저장 방식
- Codex 2의 지도 확대·이동·선택 입력 개념
- signal 기반 UI 갱신 계약

독립 교체 또는 확장:

- 미리 정해진 Province 소유권 중심 월드 모델
- Province 단위 개발/요새 명령
- 3개국 유럽풍 샘플 시나리오
- 군대 수치 중심 보급 계산

새 월드 시스템은 `src/world/`에 격리했다. 기존 전쟁 코어를 삭제하지 않고,
Codex 2가 `WorldSession`을 통해 새 지역·취락 상태를 읽도록 구성했다.

## 충돌 방지

조사 당시 다음 Codex 2 파일이 수정 또는 미추적 상태였다.

- `project.godot`
- `src/main.gd`
- `src/main.tscn`
- `src/map/`
- `src/presentation/`
- `themes/`
- `docs/ui/`

위 파일은 수정하거나 되돌리지 않았다. 새 실행 데모는
`src/world/world_demo.tscn`으로 분리했다.

## 확인된 기술 부채

- 기존 UI와 문서 일부의 한글 문자열이 모지바케 상태다.
- 기존 UI는 Province 중심 용어와 명령에 결합되어 있다.
- 새 월드의 노드 좌표는 게임용 상대 좌표이며 실제 GIS 데이터가 아니다.
- `probable`, `approximate`, `fictionalized` 지역은 후속 역사 검수가 필요하다.
