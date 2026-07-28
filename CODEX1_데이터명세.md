# CODEX1 데이터 명세

## `data/world/regions.json`

필수 필드:

`id`, `historical_name`, `display_name`, `modern_reference`, `region_group`,
`terrain`, `elevation_class`, `river`, `coast`, `resource_tags`,
`initial_controller`, `initial_settlement`, `historical_certainty`,
`adjacent_region_ids`, `x`, `y`.

`x`, `y`는 UI용 상대 좌표다. 역사적 위치 확정값으로 사용하지 않는다.

## `factions.json`

`faction_id`, `name`, `capital`, `government_type`, `culture_group`,
`starting_resources`, `starting_technology`, `diplomacy`, `color`,
`emblem_placeholder`, `ai_profile`, `unique_modifiers`.

## `buildings.json`

```json
{
  "id": "farmland",
  "name": "농경지",
  "cost": {"wood": 20, "wealth": 15},
  "upkeep": {},
  "turns": 2,
  "requires": [],
  "terrains": ["plains", "river"],
  "effects": {"food": 18}
}
```

`requires`에는 취락 단계 또는 건물 ID가 들어간다. `terrains`가 비어 있으면
모든 지형에서 건설할 수 있다.

## 저장

- 파일: 기본 `user://epoch_world_v2.json`
- 버전: `save_version = 2`
- 기존 Province 세이브와 의도적으로 분리
- 버전이 다르면 모호하게 복원하지 않고 명시적 비호환 오류 반환

저장 항목은 지역, 취락, 세력, 지형·건물 정의 스냅샷, 연결망, 영향력,
건설 대기열, 자동 관리 정책, 카메라 북마크와 디버그 로그다.
