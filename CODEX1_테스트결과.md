# CODEX1 테스트 결과

## 환경

- Godot 4.6.3 headless
- Windows
- 통합 브랜치의 Codex 2 미커밋 파일 보존

## 명령

```powershell
Godot_v4.6.3-stable_win64_console.exe --headless --path . \
  --script res://tests/world_test_runner.gd

Godot_v4.6.3-stable_win64_console.exe --headless --path . \
  --quit-after 5 res://src/world/world_demo.tscn
```

## 통과 항목

- 월드 데이터 로드와 참조 검증
- 40개 이상 지역, 12개 이상 세력
- 한반도·중국 동부·서부 일본 지역 존재
- 평지 도시와 산성 구분
- 지형 방어·이동 비용
- 비인접 이동 거부
- 지역 보급량과 연결 보급망
- 평지성–산성 연결 보너스
- 다중 도시 선택과 일괄 건설 예약
- 3턴 진행과 인구 성장
- 건설 완료
- 도시 자동 관리
- 도로 건설
- 피해·공성·통제권 변경 API
- 건설 가능 도시 강조용 조회
- 정렬·필터·북마크
- 버전 2 저장·불러오기 동등성
- 독립 데모 씬 5프레임 런타임 실행

## 해상도

데모 UI는 앵커와 `HSplitContainer` 기반이며 1920×1080 및 1366×768을
목표로 한다. 자동 스크린샷은 headless 렌더러의 texture readback이 종료되지
않아 중단했으며, 씬 로드·5프레임 실행은 성공했다.

## 남은 검증

- 실제 모니터에서 두 해상도의 시각 회귀 캡처
- 지역 좌표와 역사 확실성에 대한 전문 검수
- Codex 2 기존 메인 지도에 대한 최종 연결
