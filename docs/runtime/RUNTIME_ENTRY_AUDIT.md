# 런타임 진입 구조 감사

감사 기준: `main` 브랜치, 2026-07-29

## 실행 설정

| 항목 | 감사 시점 상태 | 최종 조치 |
| --- | --- | --- |
| 프로젝트 이름 | `Project Epoch Integrated Prototype` | 임시 표현을 제거하고 `Project Epoch`으로 복원 |
| `run/main_scene` | `res://src/integration/integrated_main.tscn` | `res://src/main.tscn`으로 통일 |
| autoload | 없음 | 변경 없음 |

## 전체 씬과 연결 스크립트

| 씬 | 연결 스크립트 | 참조·용도 | 분류 | 조치 |
| --- | --- | --- | --- | --- |
| `src/main.tscn` | `src/main.gd` | 기존 전략 UI, `ui_smoke_test.gd`, 통합 래퍼가 직접 로드 | 현재 실행에 필수 | 유일한 메인 씬으로 유지 |
| `src/integration/integrated_main.tscn` | `src/integration/integrated_main.gd` | `project.godot`, `integrated_main_test_runner.gd`, README | 기존 기능과 중복된 임시 통합 진입점 | 기능 이전 뒤 삭제 |
| `src/world/world_demo.tscn` | `src/world/world_demo.gd` | `CODEX1_구현내역.md`, `CODEX1_테스트결과.md`의 개발용 실행 예시 | 테스트·개발 데모 | 유지 |

`src/main.gd`는 시작 화면, 시나리오·국가 선택, 전략 지도, 프로빈스 정보,
모집·이동·공격, 외교·평화, 턴 실행, 알림·이벤트 로그를 조립한다.
`src/integration/integrated_main.gd`는 `src/main.tscn`을 자식으로 다시
인스턴스화하고 통치 대시보드를 오버레이로 만든다. 따라서 두 씬은 독립
게임이 아니라 동일 런타임을 이중으로 조립하는 구조다.

## 테스트의 직접 참조

| 파일 | 직접 참조 | 분류 | 조치 |
| --- | --- | --- | --- |
| `tests/integrated_main_test_runner.gd` | `src/integration/integrated_main.tscn` | 임시 통합 런타임 테스트 | `tests/main_runtime_test_runner.gd`로 이름 변경 후 `src/main.tscn` 검증 |
| `src/presentation/ui_smoke_test.gd` | `src/main.tscn` | 전략 UI 스모크 테스트 | 유지 |
| `tests/world_test_runner.gd` | `src/world/world_session.gd` | 월드 시스템 테스트 | 유지 |
| `tests/governance_rebellion_test_runner.gd` | `src/governance/governance_session.gd` | 통치·개혁·반란 코어 테스트 | 유지 |
| `tests/test_runner.gd` | `src/core/game_session.gd` | 코어·세이브·전투 테스트 | 유지 |
| `tests/strategic_military_test.gd` | 코어·전략 군사 스크립트 | 전략 군사 테스트 | 유지 |

중복 테스트 러너는 없었다. 임시 통합 러너만 최종 진입점 이름과 구조에
맞게 변경한다.

## 문서의 실행 경로

| 문서 | 감사 시점 참조 | 분류 | 조치 |
| --- | --- | --- | --- |
| `README.md` | `integrated_main.tscn`, `integrated_main_test_runner.gd` | 현재 사용자 안내 | 단일 메인 씬과 새 테스트 이름으로 갱신 |
| `CODEX1_기존구조분석.md` | `src/main.tscn` | 과거 구조 감사 기록 | 역사 기록으로 유지 |
| `CODEX1_공용파일변경.md` | `src/main.tscn` | 과거 변경 기록 | 역사 기록으로 유지 |
| `CODEX1_구현내역.md` | `world_demo.tscn` | 개발 데모 기록 | 유지 |
| `CODEX1_테스트결과.md` | `world_demo.tscn` | 과거 테스트 기록 | 유지 |

삭제되는 통합 씬을 실행하라는 현재 안내는 README에서 제거한다. 과거 작업
기록은 현재 실행 안내가 아니므로 임의 삭제하지 않는다.

## 저장 구조

감사 시점에는 코어가 `user://autosave.json`(스키마 1), 통치 래퍼가
`user://governance_autosave.json`(스키마 1)을 각각 저장한다. 통치 래퍼는
초기 코어 턴과 통치 파일의 턴이 같으면 자동 복원하므로, 턴 1 저장이 새
게임에 섞일 수 있다. 코어 불러오기 뒤에는 저장된 통치 상태를 명시적으로
복원하지 않고 턴 차이만큼 재계산한다.

최종 구조에서는 코어 `GameState`의 버전 2 세이브에 `governance_state`를
포함한다. 새 게임은 항상 통치 상태를 새로 시드하고, 불러오기는 같은
`autosave.json`에서 코어와 통치를 함께 복원하며, 턴 종료는 통치 턴을 먼저
동기화한 뒤 하나의 파일로 저장한다. 버전 1 코어 세이브는 빈 통치 상태를
추가하는 마이그레이션을 거친다.

## 파일 분류 결론

- 현재 실행에 필수: `src/main.tscn`, `src/main.gd`, 전략·코어·통치 시스템
- 테스트에만 필요: 각 테스트 러너와 `src/presentation/ui_smoke_test.gd`
- 개발 데모: `src/world/world_demo.tscn`, `src/world/world_demo.gd`
- 문서에만 언급됨: 과거 `CODEX1_*`, `CODEX2_*` 작업 기록
- 기존 기능과 중복: `src/integration/integrated_main.tscn`
- 임시 통합용: `src/integration/integrated_main.gd`,
  `tests/integrated_main_test_runner.gd`
- 완전히 미사용으로 확인된 샘플 데이터·중복 UI 씬: 없음

삭제 대상은 기능과 참조가 모두 이전되는 `integrated_main.tscn`과
`integrated_main.gd` 두 파일뿐이다. `sample_governance_state.json`은 통치
상태 시드에 사용되므로 유지한다.
