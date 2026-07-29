# 실제 지리 기반 동아시아 월드맵

## 런타임 구조

기준 메인 씬은 계속 `res://src/main.tscn`이다. 전략 화면의 `StrategicMap`이
`WorldMapData`를 로드하며 별도 실행 씬은 만들지 않는다.

- 크기: 640×480 = 307,200타일
- 타일 표현: 사각 래스터 셀
- 청크: 16×16, 40×30 = 1,200청크
- 런타임 레이어: 지형 `Uint8` 상당의 1바이트 배열 + 프로빈스 원본 ID
  인덱스 1바이트 배열
- 전체보기: 타일 데이터에서 빌드한 640×480 LOD 텍스처
- 확대보기: 카메라와 만나는 청크 텍스처만 지연 생성 및 캐시

사각 셀을 선택한 이유는 같은 640×480 표본 수에서 해안선을 회전·전단하지 않고
가장 충실하게 보존하기 위해서다. 지도 이미지는 데이터 원본이 아니라, 동일한
타일 배열에서 생성되는 렌더 캐시다.

## 데이터와 투영

원본은 Natural Earth 1:10m `ne_10m_land.geojson`과
`ne_10m_lakes.geojson`이다. Natural Earth 데이터는 public domain이며 자세한
출처·라이선스·원본 해시는 `data/geography/geography_source.md`와 생성
manifest에 기록한다.

범위는 73°E–150°E, 15°N–55°N이다. Lambert conformal conic을 다음 기준으로
적용한다.

- 중앙 자오선: 111.5°E
- 원점 위도: 35°N
- 표준 위선: 25°N, 47°N

동일한 정·역투영은 Python 빌드 도구와 Godot `MapProjection`에 모두 구현되어
도시, 디버그 경위도, 게임 타일이 같은 좌표계를 쓴다.

## 생성 과정

```powershell
py -m pip install Pillow
py scripts/generate_east_asia_map.py
```

1. Natural Earth Polygon/MultiPolygon을 읽는다.
2. Lambert conformal conic으로 투영한다.
3. 2,560×1,920(4× supersampling) 육지·호수 마스크를 그린다.
4. 점유율을 640×480으로 축소하고 작은 구멍만 정리한다.
5. Natural Earth에서 타일 해상도 때문에 사라지는 명시적 소도서는 실제 WGS84
   좌표에 최소 1타일로 보존한다.
6. 육지 인접 바다를 얕은 바다로, 그 밖을 거리별 ocean/deep_ocean으로 나눈다.
7. 해안 타일, 분리된 지형 레이어, 전략 프로빈스 인덱스, 도시 투영 좌표,
   전체보기 PNG와 manifest를 생성한다.

지형은 현재 실제 고도·토지피복 래스터가 아니라 별도 함수로 격리된 저주파
지역 휴리스틱이다. 해안선과 호수는 실제 벡터에서 생성된다.

## 디버그 조작

- `Home`: 전체 지도
- `F6`: 타일 좌표·경위도·지형·가시 청크 패널
- `F7`: 해안 타일 강조
- `F8`: 청크 경계
- `F9`: 전략 프로빈스 원본 ID

`StrategicMap.go_to_lonlat()`로 특정 경위도 이동,
`StrategicMap.export_world_map_png()`로 전체보기 PNG 출력이 가능하다.

## 시각 검증

생성 결과는 `docs/screenshots/east_asia_world_map.png`에 저장된다. Natural
Earth 해안선을 그대로 래스터화하여 한반도 서·남해안, 요동반도·발해만,
산둥반도, 양쯔강 하구, 하이난, 대만, 홋카이도·혼슈·시코쿠·규슈, 쓰시마,
류큐, 사할린의 상대 위치를 전체보기에서 확인할 수 있다.
