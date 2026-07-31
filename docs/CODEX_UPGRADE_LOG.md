# Project Epoch 업그레이드 로그

## 2026-07-31 · CP0 감사와 기준선

### 완료한 작업

- 전체 저장소 구조, 실제 F5 진입점, Git 상태와 기존 변경을 감사했다.
- core, tile city, world demo, governance의 병렬 상태 구조를 확인했다.
- 지도 생성 데이터, Natural Earth 출처, 30만 타일 청크 구조를 확인했다.
- 국가·도시·자원·군대·외교·AI·저장 데이터와 UI 연결을 확인했다.
- 12개 발견 테스트 러너를 Godot 4.7.1로 실행했다.
- codex/strategic-game-upgrade 로컬 브랜치를 생성했다.
- CODEX_AUDIT과 CODEX_UPGRADE_PLAN을 작성했다.

### 변경한 주요 파일

- docs/CODEX_AUDIT.md
- docs/CODEX_UPGRADE_PLAN.md
- docs/CODEX_UPGRADE_LOG.md

### 실행한 검증

- Godot 4.7.1 headless editor parse: 종료 코드 0.
- 메인 장면 headless 부팅: 종료 코드 0.
- 12개 러너 최종 스윕: 모두 종료 코드 0, 총 1,278 PASS 출력.
- 핵심 별도 확인:
  - core 20턴·저장·전투·외교: 통과.
  - 전략 군사 100턴 불변식: 통과.
  - 타일 영토 80 PASS: 통과.
  - 루트 UI smoke 165 PASS: 통과.

### 발견한 문제

- 세 개의 병렬 권위 상태.
- UI–명령 계약 불일치.
- 전쟁 없는 공격, 부분 이동 무시, 보급·공성 미연결.
- 도시 생산과 코어 턴 경제 분리.
- CI 삭제 파일 참조와 Godot 버전 불일치.
- 전체 테스트 스크립트가 7개 러너를 누락.
- 테스트 공용 autosave 플래키 및 UI 리소스 누수.
- river/wetland 타일 0.
- 고정 3열 UI와 작은 화면 미지원.
- 대형 PNG 내장 SVG 중복.
- export preset 부재.

### 다음 체크포인트

CP1 실행·테스트·저장 안정화.

### 현재 막힌 사항

- 로컬 이미지 뷰어와 in-app browser 제어 런타임이 현재 세션의 Windows 샌드박스 오류로 기존 캡처를 직접 열지 못했다.
- Godot 실행과 headless 렌더 자체는 정상이며, 이후 Godot 캡처 러너로 최신 화면 증거를 생성하는 경로를 사용한다.
- 핵심 구현을 차단하는 외부 의존성은 없다.
