# AAA UX Overhaul

## UX 원칙

Project Epoch의 핵심 조작 단위를 개별 Province 클릭에서 선택 집합과 의도 기반 작업으로 변경했다. 플레이어는 지도를 떠나지 않고 선택, 비교, 일괄 명령, 자동 관리, 검토와 취소를 수행한다.

## 지도 입력

- 클릭: 단일 Province 선택
- Shift+클릭: 선택 집합에 추가하거나 해제
- 빈 영역 드래그: 박스 안 Province 다중 선택
- Ctrl+Province 드래그: 인접 Province로 병력 이동 또는 공격 작업 생성
- 우클릭/가운데 버튼 드래그: 지도 패닝
- 휠: 마우스 위치 기준 줌
- 선택된 모든 Province는 동일한 강조선으로 표시

## Macro Builder와 One-click Management

오른쪽 Province 패널의 모집, 개발, 요새 버튼은 선택된 모든 자국 Province에 작업을 만든다. 지도 상단 Macro Toolbar는 경제 취약지, 보급 위험지, 일괄 개발, Governor, AI Assistant를 지도 위에서 즉시 실행한다. 모든 결과는 Task Queue에 표시되고 턴 실행 전 취소할 수 있다.

## Governor와 AI Assistant

Governor는 턴 실행 직전에 가장 경제력이 낮은 자국 Province에 개발 작업을 한 건 제안·예약한다. AI Assistant는 현재 스냅샷을 분석해 우선 개발 대상을 설명하고, 사용자가 추천 적용을 승인해야 Task Queue에 넣는다. AI가 소유권이나 경제 상태를 직접 변경하지 않는다.

## Overlay와 Heat Map

정치, 외교, 전쟁, 경제, 보급, 인구, 개발, 인력, 안정, 반란, 지형, 요새 뷰를 제공한다. 수치 뷰는 8–92 분위수 정규화로 극단값에 의해 전체 지도가 같은 색이 되는 문제를 줄인다. 보급 뷰는 개발도와 경제 기반 공급 능력에서 주둔군 부담을 뺀 상대 지표를 사용한다.

## Notification Center와 Task Queue

상단 알림 버튼은 누적 로그 수를 즉시 표시한다. 하단 Notification Center는 전쟁, 외교, 경제, 반란, 중요 항목을 필터링한다. Task Queue는 일괄 명령도 Province별 검증 결과로 보여주며 지도 화살표와 동기화된다.

## Steam Deck

- Start: 턴 실행
- Back: AI Assistant
- X: 선택 Province 일괄 모집
- Y: 지도 Overlay 순환
- B: 현재 명령 취소
- LB/RB: 하단 Task/Notification/War 탭 이동
- 오른쪽 스틱: 지도 패닝

버튼은 Godot 포커스 탐색을 유지하며 기존 마우스·키보드 입력과 동일한 명령 함수를 호출한다. 별도 게임 규칙을 UI에 복제하지 않는다.

## 현재 제한

코어의 군대 엔티티 분할 API가 아직 없어 UI가 병력 수를 표시하더라도 실제 코어 이동은 해당 군대 단위를 이동한다. Governor는 현재 한 턴에 개발 1건만 예약한다. 건설 템플릿 저장, 선택 그룹 단축키, 공급 경로 계산은 다음 확장 단계다.
