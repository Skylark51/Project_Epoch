# 기존 구조 분석

- 공개 경계는 `GameSession`; UI는 스냅샷 읽기와 명령 제출만 수행한다.
- 기존 군대는 Province별 `soldiers`, morale, organization, supply 중심 단일 엔티티였다.
- 턴은 검증→외교→행정→모집→이동→전투→점령→평화→경제→인력→성장→안정→붕괴→사건→AI→날짜→저장 순이었다.
- 정확한 `CODEX1_CODEX2연동명세.md`와 서기 400년 지도 브랜치는 조사 시점에 존재하지 않았다. 기존 `docs/integration/codex1_to_codex2.md`를 기준으로 구현했다.
- 새 시스템은 Province ID와 owner/controller/neighbors/terrain을 보존하고 선택적 city/port/road/fort 필드를 읽는다.
