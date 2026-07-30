# Godot에서 직접 수정하는 방법

이 문서는 코드를 전공하지 않은 사람도 Project Epoch의 화면과 규칙을 직접 고칠 수 있도록, 수정 위치와 확인 순서를 작업 단위로 설명한다.

## 1. 프로젝트 열기

1. GitHub Desktop 또는 터미널에서 최신 브랜치를 받는다.
2. Godot 4.x Standard를 실행한다.
3. `project.godot`을 선택한다.
4. 우측 상단의 재생 버튼 또는 `F5`를 누른다.

기준 시작 장면은 `src/main.tscn`이다. 다른 장면을 따로 실행할 필요가 없다.

## 2. 수정 전 브랜치 만들기

터미널에서 다음 순서로 작업한다.

```powershell
git switch main
git pull origin main
git switch -c user/수정내용
```

예:

```powershell
git switch -c user/change-map-labels
```

수정 중 문제가 생겨도 `main`은 그대로 남는다.

## 3. 화면 문구와 배치 수정

주요 파일:

```text
src/main.gd
```

찾기 기능 `Ctrl+F`로 화면에 보이는 한국어 문구를 검색한다.

예를 들어 시작 화면 제목을 바꾸려면 `_build_start()`를 찾는다. 이 함수는 화면 위에서 아래로 나타나는 순서대로 노드를 추가한다.

```gdscript
box.add_child(_label("◆  PROJECT EPOCH  ◆", 34, ...))
box.add_child(_label("역사의 주도권은 지도 위에서 시작됩니다", 16, ...))
box.add_child(_button("새 게임", ...))
```

위에서 아래로 읽은 순서가 실제 화면 순서다.

## 4. 공통 버튼·패널 디자인 수정

주요 파일:

```text
src/ui/project_epoch_ui_factory.gd
```

여기서 바꾸면 여러 화면에 같은 규칙이 적용된다.

- 버튼 높이와 클릭 연결: `button()`
- 주요 버튼 색: `variant == "primary"`
- 위험 버튼 색: `variant == "danger"`
- 패널 배경·테두리·안쪽 여백: `style()`
- 공통 글자 크기와 색: `label()`

특정 화면 하나만 다르게 만들고 싶다면 `main.gd`에서 해당 노드에 override를 추가한다. 모든 버튼을 고치기 위해 화면마다 같은 코드를 복사하지 않는다.

## 5. 지도 색상 수정

주요 파일:

```text
src/map/strategic_map_palette.gd
```

### 지형색

`TERRAIN_COLORS`에서 수정한다.

```gdscript
"plains": Color("#7d8a63")
"forest": Color("#4f6c55")
```

### 정치·외교·전쟁 지도

`province_color()`에서 수정한다.

### 반란·안정도·요새 지도

함수 하단의 `high` 색상을 수정한다.

색상 규칙을 `strategic_map.gd`의 그리기 코드에 직접 섞지 않는다.

## 6. 지도 이동과 확대 수정

주요 파일:

```text
src/map/strategic_map_geometry.gd
```

- 최소·최대 확대 범위: `StrategicMap`의 `min_zoom`, `max_zoom`
- 마우스 위치 기준 확대 계산: `zoom_at()`
- 지도 전체 보기: `frame_world()`
- 지도 바깥으로 지나치게 이동하지 못하게 하는 범위: `clamp_pan()`

입력 버튼 자체를 바꾸려면 `src/map/strategic_map.gd`의 `Input` 구역을 수정한다.

## 7. 국가·프로빈스 집계 방식 수정

주요 파일:

```text
src/presentation/strategy_read_model.gd
```

예:

- 국가 총병력: `army_total()`
- 예상 수입: `income()`
- 국경 지역: `border_names()`
- AI 추천용 보급 점수: `supply_score()`

화면에 표시되는 합계가 이상하면 `main.gd`에서 임시로 다시 계산하지 말고 이 파일의 해당 질문을 수정한다.

## 8. 명령 연결 수정

화면 버튼의 명령이 코어에서 다른 이름으로 처리되어야 한다면 다음 파일을 수정한다.

```text
src/presentation/strategy_command_mapper.gd
```

예:

```gdscript
"fortify":
    core_type = "build_fort"
```

명령의 실제 비용과 성공 조건은 코어 시스템이 담당한다. 화면 번역기에는 게임 규칙을 넣지 않는다.

## 9. 수정 후 확인

가장 먼저 Godot 에디터에서 프로젝트를 열어 구문 오류가 없는지 확인한다.

그다음 저장소 루트의 PowerShell에서 실행한다.

```powershell
.\tools\run_all_tests.ps1 -GodotPath "C:\경로\Godot_v4.6.3-stable_win64_console.exe"
```

마지막으로 `F5`를 눌러 다음을 직접 확인한다.

1. 새 게임 진입
2. 국가 선택
3. 지도 이동과 확대
4. 프로빈스 선택
5. 모집·이동·공격 명령 예약
6. 턴 실행
7. 저장 후 불러오기
8. 통치·반란 대시보드 열기

## 10. 커밋

```powershell
git status
git diff
git add 수정한파일경로
git commit -m "수정 내용을 한 문장으로 설명"
git push -u origin 현재브랜치이름
```

커밋 메시지는 수행한 작업을 설명한다.

좋은 예:

```text
Clarify province selection feedback
Separate map palette rules
Reduce start screen visual noise
```

피할 예:

```text
수정
작업함
AI changes
```

## 11. 문제가 생겼을 때

현재 수정 파일만 되돌리기:

```powershell
git restore src/main.gd
```

아직 커밋하지 않은 전체 변경 확인:

```powershell
git status
git diff
```

다른 브랜치의 정상 파일과 비교:

```powershell
git diff main -- src/main.gd
```

파일을 삭제하거나 전체 프로젝트를 다시 생성하기 전에 반드시 `git status`와 `git diff`로 변경 범위를 먼저 확인한다.
