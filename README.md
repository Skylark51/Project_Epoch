# Project Epoch

고대 동아시아를 배경으로 한 Godot 기반 대전략 게임 프로토타입입니다. 역사의 시대 계열의 빠른 영토 전략과 문명 계열의 도시·도로·외교·제도 운영을 참고하되, 코드·지도·UI·데이터는 독립적으로 제작합니다.

현재 기준 설계는 작은 촌락·부족·호족 세력에서 시작해 국가와 왕조를 건설하고, 한반도·중국·일본의 여러 세력과 경쟁하는 장기 캠페인입니다.

## 실행

1. `git pull origin main`
2. 프로젝트 폴더의 `.godot` 캐시를 삭제
3. Godot 4.x Standard에서 `project.godot` 열기
4. `F5` 실행

기본 실행 진입점은 `res://src/main.tscn`입니다.

## 현재 프로젝트 구조

```text
data/world/          고대 동아시아 지역·세력·취락·건물 데이터
data/governance/     통치체제·정치집단·통제율·반란·협상 규칙
src/world/           월드 세션·취락·도로·영향권 시스템
src/core/            명령·턴·세이브의 기존 코어
src/systems/         경제·군사·통치·반란·협상 시스템
src/governance/      GovernanceSession 통합 파사드
src/map/             전략 지도 렌더링과 입력
src/presentation/    UI와 게임 코어 사이의 어댑터
src/main.gd           화면 조립과 플레이 흐름
tests/                Godot headless 테스트 러너
docs/design/          설계 위키와 구현 명세
```

## 확정된 지도 구조

지도는 프로빈스와 핵심 지점을 결합한 혼합형입니다.

- 영유권·행정·세금·문화·민심·인구·자원은 프로빈스 단위
- 중심 도시·요새·관문·항구·나루·광산·교차로는 핵심 지점 단위
- 프로빈스당 핵심 지점은 평균 5~8개
- 군대의 평시 이동은 프로빈스 단위
- 공성·관문전·나루전·상륙·보급 차단 때 내부 지점을 사용

중심 도시를 점령했다고 프로빈스가 즉시 편입되지는 않습니다. 군사 통제율과 정치적 귀속을 분리하며, 이름 있는 지방 통치자의 항복·도주·저항·봉신 요청과 평화조약을 함께 판정합니다.

## 통치체제와 개혁

국가는 원칙적으로 하나의 기본 통치체제를 가집니다.

- 부족연맹제
- 귀족연합정
- 봉건제
- 군사총독제
- 군현제
- 전제 관료제

통치체제는 메뉴에서 즉시 교체하지 않고 국가 개혁으로 변경합니다.

1. 준비
2. 시행
3. 정착

개혁 반발에는 협상·매수·숙청·군사 진압으로 대응할 수 있습니다. 정착에 실패하면 명목상 제도와 실제 지방 통치가 분리된 이중 체제 상태가 됩니다.

## 정치 집단과 반란

기본 정치 집단은 귀족·군부·관료·종교 세력·지방민입니다.

플레이어에게는 정확한 내부 수치 대신 단계가 표시됩니다.

- 영향력: 미약 → 약함 → 보통 → 강함 → 압도적
- 만족도: 격렬한 반발 → 불만 → 중립 → 만족 → 적극 지지
- 반란 위험: 안정 → 주의 → 불안 → 위험 → 임박
- 다음 단계 근접도: 멀음 → 진행 중 → 절반 이상 → 임박 → 다음 턴 변동 가능

태도는 턴마다 점진적으로 변합니다. 기본 화면에는 단계 변화와 중대한 원인만 알리고, 상세 화면에서는 최근 10턴의 변화와 요구를 확인합니다.

공동반란은 둘 이상의 불만 집단, 강한 영향력 집단, 공통 명분, 중앙정부 위기, 병력·거점·연락망 등 복합 조건이 겹쳐야 발생합니다. 공동반란에 참여한 집단은 하나의 국가로 합쳐지지 않고 각자 별도 반란 세력으로 움직입니다.

## 반란국가와 협상

반란 점령지는 즉시 국가가 되지 않습니다. 프로빈스·인구·생존 기간·병력·식량·지지·이름 있는 지도자·중심 거점·정치적 명분·세금 징수 능력 등을 충족해야 정식 국가를 선포합니다.

국호와 수도는 AI가 자동으로 결정하되 역사적 후보를 우선합니다.

독립 협상은 다음 단계로 진행합니다.

1. 협상 개시
2. 핵심 요구
3. 수정안
4. 최종 합의

협상 개시만으로 전투는 멈추지 않습니다. 휴전 기간, 적용 범위, 병력 이동, 증원, 징병, 성벽 보수, 보급 비축, 포로 교환 조건을 별도로 제안하고 합의해야 합니다.

## 통치·반란 모듈 사용

```gdscript
const GovernanceSession = preload("res://src/governance/governance_session.gd")

var governance := GovernanceSession.new()

governance.governance_changed.connect(_on_governance_changed)
governance.governance_alert.connect(_on_governance_alert)
governance.rebellion_started.connect(_on_rebellion_started)
```

세부 연동 방법은 다음 문서를 기준으로 합니다.

- `docs/design/GOVERNANCE_REBELLION_IMPLEMENTATION.md`
- `docs/design/역사의시대2_게임설계_통합위키.txt`

이번 시스템은 기존 `src/main.gd`와 지도 UI를 덮어쓰지 않는 독립 모듈로 추가되었습니다. 기존 `WorldSession` 또는 `StrategyGateway`가 `GovernanceSession`을 소유하도록 연결하면 됩니다.

## 테스트

기존 월드 테스트:

```powershell
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/world_test_runner.gd
```

통치·반란 테스트:

```powershell
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/governance_rebellion_test_runner.gd
```

통치·반란 테스트 러너는 다음을 검증합니다.

- JSON 정의 로드
- 프로빈스 통제율과 지방 통치자 결정
- 3단계 통치체제 개혁
- 단계형 정치 집단 상태
- 복합 공동반란 조건
- 집단별 별도 반란 생성
- 정식 국가 선포 조건
- 역사적 국호·수도 우선 선택
- 단계형 독립 협상
- 휴전 제안과 위반 판정

## 현재 후속 과제

- 기존 게임 화면에 정치 집단 상세 탭 연결
- 월드 세이브에 통치·반란 상태 병합
- 역사적 지방 통치자 데이터 작성
- 통치체제별 밸런스 조정
- 휴전 중 병력 재배치의 기본 제한 확정
- Godot 런타임 및 CI 검증
