# 고대 동아시아 기반 데이터

`prototype_east_asia`는 시작 연도가 확정되기 전 시스템·데이터 검증을 위한 F5 기본 시나리오다. `ScenarioSystem`이 이 데이터 계약을 코어 런타임 상태로 변환하며, 기존 가상 3국 카탈로그는 회귀 테스트용으로만 유지한다.

## 범위

- 상위 지역 3개와 필수 하위 지역 10개
- 국가·후보 세력 14개
- 플레이 가능 프로빈스 13개
- Natural Earth 실제 해안선 기반 640×480 사각 타일 레이어(16×16 청크 1,200개)
- 프로빈스당 핵심 지점 5개, 총 65개
- 프로빈스 통치자 13명과 영토 없는 후보 세력 지도자 3명
- 국가마다 귀족·군부·관료·종교 세력·지방민 5개 집단
- 통치체제 6종과 준비·시행·정착 개혁 단계
- 공동반란, 집단별 별도 반란, 국가 선포, 국호·수도 후보

## 데이터 원칙

- `owner_faction_id`는 정치적 귀속, `controller_faction_id`와 `control_progress_hidden`은 군사 통제를 뜻한다.
- 프로빈스와 핵심 지점은 별도 배열로 저장하고 ID로 연결한다.
- 모든 프로빈스에는 `governor_character_id`가 있으며, 중앙 임명·세습·왕족·군사총독·부족·종교·임시군정 유형을 구분할 수 있다.
- 모든 가상 인물은 `historicity: prototype`, `is_fictional: true`로 표시한다.
- 연도에 따라 달라지는 세력 배치, 국호, 수도, 지점명은 `candidate`, `period_dependent_candidate`, `needs_review`로 표시한다.
- 종교는 정통성·민심·외교·의례·통합 채널에 영향을 주지만, 같은 계층과 기능 유형에서는 성능 우열을 두지 않는다.

## 런타임 연결과 독립 API

`res://src/main.tscn`은 `StrategyGateway`와 `ScenarioSystem`을 통해 이 시나리오를 기본으로 불러온다. 월드 기반 기능만 별도로 사용할 때는 다음 클래스를 preload할 수 있다.

```gdscript
const EastAsiaWorldFoundation = preload("res://src/world/east_asia_world_foundation.gd")

var east_asia := EastAsiaWorldFoundation.new()
var loaded := east_asia.load_prototype()
var registered := east_asia.register_with_governance(governance_session)
```

제공 메서드:

- `load_prototype()`
- `register_with_governance(governance_session)`
- `evaluate_province_control(province_id, factors)`
- `decide_governor_response(province_id, war_context)`
- `coalition_eligibility(faction_id, groups, context)`
- `create_coalition_rebellions(coalition, groups_by_id, origin_provinces)`
- `evaluate_rebel_statehood(rebel_state, world_context)`
- `choose_rebel_state_identity(rebel_state, controlled_point_ids, context)`
- `api_snapshot()`

## 역사 검토 대기

- 시작 연도와 그에 따른 국경·소유권
- 국내성·평양성·한성·금성의 시기별 수도 지위와 정확한 지점
- 영산강 권역의 백제 편입 시점과 지방 세력 표현
- 가야 소국의 시기별 명칭·맹주·경계
- 요동·청주의 시기별 왕조와 지방관 명칭
- 야마토 왕권 중심지의 시기별 이동
- 쓰쿠시·기비·이즈모의 정치체 범위와 자칭 국호
- 종교·의례 명칭의 시기별 적합성

## Headless 검증

```powershell
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/east_asia_foundation_test_runner.gd
```
