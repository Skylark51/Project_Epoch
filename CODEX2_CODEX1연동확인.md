# Codex 1 연동 확인

사용 필드: Province `id/owner_id/controller_id/neighbors/terrain/fort_level`; 선택 필드 `capital/port/road/food_storage/city/mountain_fort`. 누락 시 안전 기본값을 쓴다. `GameSession` 공개 스냅샷과 기존 command queue 계약을 유지한다.

대기 API: 서기 400년 실제 도시 ID, 산성 연결, 도로·수운·항만 그래프, 자원 재고, 계절/날씨, 기술·건물 요구 검증. 이 데이터가 제공되면 시스템을 재작성하지 않고 공급원 및 모집 조건에 연결한다.
