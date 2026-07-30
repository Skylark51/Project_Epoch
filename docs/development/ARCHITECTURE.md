# Project Epoch 코드 구조

이 문서는 현재 런타임의 책임 경계를 설명한다. 파일 목록이 아니라, **사용자 입력이 게임 결과로 이어지는 논리 순서**를 기준으로 읽는다.

## 1. 전체 흐름

```text
사용자 입력
→ main.gd가 의도를 해석
→ StrategyGateway가 실행 순서를 조율
→ StrategyCommandMapper가 코어 명령으로 번역
→ GameSession이 규칙을 검증하고 상태를 변경
→ StrategySnapshotPresenter가 화면용 상태로 변환
→ main.gd와 StrategicMap이 결과를 표현
```

각 계층은 바로 다음 계층의 공개 계약만 사용한다. 화면이 코어 내부 Dictionary를 직접 수정하거나, 렌더러가 세이브 파일을 읽는 구조를 허용하지 않는다.

## 2. 애플리케이션 계층

### `src/main.gd`

역할:

- 시작 화면, 시나리오 선택, 국가 선택, 게임 화면 조립
- 키보드·게임패드 입력을 플레이어 의도로 해석
- 선택된 프로빈스와 준비 중인 명령 상태 관리
- 화면 갱신과 알림·로그 표시

남겨 둔 책임:

화면 구성 함수는 `main.gd`에 남긴다. 화면의 정보 계층과 사용자 흐름은 한 문서처럼 연속해서 읽을 수 있어야 하기 때문이다.

밖으로 분리한 책임:

- 공통 노드 생성: `ProjectEpochUiFactory`
- 국가·프로빈스 집계 질문: `StrategyReadModel`
- 코어 실행과 저장: `StrategyGateway`

## 3. 프레젠테이션 경계

### `StrategyGateway`

세션의 오케스트레이터다.

- 시나리오 시작
- 명령 제출
- 명령 취소
- 턴 종료
- 저장·불러오기
- 코어 이벤트를 화면 신호로 중계

명령 규칙이나 화면 데이터 구조를 직접 정의하지 않는다.

### `StrategyCommandMapper`

화면 명령을 코어 프로토콜로 번역한다.

```text
fortify → build_fort
offer_alliance → form_alliance
demand_vassalization → create_vassal
peace_offer → offer_peace
```

상태와 부작용이 없는 순수 변환기다.

### `StrategySnapshotPresenter`

코어 스냅샷을 UI·지도용 읽기 모델로 변환한다.

- 코어 필드명과 화면 필드명 연결
- 프로빈스별 군대 합산
- 전쟁 배열 구성
- 실제 지도 앵커 연결

### `StrategyReadModel`

현재 화면 상태에 관해 이름 있는 질문을 제공한다.

- 특정 국가가 소유한 프로빈스
- 국가 총인구·경제·병력
- 예상 수입
- 국경 프로빈스
- 선택된 자국 프로빈스

UI가 Dictionary 순회 규칙을 반복하지 않게 한다.

## 4. 지도 계층

### `StrategicMap`

Control 노드이자 지도 표현의 오케스트레이터다.

읽는 순서:

1. 스냅샷 수신
2. 사용자 입력 처리
3. 선택·카메라 상태 변경
4. 지도 본체 렌더링
5. 전략 오버레이 렌더링
6. 툴팁과 신호 전달

### `StrategicMapGeometry`

장면 트리 없이 계산할 수 있는 기하·카메라 규칙을 담당한다.

- 화면 좌표와 월드 좌표 변환
- 마우스 기준 확대
- 카메라 프레이밍과 패닝 제한
- 폴리곤 변환과 중심 계산
- 공간 선택 버킷 구성
- 월드 경계 계산

### `StrategicMapPalette`

게임 상태가 지도에서 어떤 색과 값으로 표현되는지 결정한다.

- 정치·외교·전쟁·지형 지도 색상
- 경제·인구·개발·보급 수치
- 전쟁과 관계도 판정
- 타일의 해안 변형

## 5. UI 생성 계층

### `ProjectEpochUiFactory`

반복되는 저수준 생성 규칙을 한곳에 둔다.

- 라벨
- 버튼
- 패널 스타일
- 여백 컨테이너
- 섹션과 헤더
- 상단 통계 표시

화면 코드에는 “무엇을 보여주는가”가 남고, 테두리와 여백을 만드는 절차는 숨긴다.

## 6. 변경 규칙

| 변경하려는 것 | 수정할 위치 |
|---|---|
| 버튼 색상·패널 여백 | `ProjectEpochUiFactory` |
| 국가 총병력 계산 | `StrategyReadModel` |
| 화면 명령의 코어 명령명 | `StrategyCommandMapper` |
| 코어 필드의 화면 필드 변환 | `StrategySnapshotPresenter` |
| 저장·턴 실행 순서 | `StrategyGateway` |
| 카메라 계산 | `StrategicMapGeometry` |
| 지도 모드 색상 | `StrategicMapPalette` |
| 지도 클릭·드래그 경험 | `StrategicMap` |
| 화면의 정보 배치와 플레이 흐름 | `main.gd` |

하나의 변경이 표의 여러 행을 동시에 수정하게 된다면 경계가 무너지고 있는지 먼저 검토한다.

## 7. 검증

전체 검증:

```powershell
.\tools\run_all_tests.ps1 -GodotPath "C:\경로\Godot_v4.6.3-stable_win64_console.exe"
```

새 경계만 빠르게 검증:

```powershell
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/presentation_refactor_test_runner.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/readable_boundaries_test_runner.gd
```
