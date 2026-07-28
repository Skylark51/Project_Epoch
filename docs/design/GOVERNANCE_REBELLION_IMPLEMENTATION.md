# 통치체제·프로빈스 통제·반란 시스템 연동 명세

이 문서는 `역사의시대2_게임설계_통합위키`의 확정 내용을 실제 Godot 코드와 연결하기 위한 기준이다.

## 1. 구현 범위

이번 모듈은 다음을 담당한다.

- 프로빈스와 5~8개 핵심 지점을 결합한 혼합 지도 모델
- 군사 통제율과 정치적 귀속의 분리
- 모든 프로빈스의 이름 있는 통치자
- 국가 단일 통치체제
- 준비 → 시행 → 정착의 3단계 개혁
- 귀족·군부·관료·종교 세력·지방민 집단 정치
- 단계형 영향력·만족도·반란 위험·근접도
- 복합 조건에 의한 공동반란
- 공동반란 참여 집단의 별도 세력화
- 반란 점령지 → 정식 국가 선포
- 역사적 국호·수도 자동 우선 선택
- 단계형 독립 협상
- 별도 합의가 필요한 휴전

## 2. 파일 구조

```text
data/governance/
  government_types.json
  political_groups.json
  province_control.json
  rebellion_rules.json

src/systems/
  stage_scale.gd
  province_control_system.gd
  governance_reform_system.gd
  rebellion_system.gd
  negotiation_system.gd

src/governance/
  governance_session.gd

tests/
  governance_rebellion_test_runner.gd
```

## 3. 기존 월드 세션 연동

기존 `WorldSession` 또는 `StrategyGateway`가 `GovernanceSession`을 소유한다.

```gdscript
const GovernanceSession = preload("res://src/governance/governance_session.gd")

var governance := GovernanceSession.new()

governance.governance_changed.connect(_on_governance_changed)
governance.governance_alert.connect(_on_governance_alert)
governance.rebellion_started.connect(_on_rebellion_started)
```

시나리오 로드 후 국가·프로빈스·집단을 등록한다.

```gdscript
governance.register_faction({
    "faction_id": "GOG",
    "government_type": "aristocratic_council",
    "authority_hidden": 62,
    "legitimacy_hidden": 70,
    "administration_capacity": 45,
    "treasury": 1200,
    "technology_tags": ["council_law"]
})

governance.register_province({
    "province_id": "GOG_DOMESTIC",
    "name": "국내성 권역",
    "owner_faction_id": "GOG",
    "controller_faction_id": "GOG",
    "control_progress_hidden": 100,
    "governor_character_id": "CHAR_GOV_001",
    "governor_type": "appointed_governor",
    "core_settlement_id": "SET_GUNGNAE",
    "strategic_point_ids": ["SET_GUNGNAE", "FORT_HWANDO", "FORD_YALU", "MINE_IRON_01", "ROAD_JUNCTION_01"]
})
```

## 4. 턴 처리 순서

권장 순서:

1. 외교·전쟁 명령 확정
2. 군대 이동과 전투
3. 공성 및 핵심 지점 소유권 갱신
4. 프로빈스 군사 통제율 계산
5. 지방 통치자 결정
6. 세금·식량·인구·재난 처리
7. 정치 집단 만족도와 반란 위험 갱신
8. 개혁 단계 진행
9. 공동반란 조건 검사
10. 반란 세력별 행동
11. 반란국가 선포 조건 검사
12. 협상·휴전 만료 및 위반 검사
13. 단계 변화 알림 생성
14. 자동 저장

## 5. 프로빈스 통제

`ProvinceControlSystem.evaluate_control()`은 숨겨진 0~100 수치를 계산한다.

플레이어에게는 다음 단계만 표시한다.

- 미확보
- 교두보
- 분쟁
- 우세
- 사실상 장악
- 완전 통제

중심 도시를 점령해도 정치적 귀속은 자동 변경하지 않는다. 통제율과 지방 통치자의 결정, 평화조약을 함께 확인한다.

```gdscript
var control = governance.update_province_control(
    "P_LIAODONG",
    {
        "core_city_held": true,
        "major_forts_held": 1,
        "minor_points_held": 2,
        "supply_connected": true,
        "road_connected": true,
        "active_resistance": true,
        "occupation_turns": 2,
        "occupation_policy": "relief"
    },
    governor_data,
    war_context
)
```

## 6. 통치체제와 개혁

국가는 하나의 기본 통치체제를 가진다.

- 부족연맹제
- 귀족연합정
- 봉건제
- 군사총독제
- 군현제
- 전제 관료제

통치체제 변경은 즉시 선택이 아니라 개혁으로 처리한다.

```gdscript
var result = governance.start_reform("GOG", "commandery_county", world_context)
```

개혁은 다음 단계를 순서대로 거친다.

1. 준비
2. 시행
3. 정착

정착 실패 시 `dual_system = true`가 되어 명목상 제도와 실제 지방 통치가 분리된다.

개혁 반발 대응:

```gdscript
governance.respond_to_reform_opposition("GOG", "negotiate", "aristocracy")
governance.respond_to_reform_opposition("GOG", "bribe", "military")
governance.respond_to_reform_opposition("GOG", "purge", "aristocracy")
governance.respond_to_reform_opposition("GOG", "suppress", "local_populace")
```

## 7. 정치 집단 UI

기본 화면에는 단계 변화와 중대 사건만 알린다.

상세 화면에는 다음을 표시한다.

- 영향력 단계
- 만족도 단계
- 반란 위험 단계
- 다음 단계 근접도
- 최근 10턴 변화
- 주요 원인
- 추세
- 요구 사항
- 개혁 태도
- 정부 대응 기록

```gdscript
var detail = governance.group_detail("GOG", "aristocracy")
```

숨겨진 수치는 디버그 모드 외에는 UI에 직접 노출하지 않는다.

## 8. 공동반란

공동반란은 복합 요건을 필요로 한다.

- 불만 집단 2개 이상
- 강한 영향력 집단 1개 이상
- 공통 반대 명분
- 중앙정부 위기
- 반란 거점·병력·비밀망 중 하나 이상
- 핵심 요구의 양립 가능성

조건을 충족해도 하나의 통합 반란국이 아니라 집단별 별도 반란 세력이 생성된다.

예:

- 귀족 반란군
- 군부 반란군
- 종교 반란군
- 지방민 반란군

이들은 중앙정부를 공동의 적으로 보지만 점령지·수도·차기 군주 문제로 상호 충돌할 수 있다.

## 9. 국가 선포

반란 점령지는 즉시 국가가 되지 않는다.

기본 요건은 데이터 파일에서 조정한다.

- 프로빈스 2개
- 인구 25,000명
- 4턴 생존
- 병력 1,500명
- 식량 1,200
- 지지 수치 55 이상
- 이름 있는 지도자
- 중심 도시 또는 핵심 요새
- 정치적 명분
- 세금 징수 능력

국호 우선순위:

1. 역사적 지역 국가
2. 가문·부족 국호
3. 복위 왕조
4. 역사적 수도명
5. 생성형 국호

수도 우선순위:

1. 역사적 중심지
2. 지도자 본거지
3. 옛 수도
4. 방어 도시
5. 교통·식량 중심지

## 10. 단계형 독립 협상

협상은 다음 순서로 진행한다.

1. 협상 개시
2. 핵심 요구
3. 수정안
4. 최종 합의

협상 중에도 전투는 계속된다. 전투를 중지하려면 별도의 휴전 합의가 필요하다.

```gdscript
var negotiation = governance.begin_negotiation("REB_01", "GOG", {"deadline_turns": 4})

governance.propose_negotiation_demands(
    negotiation.negotiation_id,
    "REB_01",
    [
        {"type": "state_name", "value": "진국"},
        {"type": "tax_rights", "scale": 0.8}
    ],
    leverage_context
)
```

## 11. 휴전

휴전 제안 필드:

- 기간
- 적용 범위
- 병력 이동 정책
- 증원 허용
- 징병 허용
- 성벽 보수 허용
- 보급 비축 허용
- 포로 교환
- 종료 후 전쟁 자동 재개

병력 이동 정책 값:

- `prohibited`: 모든 이동 금지
- `limited`: 전선 통과 금지
- `rear_only`: 후방 재배치만 허용
- `unrestricted`: 이동 허용

세부 제한은 데이터화되어 있으므로 후속 논의 후 수치와 기본값을 교체할 수 있다.

## 12. 저장 데이터

세이브 파일에는 다음을 포함한다.

```text
factions[*].government_type
factions[*].active_reform
factions[*].dual_system
provinces[*].control_progress_hidden
provinces[*].control_stage
provinces[*].governor_character_id
provinces[*].governor_decision
political_groups
rebellions
negotiations
alerts
```

기존 세이브 버전과 충돌하지 않도록 저장 버전을 올리고 마이그레이션 함수를 둔다.

## 13. 테스트

Godot 설치 환경에서 실행:

```powershell
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/governance_rebellion_test_runner.gd
```

검증 항목:

- JSON 정의 로드
- 프로빈스 통제율 변화
- 지방 통치자 결정
- 3단계 개혁
- 집단 단계 표시
- 복합 공동반란 조건
- 집단별 별도 반란 생성
- 정식 국가 선포
- 역사적 국호·수도 우선 선택
- 단계형 협상
- 휴전 위반 판정
