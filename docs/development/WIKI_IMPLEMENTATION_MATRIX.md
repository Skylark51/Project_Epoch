# Wiki Implementation Matrix

이 문서는 `docs/design/index.html`의 질문 1–30과 전체 통합 목차를 현재 코드에 대조한 결과다. 상태의 **Implemented**는 데이터·규칙·gateway·UI·저장/불러오기·턴 처리 중 해당 항목에 필요한 경로가 실제로 연결된 경우에만 사용했다. 화면 문구나 버튼만 있는 항목은 **Partially implemented** 또는 **Missing**으로 기록한다.

> 조사 기준: `src/main.gd`, `src/core/**`, `src/presentation/**`, `src/ui/**`, `data/**`, 기존 테스트 및 이번 브랜치의 `tests/wiki_governance_ui_test_runner.gd`. `src/map/**`는 병렬 담당 범위이므로 수정하지 않았다.

## 질문 1–30 대조

`index.html`은 질문 1–10을 세부 번호별 제목 없이 하나의 “게임 기반 체계” 섹션으로 통합한다. 아래 1–9는 해당 정의·목록의 순서를 따라 분리했고, 10은 원문에 독립 설명이 없음을 명시해 기록했다.

| 위키 항목 번호·제목 | 현재 상태 | 근거 파일·함수 | 누락된 동작 | 이번 브랜치 변경 | 테스트 위치 | 추가 통합 필요 여부 |
| --- | --- | --- | --- | --- | --- | --- |
| 1. 게임 정체성 | Partially implemented | `src/main.gd`, `GameSession`, sample scenarios | 캠페인 승리 조건과 전체 역사 진행 | 없음 | `tests/test_runner.gd` | 예. 캠페인 설계 |
| 2. 핵심 도시와 초기 영향권 | Partially implemented | `SettlementSystem`, scenario province data | 시작 영향권을 실제 타일 소유와 완전 연결 | 없음 | `tests/world_test_runner.gd` | 예. 세계·지도 통합 |
| 3. 영향권 성장 요인 | Partially implemented | `InfluenceSystem`, `StabilitySystem` | 인구·문화·행복·수도·군주 효과의 단일 계산식 | 없음 | `tests/world_test_runner.gd` | 예. 정치/문화 데이터 |
| 4. 경합 타일과 자동 국경 | Partially implemented | `InfluenceSystem`, province adjacency | 경합 타일의 실제 귀속 변경과 지도 경계 갱신 | 없음 | `tests/world_test_runner.gd` | 예. map 담당 브랜치 |
| 5. 시설의 귀속 이전 | Missing | province/settlement 데이터의 최소 필드 | 타일 귀속 변경 시 농장·광산·도로·요새의 자동 이전 | 없음 | 없음 | 예. 시설/지도 데이터 |
| 6. 도시 전향 특별 사건 | Missing | 없음 | 복수 조건 장기 누적 도시 전향 이벤트 | 없음 | 없음 | 예. 이벤트 도메인 |
| 7. 행복·안정·물리 통제 분리 | Partially implemented | `StabilitySystem`, `ProvinceControlSystem`, `ProvincialGovernance::_evaluate_risks` | 세 시스템의 모든 행동 결과 통합 | 위험 계산에 행복/안정/불안 반영 | `tests/governance_rebellion_test_runner.gd`, `tests/wiki_governance_ui_test_runner.gd` | 예. 제어 시스템 |
| 8. 도시별·국가 평균 표시 | Implemented | `StrategyReadModel::average_city_value`, `main.gd::_apply_top_bar_preferences` | 평균 변화 추세 그래프 | 상단 선택 항목으로 평균 행복/안정 제공 | `tests/wiki_governance_ui_test_runner.gd` | 아니오 |
| 9. 턴 단위 | Partially implemented | `TurnProcessor::_advance_date`, scenario date data | 모든 시스템을 1계절 명세에 맞춘 콘텐츠 밸런스 | 없음 | `tests/test_runner.gd` | 예. 시나리오 데이터 |
| 10. 게임 기반 체계의 원문 통합 잔여 항목 | Partially implemented | `docs/design/index.html`의 1–10 통합 섹션 | 원문에 질문 10의 독립 제목·규칙이 없어 별도 구현 판정 불가 | 없음 | 문서 검토 | 예. 설계 문서에서 세부 번호 분리 시 재대조 |
| 11. 통치 위임과 자동 집행 | Implemented | `ProvincialGovernance::validate_governance_change/advance_turn`; `TurnProcessor::process_turn` | AI의 장기 지방 정책 선택은 단순 규칙 수준 | 세 통치 수준, 실제 모집량·개발 효과·행정/성장/세수/위험 연결 | `tests/wiki_governance_ui_test_runner.gd` | 아니오 |
| 12. 지방 통치 위험 | Implemented | `ProvincialGovernance::_evaluate_risks/_risk_stage`; `StrategyReadModel::city_risk_causes` | 실제 반란 세력/전투 사건의 연출은 기존 반란 시스템과 추가 결합 필요 | 거리·장기 위임·행복·안정·불안·행정·점령·문화·주둔군 누적 및 원인 표시 | `tests/wiki_governance_ui_test_runner.gd` | 예. 기존 반란 이벤트의 결과 연동 |
| 13. 국가 형태별 임명 | Implemented | `data/governance/provincial_governance.json`; `ProvincialGovernance::allowed_levels/government_appointment_mode` | 인물 단위 총독 풀은 아직 없음 | government profile별 허용 통치 수준·임명 방식 데이터와 실제 선택 제한 | `tests/wiki_governance_ui_test_runner.gd` | 예. 향후 인물 시스템 |
| 14. 직접 통치 한도 | Implemented | `ProvincialGovernance::_recalculate_administration` | 행정 피로도에 대한 대규모 관리 화면은 기본 목록 수준 | 절대 상한 없이 도시 수에 비례한 행정 부하/압력 적용 | `tests/wiki_governance_ui_test_runner.gd` | 아니오 |
| 15. 원거리 직접 명령 | Implemented | `ProvincialGovernance::prepare_local_command`; `TurnProcessor::validate_command/_execute_types` | 명령 전달 시각화는 없음 | 정상 편입 직접 통치는 거리 검사 없이 즉시 처리, 임시 점령지는 징병·건설 제한 | `tests/wiki_governance_ui_test_runner.gd` | 아니오 |
| 16. 점령지 소유권 | Implemented | `PeaceSystem`; `ProvincialGovernance::_advance_occupation` | 조약 UI의 세부 조건 편집은 제한적 | 공식 편입 시 소유권 이전, 기존 평화 협정 경로 유지 | `tests/wiki_governance_ui_test_runner.gd`, `tests/test_runner.gd` | 아니오 |
| 17. 군사 통제 영토의 단계적 편입 | Implemented | `ProvincialGovernance::_advance_occupation/_apply_occupation_values/apply_*_effects` | 단계별 별도 외교 화면은 없음 | 즉후·지속·사실상·정상 4단계와 세수/생산/보충/저항/치안/행정/분쟁 적용 | `tests/wiki_governance_ui_test_runner.gd` | 아니오 |
| 18. 피점령지 주민 융화 | Implemented | `ProvincialGovernance::_advance_assimilation` | 문화 집단별 세부 이벤트는 없음 | 정치 충성·시민 편입·문화 융화를 독립 수치로 누적 | `tests/wiki_governance_ui_test_runner.gd` | 아니오 |
| 19. 융화 정책 적용 단위 | Implemented | `StrategyCommandMapper`; `ProvincialGovernance::validate_assimilation_policy` | 다중 도시 일괄 지정은 없음 | 도시별 현상 유지·완만한 통합·적극적 통합 명령 | `tests/wiki_governance_ui_test_runner.gd` | 아니오 |
| 20. 융화 정책 변경 | Implemented | `ProvincialGovernance::execute_assimilation_policy` | 정책 추천 AI는 없음 | 최소 유지 기간, cooldown, 빠른 재변경의 행복/안정/불안 패널티 | `tests/wiki_governance_ui_test_runner.gd` | 아니오 |
| 21. 사용자 설정형 상단 정보 바 | Implemented | `main.gd::_top_bar_configuration/_apply_top_bar_preferences/_open_top_bar_settings`; `StrategyGateway::update_ui_preferences` | 마우스 드래그 재정렬은 명시적 좌/우 버튼으로 대체 | 항목 표시/숨김·순서 저장·공간 축약·tooltip·긴급 분리 경고 | `tests/wiki_governance_ui_test_runner.gd` | 아니오 |
| 22. 우측 고정 도시 패널 | Partially implemented | `main.gd::_show_single_province_selection/_refresh_governance_controls` | 인구·경제·건설·군사·통치·문화의 개별 탭, 건설 대기열과 총독 인물은 아직 없음 | 국가 개요/도시 상세 계층, 통치·융화·점령·위험·주둔군·경제 수치와 고정 행동 영역 | `tests/main_runtime_test_runner.gd`, `tests/wiki_governance_ui_test_runner.gd` | 예. 건설·인물 데이터 제공 시 확장 |
| 23. 도시 패널 너비 | Partially implemented | `main.gd::_on_right_panel_dragged/_persist_right_panel_width/_apply_right_panel_width` | 상세 탭 자동 확장·카메라 보정은 지도 담당 API가 필요 | 260–520px 제한, 사용자가 조절, 저장/복원 | `tests/wiki_governance_ui_test_runner.gd` | 예. 지도 카메라 보정 API |
| 24. 지도 위 도시 상시 정보 | Deferred with technical reason | `src/map/**` (병렬 담당) | 도시 배너·수도 상징·상시 발전 표식 | 수정하지 않음: 병렬 map 작업과 충돌 방지 | `tests/geographic_map_test_runner.gd` | 예. map 담당 브랜치 병합 |
| 25. 건물의 도시 외형 반영 | Deferred with technical reason | `src/map/**`, 건설 데이터 | 건물 성격별 도시 메쉬/스프라이트 누적 표현 | 수정하지 않음: map 렌더러 소유 범위 | 없음 | 예. map/asset 파이프라인 |
| 26. 지도 확대·이동·입력 | Deferred with technical reason | `src/map/**` (병렬 담당) | 줌·팬·미니맵 입력 최종 동작 | 수정하지 않음: 병렬 map 작업과 충돌 방지 | `tests/geographic_map_test_runner.gd` | 예. map 담당 브랜치 병합 |
| 27. 선택 도시 순환 | Partially implemented | `StrategyReadModel::city_rows`; `main.gd::_focus_city_adapter` | 키보드 좌/우 순환과 지도 카메라 이동은 새 map focus API가 필요 | 목록 정렬 결과와 focus adapter 연결 지점 준비 | `tests/wiki_governance_ui_test_runner.gd` | 예. `StrategicMap.focus_city(province_id)` |
| 28. 도시 목록과 전체 관리 창 | Partially implemented | `StrategyReadModel::city_rows/_city_matches_filter/_city_sort_value`; `main.gd::_refresh_city_list` | 검색·다중 선택·일괄 정책·표시 열/폭 설정·전체 화면 관리 창 | 도시명/인구/경제/행복/안정/반란/점령/통치/정책 정렬·필터 및 선택 연결 | `tests/wiki_governance_ui_test_runner.gd` | 예. map focus API, 대량 관리 UI 후속 |
| 29. 사용자 설정형 알림과 긴급 예외 | Partially implemented | `EpochNotificationCenter::add/mark_read`; `main.gd::_refresh_notification_center/_activate_notification` | 사건 유형별 표시 설정, 자동 일시정지/중앙 긴급 오버레이, 지도 아이콘 | 정보·주의·중요·긴급, 읽음·원인·권장 행동·dedup·toast/로그 역할 분리 | `tests/wiki_governance_ui_test_runner.gd` | 예. map overlay/게임 pause 정책 |
| 30. 턴 종료 검증 | Partially implemented | `TurnEndValidator::evaluate`; `GameSession::end_turn`; `main.gd::_request_turn_end/_refresh_turn_review` | 외교 기한·계승·즉시 사건처럼 아직 존재하지 않는 콘텐츠의 검증 | 차단/중요 확인/권고 분리, 명령·자원·주둔·반란·점령·정책·설정 상태 검사 | `tests/wiki_governance_ui_test_runner.gd` | 예. 미래 사건/외교 결정 데이터 |

## 전체 통합 위키 목차 대조

| 전체 목차 항목 | 현재 상태 | 근거 파일·함수 | 누락된 동작 | 이번 브랜치 변경 | 테스트 위치 | 추가 통합 필요 여부 |
| --- | --- | --- | --- | --- | --- | --- |
| 제0부. 문서 체계 | Implemented | `docs/design/index.html`, 본 매트릭스 | 릴리스별 자동 동기화 없음 | 이 구현 매트릭스 추가 | 문서 검토 | 아니오 |
| 제1부. 게임의 정체성 | Partially implemented | `src/main.gd`, `GameSession` | 전체 캠페인 루프·승리 조건 | 없음 | `tests/test_runner.gd` | 예. 캠페인 설계 |
| 제2부. 시대와 세계 범위 | Partially implemented | `EastAsiaWorldFoundation`, scenario data | 다수 시대/지역 콘텐츠 | 없음 | `tests/east_asia_foundation_test_runner.gd` | 예. 콘텐츠 데이터 |
| 제3부. 지도 체계 | Deferred with technical reason | `src/map/**` | 투영·렌더·입력 최종 통합 | 수정 금지 범위 | `tests/geographic_map_test_runner.gd` | 예. map 담당 브랜치 |
| 제4부. 지형 체계 | Partially implemented | `TerrainSystem`, world data | 지형 효과의 모든 전략 규칙 | 없음 | `tests/world_test_runner.gd` | 예. 지도 시스템 |
| 제5부. 정착지와 도시 | Partially implemented | `ProvinceSystem`, `StrategyReadModel` | 건설 대기열·도시 계층의 전체 규칙 | 도시 관리 상세 정보 확장 | `tests/wiki_governance_ui_test_runner.gd` | 예. 건설 시스템 |
| 제6부. 국가와 정치체 | Partially implemented | `CountrySystem`, governance profiles | 정부 개혁 전체 흐름 | 정부별 통치 옵션/임명 방식 | `tests/wiki_governance_ui_test_runner.gd` | 예. 정치 개혁 콘텐츠 |
| 제7부. 통치자와 인물 | Missing | 국가 딕셔너리의 최소 leader 필드 | 인물 생성·관계·임명·계승 | 없음 | 없음 | 예. 인물 도메인 |
| 제8부. 정통성 | Partially implemented | `ProvincialGovernance::initialize_state` | 정통성 획득/소모 규칙 및 UI | 안전 기본값/상단 선택 항목 표시 | `tests/wiki_governance_ui_test_runner.gd` | 예. 정치 규칙 |
| 제9부. 민심과 사회 안정 | Partially implemented | `StabilitySystem`, `ProvincialGovernance::_evaluate_risks` | 계층·파벌·사회 사건 | 도시 행복/안정/불안과 반란 위험 결합 | `tests/wiki_governance_ui_test_runner.gd` | 예. 사회 이벤트 |
| 제10부. 문화와 민족 | Partially implemented | `ProvincialGovernance::_advance_assimilation` | 문화권/민족 집단의 독립 데이터 | 문화 융화 수치와 정책 | `tests/wiki_governance_ui_test_runner.gd` | 예. 문화 데이터 |
| 제11부. 종교와 신앙 | Missing | 없음 | 신앙·사원·종교 외교 | 없음 | 없음 | 예. 별도 도메인 |
| 제12부. 경제 | Partially implemented | `EconomySystem`, `ProvincialGovernance::apply_economic_effects` | 교역망·가격·자원 시장 | 점령/통치 세수·생산 보정 | `tests/wiki_governance_ui_test_runner.gd` | 예. 경제 확장 |
| 제13부. 기술과 발전 | Missing | 개발 수치만 존재 | 연구 트리·발명·확산 | 없음 | 없음 | 예. 기술 도메인 |
| 제14부. 군사 조직 | Partially implemented | `MilitarySystem`, `StrategicMilitarySystem` | 편제·지휘·보급의 전체 UI | 점령지 보충 및 주둔군 위험 반영 | `tests/strategic_military_test.gd` | 예. 군사 UI |
| 제15부. 병종 | Partially implemented | army units data, `StrategicMilitarySystem` | 병종 상성/모집 다양성 | 없음 | `tests/strategic_military_test.gd` | 예. 콘텐츠 |
| 제16부. 전투 | Implemented | `BattleSystem::resolve_attack` | 전투 시각화·전술 선택 | 없음 | `tests/test_runner.gd` | 예. presentation |
| 제17부. 공성전 | Missing | fort level의 최소 수치 | 공성 규칙·보급·항복 | 없음 | 없음 | 예. 전투 확장 |
| 제18부. 전쟁 | Implemented | `DiplomacySystem`, `PeaceSystem`, `BattleSystem` | 전쟁 목표·전쟁 피로도 | 점령 단계가 전시 통제와 연결 | `tests/test_runner.gd`, `tests/wiki_governance_ui_test_runner.gd` | 아니오 |
| 제19부. 외교 | Partially implemented | `DiplomacySystem`, `NegotiationSystem` | 외교 결정 UI·기한 이벤트 | 점령 외교 분쟁 수치 기록 | `tests/test_runner.gd` | 예. 외교 UI |
| 제20부. 종속국과 식민지 | Missing | vassal 명령의 최소 경로 | 지속 종속국·식민지 경제/외교 | 없음 | `tests/test_runner.gd` | 예. 외교 도메인 |
| 제21부. 점령과 통합 | Implemented | `ProvincialGovernance`, data-driven rules | 단계별 내러티브 이벤트 | 단계적 편입·융화·저장·UI·검증 | `tests/wiki_governance_ui_test_runner.gd` | 아니오 |
| 제22부. 해상 체계 | Missing | 없음 | 해역·함대·항구·해상 교역 | 없음 | 없음 | 예. map/군사/경제 |
| 제23부. AI 체계 | Partially implemented | `AIDirector`, planners | 통치/융화/위기 대응 AI | 없음 | `tests/test_runner.gd` | 예. AI 정책 |
| 제24부. 플레이어 인터페이스 | Partially implemented | `main.gd`, `ProjectEpochUiFactory`, theme | 모든 화면의 세부 일관성 및 전체 도시 관리 창 | 테마 variant, 상단 바, 도시 패널, 목록, 알림, 턴 검토 | `tests/main_runtime_test_runner.gd`, `tests/wiki_governance_ui_test_runner.gd` | 예. map focus/UI visual QA |
| 제25부. 게임 흐름 | Partially implemented | `GameSession`, `StrategyGateway`, `main.gd` | 사건/결정 흐름과 게임 종료 | 턴 검토·강제 진행·자동 저장 연결 | `tests/main_runtime_test_runner.gd` | 예. 이벤트 시스템 |
| 제26부. 시나리오와 역사 데이터 | Partially implemented | `data/scenarios/**`, loaders | 역사 시나리오 폭과 검증 도구 | v2 migration 안전 기본값 | `tests/east_asia_foundation_test_runner.gd`, `tests/wiki_governance_ui_test_runner.gd` | 예. 데이터 콘텐츠 |
| 제27부. 밸런스 원칙 | Missing | balance JSON의 최소 수치 | 시뮬레이션 기반 밸런스 지표/자동 검사 | 통치·점령 수치를 data-driven으로 분리 | 없음 | 예. 밸런스 도구 |
| 제28부. 데이터와 구현 구조 | Partially implemented | `ARCHITECTURE.md`, `GameState`, gateway/presenter | 전체 스키마 검증·컨텐츠 migration 체계 | core→gateway→UI 경계 및 v2 호환 migration | `tests/readable_boundaries_test_runner.gd`, `tests/wiki_governance_ui_test_runner.gd` | 아니오 |
| 제29부. 배포판 기준 | Deferred with technical reason | `project.godot`, test runners | 패키징·성능 예산·플랫폼 QA 기준 | 새 runner만 추가, 기존 전체 runner 변경 안 함 | headless runners | 예. 릴리스/CI 책임자 |

## 이번 브랜치의 map 통합 계약

`src/main.gd::_focus_city_adapter(province_id)`는 새 지도 API가 있으면 `StrategicMap.focus_city(province_id)`를 호출하고, 병합 전에는 기존 `focus_province(province_id)`로 폴백한다. 지도 담당 브랜치는 다음 호환 API를 제공하면 도시 목록·알림·턴 검토의 “이동” 행동이 자동으로 더 정밀해진다.

```gdscript
func focus_city(province_id: int) -> void
```

이 문서는 map 파일을 변경하지 않으며, 병렬 map 작업이 병합된 뒤 해당 API의 존재를 headless smoke test와 실제 1280×720/1920×1080 플레이 검수로 확인해야 한다.
