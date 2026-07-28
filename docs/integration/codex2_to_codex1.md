# Codex 2 → Codex 1 통합 요구사항

UI는 코어 규칙을 복제하지 않으며 아래 계약이 제공되면 `StrategyGateway`의 로컬 JSON 어댑터를 교체합니다.

## 읽기 전용 스냅샷

필수 필드: 현재 날짜/턴, 플레이 국가 ID, 국가·Province·군대·관계·전쟁 사전. Province에는 ID, 이름, 폴리곤 또는 렌더 참조, 소유국, 점령국, 수도, 인접 ID, 인구, 경제, 개발도, 인력, 안정도/불안도, 지형, 요새, 예상 세입·모집량이 필요합니다. 국가에는 정부, 수도, 국고, 수입, 인력, 안정도, 전쟁 피로도, 외교 상태가 필요합니다.

권장 신호: `snapshot_changed`, `province_changed(ids)`, `country_changed(ids)`, `wars_changed`, `turn_resolved`, `entity_removed`. 국가 멸망·Province 삭제 시 유효하지 않은 선택 ID를 함께 알려주십시오.

## 명령 API

- `validate_command(type, payload) -> {valid, cost, warnings, normalized_payload}`
- `queue_command(type, payload) -> command_id`
- `update_command(command_id, payload)`
- `cancel_command(command_id)`
- `submit_turn(command_ids)`
- `predict_path(from_id, to_id, kind)` 및 최소 주둔군/도달 가능성
- 모집, 개발, 요새, 수도 이전, 점령지 관리 검증
- 이동·공격 충돌과 적국 공격 전 전쟁 상태 검증

명령 큐 응답에는 ID, 유형, 출발지, 목적지, 병력, 비용, 경고, 상태가 필요합니다. UI 화살표는 이 응답을 단일 진실 공급원으로 사용합니다.

## 외교·평화 API

- 관계 개선, 모욕, 전쟁 선포, 평화, 동맹, 불가침, 군사 통행, 속국화, 독립 요구의 비용·가능 여부·수락 예상치
- 양국 국력 비교, 국경 Province, 휴전/조약 만료일
- 평화 조건 평가: 요구 Province, 배상금, 속국화, 독립 승인, 협상 비용, 전쟁 점수, AI 수락 예상치
- 평화 제안 전송 및 결과 이벤트

## 턴·로그·저장

`advance_turn(commands)` 결과로 새 스냅샷과 구조화 로그를 반환해 주십시오. 로그 필드는 category(`war`, `diplomacy`, `economy`, `revolt`, `country_fall`, `occupation`, `peace`, `important`, `general`), importance, message, entity_ids를 권장합니다. 저장/불러오기/설정 UI용 슬롯 목록과 실패 사유 API도 필요합니다.

## 현재 연결 상태

`StrategyGateway`는 저장소의 JSON을 읽고 UI 명령을 `awaiting_core`로 보관하지만 게임 상태를 변경하지 않습니다. 턴 실행은 `turn_requested(commands)`를 발생시킬 뿐입니다. 이 경계 덕분에 코어 병합 전에도 전체 UI 흐름을 점검할 수 있고, 병합 시 표시 계층을 다시 작성할 필요가 없습니다.
