# 코드는 일종의 언어다

이 문서는 Project Epoch 코드베이스의 리팩터링 기준이다. 목표는 단순히 코드가 실행되는 상태가 아니라, **개발자가 읽어도 정확하고 비개발자가 따라가도 논리 전개가 보이는 상태**다.

## 1. 읽는 순서와 실행 순서를 일치시킨다

함수의 첫 부분에는 입력 확인, 중간에는 핵심 처리, 마지막에는 결과 전달을 둔다. 한 줄 안에서 여러 상태를 바꾸거나 여러 함수를 호출하지 않는다.

```gdscript
# 피한다.
commands.clear(); sync(); notice.emit("완료")

# 사용한다.
commands.clear()
sync()
notice.emit("완료")
```

## 2. 한 클래스는 하나의 이유로만 변경된다

- 화면 명령 번역이 바뀌면 `StrategyCommandMapper`를 수정한다.
- 코어 데이터의 화면 표현이 바뀌면 `StrategySnapshotPresenter`를 수정한다.
- 국가·프로빈스 집계 질문이 바뀌면 `StrategyReadModel`을 수정한다.
- 저장이나 턴 진행 순서가 바뀌면 `StrategyGateway`를 수정한다.
- 카메라와 폴리곤 계산이 바뀌면 `StrategicMapGeometry`를 수정한다.
- 지도 모드의 색상 의미가 바뀌면 `StrategicMapPalette`를 수정한다.
- 공통 버튼과 패널의 생김새가 바뀌면 `ProjectEpochUiFactory`를 수정한다.

## 3. 이름이 주석을 대신하도록 한다

`data`, `item`, `tmp`, `do_work`처럼 의미가 넓은 이름을 피한다. `core_snapshot`, `selected_province_ids`, `retained_ai_commands`처럼 값의 역할과 생명주기를 함께 드러낸다.

## 4. 주석은 동작보다 경계를 설명한다

코드를 그대로 한국어로 반복하지 않는다. 대신 이 코드가 맡는 책임, 호출자가 기대할 수 있는 계약, 다른 계층과의 경계를 설명한다.

## 5. 변환은 순수하게, 오케스트레이션은 얇게 유지한다

- 변환기: 입력을 받아 새 값을 반환한다. 파일을 읽거나 신호를 보내지 않는다.
- 읽기 모델: 현재 상태에 이름 있는 질문을 제공한다. 상태를 변경하지 않는다.
- 오케스트레이터: 변환기와 코어를 호출하고 실행 순서를 보여준다.
- UI: 상태를 표현하고 사용자 의도를 명령으로 전달한다.
- 렌더러: 그릴 위치와 순서를 결정한다. 게임 규칙을 만들지 않는다.

이 구분을 지키면 게임 규칙, 화면 표현, 저장 방식이 서로를 몰래 변경하지 않는다.

## 6. 호환 경계를 보존한다

리팩터링은 공개 메서드, 신호, 저장 포맷, 시나리오 데이터 계약을 임의로 바꾸지 않는다. 구조를 바꾸기 전에 현재 동작을 테스트로 고정한다.

이번 리팩터링에서도 다음 계약을 유지한다.

- `StrategyGateway`의 공개 메서드와 신호
- `StrategicMap`의 공개 필드, 신호, 입력 상태 enum
- `main.gd`의 `gateway`, `state`, `selected_country`, `selected_province`
- 데이터 버전 2 통합 저장 형식
- `src/main.tscn` 단일 F5 진입점

## 7. 실패 경로도 정상 경로처럼 읽혀야 한다

오류 처리를 한 줄에 압축하지 않는다. 실패 이유를 구하고, 사용자에게 전달하고, 함수를 종료하는 순서를 분명히 적는다.

## 8. 화면 구성도 문서처럼 읽혀야 한다

화면 구성 함수는 실제 화면의 위에서 아래, 왼쪽에서 오른쪽 순서대로 노드를 추가한다. 공통 스타일 생성은 `ProjectEpochUiFactory`로 이동하되, 화면의 정보 계층은 화면 코드에서 연속해서 읽을 수 있게 유지한다.

## 9. 길이는 목적이 아니라 결과다

짧은 코드가 논리를 숨긴다면 줄을 나눈다. 반대로 같은 판단을 여러 파일에서 반복한다면 이름 있는 함수나 경계 모듈로 합친다. 목표는 최소 줄 수가 아니라 **최소 추론 비용**이다.

## 10. 수정 위치가 하나로 결정되어야 한다

개발자가 요구사항을 읽었을 때 수정할 파일이 즉시 떠올라야 한다. 같은 변경을 위해 여러 계층을 동시에 고쳐야 한다면 데이터 계약이나 책임 경계를 다시 검토한다.

## 현재 적용 구조

1. `StrategyCommandMapper`: 화면 명령을 코어 프로토콜로 번역한다.
2. `StrategySnapshotPresenter`: 코어 스냅샷을 UI·지도용 읽기 모델로 변환한다.
3. `StrategyReadModel`: 국가·프로빈스 집계와 이름 있는 조회를 담당한다.
4. `StrategyGateway`: 세션 시작, 명령 제출, 턴 진행, 저장, 신호 중계를 조율한다.
5. `StrategicMapGeometry`: 카메라·폴리곤·공간 인덱스 계산을 담당한다.
6. `StrategicMapPalette`: 지도 모드의 수치와 색상 의미를 담당한다.
7. `StrategicMap`: 입력, 선택, 렌더링 순서를 조율한다.
8. `ProjectEpochUiFactory`: 반복되는 UI 생성 규칙을 담당한다.
9. `main.gd`: 전체 화면 흐름과 플레이어 의도를 조율한다.

검증 경계는 다음 테스트로 고정한다.

```text
tests/presentation_refactor_test_runner.gd
tests/readable_boundaries_test_runner.gd
tests/main_runtime_test_runner.gd
```
