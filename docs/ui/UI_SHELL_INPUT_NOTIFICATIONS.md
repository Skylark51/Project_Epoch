# 전역 UI Shell · 입력 · 알림 통합

구현 기준은 Project Epoch 설계 위키 v0.4의 질문 21, 26, 27, 29, 30이다.
기존 전략 지도, 게임 데이터, 통합 세이브, 통치 대시보드와 도시 UI의 소유권은
그대로 유지하고, 전역 인터페이스만 느슨하게 연결한다.

## 모듈 경계

- `src/ui/configurable_top_bar.gd`: 사용자 설정형 상단 정보 바와 설정 창
- `src/ui/top_bar_data_adapter.gd`: 코어 스냅샷을 표시 데이터로 안전하게 변환
- `src/ui/ui_shell_preferences.gd`: `user://ui_shell_preferences.json` 버전 1 저장·복구
- `src/input/map_input_router.gd`: 지도 키보드 입력, 도시 순환, 가장자리 이동
- `src/presentation/city_navigation_adapter.gd`: Codex 2 도시 목록과의 공용 계약
- `src/ui/notification_center.gd`: 알림 규칙, 묶기, 읽음 상태, 위기 카드, 이동
- `src/ui/notification_presenter.gd`: 알림 목록, 배너, 중앙 확인창
- `src/ui/notification_sound_player.gd`: 경고 알림용 내장 생성음
- `src/ui/turn_end_guard.gd`: 종료 차단·경고 분류 및 동일 유형 묶기
- `src/ui/turn_end_dialog.gd`: 위치 이동, 이번 턴 무시, 그대로 종료 UI

`src/main.gd`는 위 모듈을 조립하고 코어 턴 실행으로 연결한다. 도시 패널 내부,
도시 외형, 도시 목록·검색·정렬 UI는 구현하거나 변경하지 않는다.

## 상단 정보 바

기본 표시 항목은 연도·계절, 국고, 핵심 자원, 전쟁 상태다. 긴급 알림 수와 턴
종료 버튼은 항상 노출한다. 선택 항목은 총인구, 평균 행복도·안정도, 행정력,
정통성, 군사력, 영향권 성장, 반란 위험 도시 수, 점령지, 종속국 충성도, 연구
진행도다.

항목은 상단 바에서 직접 드래그하여 재정렬한다. `⚙` 설정 창에서 표시 여부,
상세형·간략형, 가장자리 이동, 알림 중요도별 출력 채널을 바꾼다. 화면 폭이
부족하면 간략형으로 바뀌고 그래도 넘치는 선택 항목은 `+N`으로 접힌다.
숨긴 항목이 위험 상태이면 별도 경고 문구가 남는다.

데이터 어댑터는 존재하는 코어 필드만 표시한다. 아직 코어가 제공하지 않는
항목은 수치를 만들어내지 않고 `—`로 표시한다. 기존 캠페인 세이브에는 UI
설정을 삽입하지 않으므로 세이브 버전 2와 호환된다. UI 설정 JSON이 깨지면
필수 항목이 포함된 기본값으로 복구한다.

## 지도 입력

- 휠: 마우스 위치 기준 연속 확대·축소
- `전략` / `지역` / `근접`: 의미상 정보 단계 즉시 전환
- 방향키: 도시 미선택 시 지도 이동
- `WASD`: 지도 이동
- 가운데 버튼 또는 기존 우클릭 드래그: 지도 이동
- `Alt+1` / `Alt+2` / `Alt+3`: 전략·지역·근접 단계
- `Shift+A`: 기존 공격 명령 준비 (`A`는 WASD 지도 이동에 양보)
- `Home`: 전체 지도

`LineEdit`, `TextEdit`, `SpinBox`에 포커스가 있으면 전역 방향키·WASD를
소비하지 않는다. 가장자리 이동은 기본적으로 꺼져 있고 UI 설정에서 켠다.
기존 미니맵 구현은 없지만 `StrategicMap.center_from_minimap(Vector2)` 계약을
제공하여 정규화 좌표 클릭 이동을 바로 연결할 수 있다.

## Codex 2 도시 UI 연결 계약

Codex 2의 도시 목록 제공 객체를 다음처럼 등록한다.

```gdscript
main.set_city_ui_provider(city_ui_provider)
```

제공 객체는 snake_case 또는 기존 권장 camelCase 중 하나를 구현하면 된다.

```text
get_ordered_city_ids() / getOrderedCityIds()
get_selected_city_id() / getSelectedCityId()
select_city_by_id(city_id) / selectCityById(cityId)
focus_camera_on_city(city_id) / focusCameraOnCity(cityId)
clear_city_selection() / clearCitySelection()  # 선택 사항
```

`CityNavigationAdapter.city_selection_requested(city_id)` 신호를 도시 패널 갱신에
연결한다. 어댑터는 패널 탭을 변경하지 않으므로 현재 탭이 유지된다. 제공자가
아직 없으면 실제 지도 도시 좌표를 서쪽→동쪽, 동일 경도에서는 북쪽→남쪽으로
정렬한 목록을 fallback으로 사용하며 임시 도시 UI는 만들지 않는다.

## 알림 입력 계약

게임 시스템은 메인 런타임의 다음 API로 알림을 보낸다.

```gdscript
main.push_game_notification({
    "kind": "food_decline",
    "severity": "caution",
    "title": "식량 감소",
    "message": "서울의 식량이 감소했습니다.",
    "city_id": "seoul",
    "target": {"type": "city", "id": "seoul"}
})
```

중요도는 `info`, `caution`, `warning`, `urgent`, `decision_required`다. 출력
채널은 `list`, `banner`, `map_icon`, `sound`, `auto_pause`, `modal`이다. 규칙은
중요도 기본값과 사건 `kind`별 재정의를 지원한다. 긴급·결정 필요 사건은 모든
채널을 끌 수 없으며 최소 목록과 중앙 확인창으로 복구된다.

동일 `kind`·도시·위치 알림은 반복 횟수로 묶이고 같은 도시의 주의 이상 알림은
도시 위기 카드로 함께 표시된다. `decision_required`는 읽음 처리만으로 해결되지
않으며 원 시스템이 `NotificationCenter.resolve(id)`를 호출할 때까지 턴을 막는다.

## 턴 종료 검증 계약

외부 시스템은 다음 API로 현재 미처리 항목을 전달한다.

```gdscript
main.set_turn_validation_items([
    {
        "id": "succession:1",
        "type": "mandatory_succession",
        "message": "후계자를 선택해야 합니다.",
        "target": {"type": "city", "id": "seoul"},
        "auto_governed": false
    }
])
```

차단 유형과 경고 유형은 `TurnEndGuard.BLOCKING_TYPES`,
`TurnEndGuard.WARNING_TYPES`에 위키 기준대로 선언되어 있다. 같은 유형은 한
행으로 묶인다. `auto_governed=true` 항목은 제외한다. 차단 항목을 해결한 시스템은
`main.resolve_turn_validation_item(id)`를 호출한다. 일반 경고는 이번 턴만 무시한
뒤 종료할 수 있지만 결정 필요 알림과 차단 항목은 해결 전까지 종료할 수 없다.

## 검증

```powershell
Godot_v4.6.3-stable_win64_console.exe --headless --editor --path . --quit
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/ui_shell_input_notifications_test_runner.gd
Godot_v4.6.3-stable_win64_console.exe --path . --script res://tests/ui_shell_visual_capture_runner.gd
```

시각 테스트는 1366×768과 1920×1080에서 필수 상단 항목 표시, 화면 폭,
긴급 알림·턴 종료 버튼 비중첩을 확인하고 `captures/ui_shell_*.png`를 만든다.
