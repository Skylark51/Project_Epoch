extends Control


enum ScreenState {
    START,
    SCENARIO,
    COUNTRY,
    GAME
}


const MAP_MODES := [
    ["political", "정치"],
    ["relations", "외교"],
    ["war", "전쟁"],
    ["economy", "경제"],
    ["supply", "보급"],
    ["population", "인구"],
    ["development", "개발"],
    ["manpower", "인력"],
    ["stability", "안정"],
    ["revolt", "반란"],
    ["terrain", "지형"],
    ["fort", "요새"]
]

const LOG_LIMIT := 120
const ProjectEpochUiFactoryScript = preload(
    "res://src/ui/project_epoch_ui_factory.gd"
)
const StrategyReadModelScript = preload(
    "res://src/presentation/strategy_read_model.gd"
)


# Application state ----------------------------------------------------------

var gateway := StrategyGateway.new()
var read_model
var state := ScreenState.START

var selected_country := "goguryeo"
var selected_province := -1
var selected_provinces: Array[int] = []

var pending_sources: Array[int] = []
var pending_source := -1
var pending_kind := ""
var pending_amount := 0
var peace_demands: Array[int] = []

var governor_enabled := false
var map_mode_index := 0
var logs: Array[Dictionary] = []


# Constructed UI references --------------------------------------------------

var screens: Dictionary = {}
var maps: Dictionary = {}
var ui: Dictionary = {}

var move_dialog: Window
var diplomacy_dialog: Window
var peace_dialog: Window
var toast: PanelContainer
var toast_timer: Timer


# Lifecycle ------------------------------------------------------------------

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _apply_project_theme()

    read_model = StrategyReadModelScript.new(gateway)
    _build_screens()
    _connect_gateway_signals()
    _load_initial_catalog()

    _show(ScreenState.START)
    get_viewport().size_changed.connect(_on_resize)


func _apply_project_theme() -> void:
    var epoch_theme = load("res://themes/project_epoch_theme.tres")
    if epoch_theme is Theme:
        theme = epoch_theme


func _connect_gateway_signals() -> void:
    gateway.snapshot_changed.connect(_sync_snapshot)
    gateway.command_queue_changed.connect(_rebuild_queue)
    gateway.integration_notice.connect(_on_integration_notice)
    gateway.turn_requested.connect(_on_turn_requested)
    gateway.turn_requested.connect(_before_turn)


func _load_initial_catalog() -> void:
    if not gateway.load_local_catalog():
        _notify("기본 JSON 데이터를 불러오지 못했습니다.", "error")
        return

    selected_country = String(
        gateway.snapshot().get("player_country_id", "goguryeo")
    )
    _sync_snapshot(gateway.snapshot())


func _on_integration_notice(message: String) -> void:
    _notify(message, "info")
    _add_log("일반", message, "normal")


func _on_turn_requested(commands: Array) -> void:
    _add_log(
        "중요",
        "코어 턴 처리 요청 · %d개 명령" % commands.size(),
        "important"
    )


# Keyboard and controller input ---------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
    if not _accept_game_keyboard_event(event):
        return

    match event.keycode:
        KEY_ESCAPE:
            if pending_kind.is_empty():
                _show(ScreenState.START)
            else:
                _cancel_mode()
        KEY_SPACE:
            gateway.submit_turn()
        KEY_M:
            _prepare_move("move")
        KEY_A:
            _prepare_move("attack")
        KEY_R:
            _queue_recruit()
        KEY_F:
            if selected_province != -1:
                _game_map().focus_province(selected_province)
        KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
            var mode_index := int(event.keycode - KEY_1)
            if mode_index < MAP_MODES.size():
                _set_map_mode(String(MAP_MODES[mode_index][0]))


func _accept_game_keyboard_event(event: InputEvent) -> bool:
    if not event.pressed or event.echo:
        return false
    if state != ScreenState.GAME:
        return false

    var focused_control := get_viewport().gui_get_focus_owner()
    if focused_control is LineEdit or focused_control is SpinBox:
        return false
    return true


func _unhandled_input(event: InputEvent) -> void:
    if state != ScreenState.GAME:
        return

    if event is InputEventJoypadButton and event.pressed:
        _handle_joypad_button(event)
    elif (
        event is InputEventJoypadMotion
        and absf(event.axis_value) > 0.35
    ):
        _handle_joypad_motion(event)


func _handle_joypad_button(event: InputEventJoypadButton) -> void:
    match event.button_index:
        JOY_BUTTON_START:
            gateway.submit_turn()
        JOY_BUTTON_BACK:
            _open_ai_assistant()
        JOY_BUTTON_X:
            _queue_recruit()
        JOY_BUTTON_Y:
            _cycle_map_mode()
        JOY_BUTTON_B:
            _cancel_mode()
        JOY_BUTTON_LEFT_SHOULDER:
            _bottom_tab(ui.bottom_tabs.current_tab - 1)
        JOY_BUTTON_RIGHT_SHOULDER:
            _bottom_tab(ui.bottom_tabs.current_tab + 1)


func _handle_joypad_motion(event: InputEventJoypadMotion) -> void:
    if event.axis == JOY_AXIS_RIGHT_X:
        _game_map().nudge_camera(
            Vector2(-event.axis_value * 24.0, 0.0)
        )
    elif event.axis == JOY_AXIS_RIGHT_Y:
        _game_map().nudge_camera(
            Vector2(0.0, -event.axis_value * 24.0)
        )


func _cycle_map_mode() -> void:
    map_mode_index = (map_mode_index + 1) % MAP_MODES.size()
    _set_map_mode(String(MAP_MODES[map_mode_index][0]))


# Screen composition ---------------------------------------------------------

func _build_screens() -> void:
    var background := ColorRect.new()
    background.color = Color("#10161d")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)

    var screen_entries := [
        [ScreenState.START, _build_start()],
        [ScreenState.SCENARIO, _build_scenario()],
        [ScreenState.COUNTRY, _build_country()],
        [ScreenState.GAME, _build_game()]
    ]
    for entry in screen_entries:
        screens[entry[0]] = entry[1]
        add_child(entry[1])

    _build_dialogs()


func _build_start() -> Control:
    var root := _margin(48)
    var center := CenterContainer.new()
    root.add_child(center)

    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(520, 560)
    panel.add_theme_stylebox_override(
        "panel",
        _style("#17212a", "#8f7448", 2, 18)
    )
    center.add_child(panel)

    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 18)
    panel.add_child(box)

    box.add_child(
        _label(
            "◆  PROJECT EPOCH  ◆",
            34,
            Color("#d7bb79"),
            HORIZONTAL_ALIGNMENT_CENTER
        )
    )
    box.add_child(
        _label(
            "역사의 주도권은 지도 위에서 시작됩니다",
            16,
            Color("#aeb9bd"),
            HORIZONTAL_ALIGNMENT_CENTER
        )
    )
    box.add_child(HSeparator.new())
    box.add_child(
        _button(
            "새 게임",
            func(): _show(ScreenState.SCENARIO),
            "primary",
            58
        )
    )
    box.add_child(_button("불러오기", _load_game))
    box.add_child(_button("설정", _settings))
    box.add_child(_button("종료", func(): get_tree().quit()))
    box.add_child(
        _label(
            "Province 중심 대전략 · 데스크톱 고밀도 인터페이스",
            12,
            Color("#74828a"),
            HORIZONTAL_ALIGNMENT_CENTER
        )
    )
    return root


func _build_scenario() -> Control:
    var root := _margin(18)
    var outer := VBoxContainer.new()
    outer.add_theme_constant_override("separation", 12)
    root.add_child(outer)

    outer.add_child(
        _header(
            "시나리오 선택",
            "시대와 지역을 고른 뒤 지도를 확인하세요",
            func(): _show(ScreenState.START)
        )
    )

    var split := HSplitContainer.new()
    split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    split.split_offset = 270
    outer.add_child(split)

    var left := _section("시대 · 지역 · 시나리오", 250)
    split.add_child(left)

    var era := OptionButton.new()
    era.add_item("고대 동아시아 · 프로토타입")
    era.add_item("시대 확정 후 추가")
    left.add_child(era)

    var region := OptionButton.new()
    region.add_item("한반도 · 요동 · 중국 동부 · 일본")
    left.add_child(region)
    left.add_child(
        _button(
            "고대 동아시아 기반\n프로토타입 시작",
            _refresh_scenario,
            "list",
            72
        )
    )

    var middle := _section("지도 미리보기")
    middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.add_child(middle)

    var scenario_map := StrategicMap.new()
    scenario_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
    maps[ScreenState.SCENARIO] = scenario_map
    middle.add_child(scenario_map)

    var right := _section("시나리오 정보", 310)
    split.add_child(right)

    var detail := RichTextLabel.new()
    detail.bbcode_enabled = true
    detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
    ui.scenario_detail = detail
    right.add_child(detail)

    var footer := HBoxContainer.new()
    footer.add_spacer(true)
    footer.add_child(
        _button("이전", func(): _show(ScreenState.START))
    )
    footer.add_child(
        _button(
            "국가 선택",
            func(): _show(ScreenState.COUNTRY),
            "primary"
        )
    )
    outer.add_child(footer)
    return root


func _build_country() -> Control:
    var root := _margin(18)
    var outer := VBoxContainer.new()
    outer.add_theme_constant_override("separation", 12)
    root.add_child(outer)

    outer.add_child(
        _header(
            "국가 선택",
            "지도 또는 검색 결과에서 국가를 선택하세요",
            func(): _show(ScreenState.SCENARIO)
        )
    )

    var split := HSplitContainer.new()
    split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    split.split_offset = 300
    outer.add_child(split)

    var left := _section("국가 검색", 285)
    split.add_child(left)

    var search := LineEdit.new()
    search.placeholder_text = "국가명 · 정부 형태 검색"
    search.text_changed.connect(_rebuild_countries)
    left.add_child(search)

    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left.add_child(scroll)

    var country_list := VBoxContainer.new()
    country_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    ui.country_list = country_list
    scroll.add_child(country_list)

    var middle := _section("지도에서 국가 선택")
    middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.add_child(middle)

    var country_map := StrategicMap.new()
    country_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
    country_map.province_selected.connect(_country_map_pick)
    maps[ScreenState.COUNTRY] = country_map
    middle.add_child(country_map)

    var right := _section("국가 개요", 330)
    split.add_child(right)

    var detail := RichTextLabel.new()
    detail.bbcode_enabled = true
    detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
    ui.country_detail = detail
    right.add_child(detail)

    var spectate := CheckBox.new()
    spectate.text = "관전 모드"
    right.add_child(spectate)
    right.add_child(_button("플레이 시작", _start_game, "primary"))
    return root


func _build_game() -> Control:
    var root := _margin(8)
    var outer := VBoxContainer.new()
    outer.add_theme_constant_override("separation", 6)
    root.add_child(outer)

    outer.add_child(_top_bar())

    var split := HSplitContainer.new()
    split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    split.split_offset = 244
    outer.add_child(split)
    split.add_child(_left_panel())

    var center_right := HSplitContainer.new()
    center_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    center_right.split_offset = 760
    split.add_child(center_right)

    var center := VBoxContainer.new()
    center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    center.add_theme_constant_override("separation", 6)
    center_right.add_child(center)
    center.add_child(_macro_toolbar())

    var map_panel := PanelContainer.new()
    map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    map_panel.add_theme_stylebox_override(
        "panel",
        _style("#0d151c", "#46535a", 1, 8)
    )
    center.add_child(map_panel)

    var game_map := StrategicMap.new()
    maps[ScreenState.GAME] = game_map
    _connect_game_map_signals(game_map)
    map_panel.add_child(game_map)

    center.add_child(_bottom_panel())
    center_right.add_child(_right_panel())
    return root


func _macro_toolbar() -> Control:
    var toolbar := HBoxContainer.new()
    toolbar.add_theme_constant_override("separation", 6)
    toolbar.add_child(_label("MACRO", 12, Color("#d8bd7a")))
    toolbar.add_child(
        _button(
            "경제 취약지",
            _smart_recommend.bind("economy"),
            "small"
        )
    )
    toolbar.add_child(
        _button(
            "보급 위험",
            _smart_recommend.bind("supply"),
            "small"
        )
    )
    toolbar.add_child(
        _button(
            "선택지 일괄 개발",
            _simple_command.bind("develop"),
            "small"
        )
    )
    toolbar.add_child(
        _button("Governor", _toggle_governor, "small")
    )
    toolbar.add_child(
        _button("AI 제안", _open_ai_assistant, "small")
    )
    return toolbar


func _connect_game_map_signals(game_map: StrategicMap) -> void:
    game_map.province_selected.connect(_province_pick)
    game_map.selection_changed.connect(_selection_changed)
    game_map.province_dropped.connect(_quick_drag_move)
    game_map.command_target_selected.connect(_map_target)
    game_map.tooltip_changed.connect(_map_tooltip)


func _top_bar() -> Control:
    var panel := PanelContainer.new()
    panel.custom_minimum_size.y = 62
    panel.add_theme_stylebox_override(
        "panel",
        _style("#18232c", "#8d764b", 1, 8)
    )

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    panel.add_child(row)

    row.add_child(
        _button("☰", func(): _show(ScreenState.START))
    )

    var title := _label("PROJECT EPOCH", 18, Color("#d8bd7a"))
    title.custom_minimum_size.x = 160
    row.add_child(title)

    var statistics := [
        ["날짜", "date", "1000. 1. 1"],
        ["국고", "treasury", "0"],
        ["수입", "income", "+0"],
        ["인력", "manpower", "0"],
        ["안정도", "stability", "0"],
        ["전쟁 피로", "exhaustion", "0%"]
    ]
    for statistic in statistics:
        var value := _stat(String(statistic[0]), String(statistic[2]))
        ui[statistic[1]] = value
        row.add_child(value.get_parent())

    row.add_spacer(true)

    var alerts_button := _button(
        "알림 0",
        func(): _bottom_tab(1)
    )
    ui.alert_button = alerts_button
    row.add_child(alerts_button)
    row.add_child(
        _button(
            "턴 실행  Space",
            gateway.submit_turn,
            "primary"
        )
    )
    return panel


func _left_panel() -> Control:
    var tabs := TabContainer.new()
    tabs.custom_minimum_size.x = 230
    tabs.mouse_filter = Control.MOUSE_FILTER_STOP

    var map_box := _section("지도 모드")
    map_box.name = "지도"

    var search := LineEdit.new()
    search.placeholder_text = "Province 검색"
    search.text_submitted.connect(_search_province)
    map_box.add_child(search)

    var grid := GridContainer.new()
    grid.columns = 2
    map_box.add_child(grid)
    for mode in MAP_MODES:
        grid.add_child(
            _button(
                String(mode[1]),
                _set_map_mode.bind(String(mode[0])),
                "small"
            )
        )

    ui.mode_title = _label("정치 지도", 15, Color("#d7ba76"))
    map_box.add_child(ui.mode_title)

    var legend := RichTextLabel.new()
    legend.bbcode_enabled = true
    legend.fit_content = true
    ui.legend = legend
    map_box.add_child(legend)
    tabs.add_child(map_box)

    var nation := _section("국가 개요")
    nation.name = "국가"
    nation.add_child(
        _label(
            "국가 자원과 외교 상태를 빠르게 확인합니다.",
            13,
            Color("#aab5b9")
        )
    )
    nation.add_child(_button("외교 화면", _open_diplomacy))
    nation.add_child(_button("전쟁 · 평화", _open_peace))
    tabs.add_child(nation)

    var alerts := _section("중요 알림")
    alerts.name = "알림"
    alerts.add_child(
        _label(
            "전쟁, 반란, 외교 제안을 중요도 순으로 표시합니다.",
            13,
            Color("#aab5b9")
        )
    )
    tabs.add_child(alerts)

    var management := _section("자동 관리")
    management.name = "관리"
    management.add_child(
        _label(
            "Governor가 선택 기준에 따라 반복 투자를 Task Queue에 넣습니다.",
            12,
            Color("#aab5b9")
        )
    )
    management.add_child(
        _button(
            "Governor 켜기/끄기",
            _toggle_governor,
            "primary"
        )
    )
    management.add_child(
        _button("AI Assistant 추천", _open_ai_assistant)
    )
    management.add_child(
        _button(
            "전 영토 중 취약지 선택",
            _smart_recommend.bind("economy")
        )
    )
    tabs.add_child(management)
    return tabs


func _right_panel() -> Control:
    var tabs := TabContainer.new()
    tabs.custom_minimum_size.x = 330
    tabs.mouse_filter = Control.MOUSE_FILTER_STOP

    var province := _section("Province 정보")
    province.name = "Province"
    ui.province_title = _label(
        "Province를 선택하세요",
        21,
        Color("#e4cf97")
    )
    province.add_child(ui.province_title)

    var detail := RichTextLabel.new()
    detail.bbcode_enabled = true
    detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
    ui.province_detail = detail
    province.add_child(detail)

    ui.action_status = _label(
        "지도에서 Province를 선택하세요.",
        12,
        Color("#91a0a6")
    )
    ui.action_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    province.add_child(ui.action_status)

    var actions := GridContainer.new()
    actions.columns = 2
    province.add_child(actions)

    var province_actions := [
        ["병력 모집  R", _queue_recruit, "primary"],
        ["군대 이동  M", _prepare_move.bind("move"), "default"],
        ["공격  A", _prepare_move.bind("attack"), "danger"],
        ["개발 투자", _simple_command.bind("develop"), "default"],
        ["요새 건설", _simple_command.bind("fortify"), "default"],
        ["수도 이전", _simple_command.bind("move_capital"), "default"],
        ["점령지 관리", _simple_command.bind("occupation"), "default"],
        ["외교", _open_diplomacy, "default"]
    ]
    for action in province_actions:
        actions.add_child(
            _button(
                String(action[0]),
                action[1],
                String(action[2])
            )
        )
    tabs.add_child(province)

    var army := _section("군대")
    army.name = "군대"
    army.add_child(
        _label(
            "출발지 → 병력 수 → 목적지\n명령은 턴 실행 전까지 취소할 수 있습니다.",
            13,
            Color("#aab5b9")
        )
    )
    tabs.add_child(army)

    var diplomacy := _section("외교")
    diplomacy.name = "외교"
    diplomacy.add_child(
        _button("선택 국가 외교", _open_diplomacy, "primary")
    )
    diplomacy.add_child(_button("평화 협상", _open_peace))
    tabs.add_child(diplomacy)
    return tabs


func _bottom_panel() -> Control:
    var tabs := TabContainer.new()
    tabs.name = "BottomTabs"
    tabs.custom_minimum_size.y = 188
    tabs.mouse_filter = Control.MOUSE_FILTER_STOP
    ui.bottom_tabs = tabs

    var queue_scroll := ScrollContainer.new()
    queue_scroll.name = "Task Queue"
    queue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

    var queue := VBoxContainer.new()
    queue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    ui.queue = queue
    queue_scroll.add_child(queue)
    tabs.add_child(queue_scroll)

    var log_box := VBoxContainer.new()
    log_box.name = "이벤트 로그"
    var filters := HBoxContainer.new()
    log_box.add_child(filters)
    for category in ["전체", "전쟁", "외교", "경제", "반란", "중요"]:
        filters.add_child(
            _button(
                category,
                _filter_logs.bind(category),
                "small"
            )
        )

    var log := RichTextLabel.new()
    log.bbcode_enabled = true
    log.size_flags_vertical = Control.SIZE_EXPAND_FILL
    ui.log = log
    log_box.add_child(log)
    tabs.add_child(log_box)

    var wars := RichTextLabel.new()
    wars.name = "전쟁 현황"
    wars.bbcode_enabled = true
    ui.wars = wars
    tabs.add_child(wars)
    return tabs


func _build_dialogs() -> void:
    _build_tooltip()
    _build_toast()
    _build_move_dialog()
    _build_diplomacy_dialog()
    _build_peace_dialog()


func _build_tooltip() -> void:
    var tooltip := PanelContainer.new()
    tooltip.visible = false
    tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
    tooltip.z_index = 90
    tooltip.add_theme_stylebox_override(
        "panel",
        _style("#101820", "#b59b63", 1, 7)
    )
    ui.tooltip = tooltip
    add_child(tooltip)

    var tooltip_label := Label.new()
    tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    tooltip_label.custom_minimum_size = Vector2(210, 0)
    ui.tooltip_label = tooltip_label
    tooltip.add_child(tooltip_label)


func _build_toast() -> void:
    toast = PanelContainer.new()
    toast.visible = false
    toast.z_index = 100
    toast.custom_minimum_size = Vector2(440, 52)
    add_child(toast)

    var toast_label := Label.new()
    toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    ui.toast_label = toast_label
    toast.add_child(toast_label)

    toast_timer = Timer.new()
    toast_timer.one_shot = true
    toast_timer.timeout.connect(func(): toast.hide())
    add_child(toast_timer)


func _build_move_dialog() -> void:
    move_dialog = Window.new()
    move_dialog.visible = false
    move_dialog.exclusive = true
    move_dialog.title = "군대 명령"
    move_dialog.size = Vector2i(440, 300)
    move_dialog.close_requested.connect(_cancel_mode)
    add_child(move_dialog)

    var move_box := _window_box(move_dialog)
    ui.move_summary = _label(
        "출발 Province",
        16,
        Color("#dfc889")
    )
    move_box.add_child(ui.move_summary)

    var amount := SpinBox.new()
    amount.min_value = 1
    amount.max_value = 999999
    amount.value_changed.connect(_on_move_amount_changed)
    ui.move_amount = amount
    move_box.add_child(amount)

    var presets := HBoxContainer.new()
    move_box.add_child(presets)
    presets.add_child(
        _button("전 병력", _move_fraction.bind(1.0), "small")
    )
    presets.add_child(
        _button("절반", _move_fraction.bind(0.5), "small")
    )
    presets.add_child(
        _button(
            "주둔군 1 남기기",
            _move_fraction.bind(0.0),
            "small"
        )
    )

    move_box.add_child(
        _label(
            "적국 목적지는 공격으로 표시됩니다. 전쟁 상태를 먼저 확인합니다.",
            12,
            Color("#c99572")
        )
    )

    var buttons := HBoxContainer.new()
    buttons.add_spacer(true)
    buttons.add_child(_button("취소", _cancel_mode))
    buttons.add_child(
        _button("목적지 선택", _begin_target, "primary")
    )
    move_box.add_child(buttons)


func _on_move_amount_changed(value: float) -> void:
    pending_amount = int(value)


func _build_diplomacy_dialog() -> void:
    diplomacy_dialog = Window.new()
    diplomacy_dialog.visible = false
    diplomacy_dialog.exclusive = true
    diplomacy_dialog.title = "외교"
    diplomacy_dialog.size = Vector2i(720, 620)
    diplomacy_dialog.close_requested.connect(
        func(): diplomacy_dialog.hide()
    )
    add_child(diplomacy_dialog)

    var scroll := ScrollContainer.new()
    scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    diplomacy_dialog.add_child(scroll)

    var box := VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 10)
    ui.diplomacy_box = box
    scroll.add_child(box)


func _build_peace_dialog() -> void:
    peace_dialog = Window.new()
    peace_dialog.visible = false
    peace_dialog.exclusive = true
    peace_dialog.title = "평화 협상"
    peace_dialog.size = Vector2i(760, 650)
    peace_dialog.close_requested.connect(_close_peace)
    add_child(peace_dialog)

    var scroll := ScrollContainer.new()
    scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    peace_dialog.add_child(scroll)

    var box := VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 10)
    ui.peace_box = box
    scroll.add_child(box)


# Screen navigation and snapshot presentation --------------------------------

func _show(next_state: ScreenState) -> void:
    state = next_state
    for screen_state in screens:
        screens[screen_state].visible = screen_state == next_state

    if ui.has("tooltip"):
        ui.tooltip.hide()

    match next_state:
        ScreenState.SCENARIO:
            _refresh_scenario()
            call_deferred("_frame_map", maps.get(next_state))
        ScreenState.COUNTRY:
            _rebuild_countries("")
            _refresh_country()
            call_deferred("_frame_map", maps.get(next_state))
        ScreenState.GAME:
            _sync_snapshot(gateway.snapshot())
            call_deferred("_frame_map", maps.get(next_state))


func _load_game() -> void:
    if not gateway.load_autosave():
        return

    selected_country = String(
        gateway.snapshot().get("player_country_id", "goguryeo")
    )
    selected_province = -1
    selected_provinces.clear()
    _sync_snapshot(gateway.snapshot())
    _show(ScreenState.GAME)
    _notify("자동 저장 게임을 불러왔습니다.", "success")


func _sync_snapshot(snapshot: Dictionary) -> void:
    for strategy_map in maps.values():
        strategy_map.set_snapshot(snapshot)

    selected_country = String(
        snapshot.get("player_country_id", selected_country)
    )
    var country := gateway.country(selected_country)
    var date: Dictionary = snapshot.get("date", {})

    if ui.has("date"):
        ui.date.text = "%d. %d. %d" % [
            int(date.get("year", 1000)),
            int(date.get("month", 1)),
            int(date.get("day", 1))
        ]
    if ui.has("treasury"):
        ui.treasury.text = _number(int(country.get("treasury", 0)))
    if ui.has("income"):
        ui.income.text = "+%s" % _number(_income(selected_country))
    if ui.has("manpower"):
        ui.manpower.text = _number(int(country.get("manpower", 0)))
    if ui.has("stability"):
        ui.stability.text = str(country.get("stability", 0))
    if ui.has("exhaustion"):
        ui.exhaustion.text = "%d%%" % int(
            country.get("war_exhaustion", 0)
        )

    _refresh_province()
    _refresh_wars()
    _legend()


# Scenario and country selection --------------------------------------------

func _refresh_scenario() -> void:
    if not ui.has("scenario_detail"):
        return

    var scenarios := gateway.scenarios()
    var scenario: Dictionary = {}
    if not scenarios.is_empty():
        scenario = scenarios[0]

    var recommendations := PackedStringArray()
    for country_value in gateway.countries().values():
        if recommendations.size() >= 5:
            break
        var country: Dictionary = country_value
        recommendations.append(
            "• %s" % String(country.get("name", country.get("id", "")))
        )

    ui.scenario_detail.text = (
        "[font_size=22][color=#ddc47e]%s[/color][/font_size]\n\n"
        + "시작 연도  [b]%s년(프로토타입)[/b]\n"
        + "국가 수  [b]%d[/b]\n"
        + "턴 방식  [b]동시 명령[/b]\n\n"
        + "%s\n\n"
        + "[color=#9fb0b5]플레이 가능 국가[/color]\n%s"
    ) % [
        String(scenario.get("name", "고대 동아시아 기반 시나리오")),
        str(scenario.get("start_date", {}).get("year", 300)),
        gateway.countries().size(),
        String(scenario.get("description", "")),
        "\n".join(recommendations)
    ]


func _rebuild_countries(filter_text: String) -> void:
    if not ui.has("country_list"):
        return

    for child in ui.country_list.get_children():
        child.queue_free()

    var needle := filter_text.strip_edges().to_lower()
    for country_id_value in gateway.countries().keys():
        var country_id := String(country_id_value)
        var country := gateway.country(country_id)
        var searchable_text := (
            String(country.get("name", ""))
            + " "
            + String(country.get("government", ""))
        ).to_lower()
        if not needle.is_empty() and needle not in searchable_text:
            continue

        ui.country_list.add_child(
            _button(
                "%s\n%s · 난이도 %s" % [
                    country.get("name", country_id),
                    country.get("government", "정부"),
                    _difficulty(country)
                ],
                _select_country.bind(country_id),
                "list",
                64
            )
        )


func _select_country(country_id: String) -> void:
    selected_country = country_id
    _refresh_country()

    var capital_province_id := int(
        gateway.country(country_id).get("capital_province", -1)
    )
    if capital_province_id == -1:
        return

    var country_map := maps[ScreenState.COUNTRY] as StrategicMap
    country_map.selected_province_id = capital_province_id
    country_map.focus_province(capital_province_id)


func _country_map_pick(province_id: int) -> void:
    var owner_id := String(gateway.province(province_id).get("owner", ""))
    if not owner_id.is_empty():
        _select_country(owner_id)


func _refresh_country() -> void:
    if not ui.has("country_detail"):
        return

    var country := gateway.country(selected_country)
    ui.country_detail.text = (
        "[font_size=24][color=#dec783]%s[/color][/font_size]\n"
        + "[color=%s]████[/color]  %s\n\n"
        + "정부  [b]%s[/b]\n"
        + "수도  [b]%s[/b]\n"
        + "국고  [b]%s[/b]\n"
        + "인구  [b]%s[/b]\n"
        + "경제  [b]%s[/b]\n"
        + "인력  [b]%s[/b]\n"
        + "안정도  [b]%s[/b]\n"
        + "난이도  [b]%s[/b]\n\n"
        + "Province %d · 육군 %s"
    ) % [
        country.get("name", selected_country),
        country.get("color", "#777777"),
        country.get("id", ""),
        country.get("government", "정부"),
        _province_name(int(country.get("capital_province", -1))),
        _number(int(country.get("treasury", 0))),
        _number(_country_total(selected_country, "population")),
        _number(_country_total(selected_country, "economy")),
        _number(int(country.get("manpower", 0))),
        str(country.get("stability", 0)),
        _difficulty(country),
        _owned(selected_country).size(),
        _number(_army_total(selected_country))
    ]


func _start_game() -> void:
    if selected_country.is_empty():
        _notify("플레이할 국가를 선택하세요.", "warning")
        return

    if not gateway.select_player_country(selected_country):
        _notify("선택한 국가로 게임을 시작하지 못했습니다.", "error")
        return

    _add_log(
        "중요",
        "%s로 플레이를 시작했습니다." % _country_name(selected_country),
        "important"
    )
    _show(ScreenState.GAME)


# Province selection and presentation ---------------------------------------

func _province_pick(province_id: int) -> void:
    selected_province = province_id
    if province_id not in selected_provinces:
        selected_provinces = [province_id]

    _game_map().selected_province_id = province_id
    _refresh_province()


func _selection_changed(province_ids: Array[int]) -> void:
    selected_provinces = province_ids.duplicate()
    if selected_provinces.is_empty():
        selected_province = -1
    else:
        selected_province = selected_provinces.back()
    _refresh_province()


func _active_selection() -> Array[int]:
    return read_model.active_selection(
        selected_provinces,
        selected_province
    )


func _owned_selection() -> Array[int]:
    return read_model.owned_selection(
        selected_provinces,
        selected_province,
        selected_country
    )


func _refresh_province() -> void:
    if not ui.has("province_detail"):
        return

    if selected_province == -1:
        _show_empty_province_selection()
        return

    if selected_provinces.size() > 1:
        _show_multiple_province_selection()
        return

    _show_single_province_selection()


func _show_empty_province_selection() -> void:
    ui.province_title.text = "Province를 선택하세요"
    ui.province_detail.text = (
        "[color=#96a5aa]클릭·Shift 클릭·드래그 박스로 "
        + "여러 Province를 선택하세요.[/color]"
    )


func _show_multiple_province_selection() -> void:
    var population := 0
    var economy := 0
    var manpower := 0
    var army_total := 0
    var armies: Dictionary = gateway.snapshot().get("armies", {})

    for province_id in selected_provinces:
        var province := gateway.province(province_id)
        population += int(province.get("population", 0))
        economy += int(province.get("economy", 0))
        manpower += int(province.get("manpower", 0))
        army_total += int(armies.get(province_id, 0))

    ui.province_title.text = "%d개 Province 선택" % selected_provinces.size()
    ui.province_detail.text = (
        "[b]일괄 관리 준비됨[/b]\n\n"
        + "총 인구  %s\n"
        + "총 경제  %s\n"
        + "총 인력  %s\n"
        + "총 주둔군  %s\n\n"
        + "개발·요새·모집은 선택한 자국 Province에 한 번에 예약됩니다."
    ) % [
        _number(population),
        _number(economy),
        _number(manpower),
        _number(army_total)
    ]
    ui.action_status.text = "다중 선택 · Shift로 추가/해제 · 빈 영역 드래그 선택"


func _show_single_province_selection() -> void:
    var province := gateway.province(selected_province)
    if province.is_empty():
        selected_province = -1
        _refresh_province()
        return

    var owner_id := String(province.get("owner", ""))
    var owner := gateway.country(owner_id)
    var armies: Dictionary = gateway.snapshot().get("armies", {})
    var capital_suffix := ""
    if int(owner.get("capital_province", -1)) == selected_province:
        capital_suffix = "  ★ 수도"

    ui.province_title.text = (
        String(province.get("name", "Province")) + capital_suffix
    )
    ui.province_detail.text = (
        "[color=#9eacb1]소유국[/color]  [b]%s[/b]\n"
        + "[color=#9eacb1]점령국[/color]  %s\n\n"
        + "인구  [b]%s[/b]     경제  [b]%s[/b]\n"
        + "개발도  [b]%s[/b]     인력  [b]%s[/b]\n"
        + "지형  [b]%s[/b]     요새  [b]%s[/b]\n"
        + "불안도  [b]%s%%[/b]     주둔군  [b]%s[/b]\n\n"
        + "예상 세입  [color=#7ec59f]+%s[/color]\n"
        + "인접 Province  %s"
    ) % [
        _country_name(owner_id),
        _country_name(String(province.get("controller", owner_id))),
        _number(int(province.get("population", 0))),
        _number(int(province.get("economy", 0))),
        str(province.get("development", 0)),
        _number(int(province.get("manpower", 0))),
        _terrain(String(province.get("terrain", "plains"))),
        str(province.get("fort", 0)),
        str(province.get("revolt_risk", 0)),
        _number(int(armies.get(selected_province, 0))),
        str(
            int(
                float(province.get("economy", 0))
                * float(owner.get("tax_rate", 0.2))
            )
        ),
        _neighbor_names(province.get("neighbors", []))
    ]
    ui.action_status.text = _province_action_status(owner_id)


func _province_action_status(owner_id: String) -> String:
    if owner_id == selected_country:
        return "자국 Province"
    if gateway.at_war(selected_country, owner_id):
        return "적국 · 전쟁 중"
    return "외국 · 공격 전 전쟁 선포 필요"


# Domestic and military commands --------------------------------------------

func _queue_recruit() -> void:
    var targets := _owned_selection()
    if targets.is_empty():
        _notify("모집할 자국 Province를 선택하세요.", "warning")
        return

    var queued_count := 0
    for province_id in targets:
        var command_id := gateway.queue_command(
            "recruit",
            {
                "province_id": province_id,
                "amount": 100
            },
            {
                "title": "일괄 병력 모집",
                "from": _province_name(province_id),
                "amount": 100,
                "cost": 2
            }
        )
        if command_id != -1:
            queued_count += 1

    _notify(
        "%d개 Province 모집 작업을 Task Queue에 추가했습니다."
        % queued_count,
        "success"
    )


func _simple_command(command_type: String) -> void:
    var targets := _owned_selection()
    if targets.is_empty():
        _notify("관리할 자국 Province를 선택하세요.", "warning")
        return

    var command_labels := {
        "develop": "개발 투자",
        "fortify": "요새 건설",
        "move_capital": "수도 이전",
        "occupation": "점령지 관리"
    }
    var queued_count := 0

    for province_id in targets:
        var command_id := gateway.queue_command(
            command_type,
            {"province_id": province_id},
            {
                "title": command_labels.get(command_type, command_type),
                "from": _province_name(province_id),
                "cost": 40
            }
        )
        if command_id != -1:
            queued_count += 1

    _notify(
        "%d개 작업을 Task Queue에 추가했습니다." % queued_count,
        "success" if queued_count > 0 else "warning"
    )


func _prepare_move(command_type: String = "move") -> void:
    pending_sources = _owned_selection()
    if pending_sources.is_empty():
        _notify("출발할 자국 Province를 선택하세요.", "warning")
        return

    var available := read_model.available_army(pending_sources)
    if available <= 0:
        _notify("이동 가능한 병력이 없습니다.", "warning")
        _cancel_mode()
        return

    pending_source = pending_sources[0]
    pending_kind = command_type
    pending_amount = available

    ui.move_amount.max_value = available
    ui.move_amount.value = available
    ui.move_summary.text = "%d개 출발지 · 총 가용 병력 %d" % [
        pending_sources.size(),
        available
    ]

    _game_map().set_interaction_state(
        StrategicMap.InputState.MODAL_OPEN,
        pending_source
    )
    move_dialog.popup_centered()


func _move_fraction(fraction: float) -> void:
    var available := int(ui.move_amount.max_value)
    if fraction <= 0.0 or fraction >= 1.0:
        ui.move_amount.value = available
    else:
        ui.move_amount.value = maxi(
            1,
            int(float(available) * fraction)
        )


func _begin_target() -> void:
    pending_amount = int(ui.move_amount.value)
    move_dialog.hide()

    var target_state := StrategicMap.InputState.CHOOSING_MOVE_TARGET
    if pending_kind == "attack":
        target_state = StrategicMap.InputState.CHOOSING_ATTACK_TARGET

    _game_map().set_interaction_state(target_state, pending_source)
    ui.action_status.text = (
        "목적지 선택 중 · 우클릭 드래그 패닝 · Esc 취소"
    )
    _notify("지도에서 목적지를 선택하세요.", "info")


func _map_target(province_id: int) -> void:
    if pending_kind == "peace":
        _toggle_peace_demand(province_id)
        return
    if pending_kind.is_empty():
        return

    var sources := pending_sources.duplicate()
    if sources.is_empty():
        sources = [pending_source]

    var target := gateway.province(province_id)
    var target_owner := String(target.get("owner", ""))
    var queued_count := 0

    for source_id_value in sources:
        var source_id := int(source_id_value)
        var source := gateway.province(source_id)
        if not _has_neighbor(source, province_id):
            continue

        var command_type := pending_kind
        if target_owner != selected_country:
            command_type = "attack"
        if (
            command_type == "attack"
            and not gateway.at_war(selected_country, target_owner)
        ):
            continue

        var amount := _distributed_move_amount(
            source_id,
            sources.size()
        )
        var command_id := gateway.queue_command(
            command_type,
            {
                "from_id": source_id,
                "to_id": province_id,
                "amount": amount,
                "leave_garrison": 1
            },
            {
                "title": (
                    "일괄 공격"
                    if command_type == "attack"
                    else "일괄 이동"
                ),
                "from": _province_name(source_id),
                "to": _province_name(province_id),
                "amount": amount,
                "warning": (
                    "전투 발생 가능"
                    if command_type == "attack"
                    else ""
                )
            }
        )
        if command_id != -1:
            queued_count += 1

    _cancel_mode()
    _notify(
        "%d개 이동 작업을 Task Queue에 추가했습니다." % queued_count,
        "success" if queued_count > 0 else "warning"
    )


func _distributed_move_amount(source_id: int, source_count: int) -> int:
    var armies: Dictionary = gateway.snapshot().get("armies", {})
    var available := maxi(1, int(armies.get(source_id, 0)) - 1)
    var requested_share := maxi(
        1,
        int(float(pending_amount) / float(source_count))
    )
    return mini(available, requested_share)


func _quick_drag_move(from_id: int, to_id: int) -> void:
    var source := gateway.province(from_id)
    if String(source.get("owner", "")) != selected_country:
        _notify("자국 군대만 드래그할 수 있습니다.", "warning")
        return
    if not _has_neighbor(source, to_id):
        _notify("인접 Province로만 이동할 수 있습니다.", "warning")
        return

    var target_owner := String(gateway.province(to_id).get("owner", ""))
    var command_type := "move"
    if target_owner != selected_country:
        command_type = "attack"

    if (
        command_type == "attack"
        and not gateway.at_war(selected_country, target_owner)
    ):
        _notify("공격 전 전쟁 상태가 필요합니다.", "warning")
        return

    var armies: Dictionary = gateway.snapshot().get("armies", {})
    var amount := maxi(1, int(armies.get(from_id, 0)) - 1)
    var command_id := gateway.queue_command(
        command_type,
        {
            "from_id": from_id,
            "to_id": to_id,
            "amount": amount,
            "leave_garrison": 1
        },
        {
            "title": "Drag & Drop 이동",
            "from": _province_name(from_id),
            "to": _province_name(to_id),
            "amount": amount
        }
    )

    if command_id != -1:
        _notify(
            "Drag & Drop 명령을 Task Queue에 추가했습니다.",
            "success"
        )


func _cancel_mode() -> void:
    move_dialog.hide()
    pending_source = -1
    pending_sources.clear()
    pending_kind = ""
    pending_amount = 0
    _game_map().clear_interaction()

    if ui.has("action_status"):
        ui.action_status.text = "명령 준비 상태가 해제되었습니다."


# Automated recommendations --------------------------------------------------

func _smart_recommend(recommendation_type: String = "economy") -> void:
    var owned_provinces := _owned(selected_country)
    if owned_provinces.is_empty():
        return

    owned_provinces.sort_custom(
        func(first_id: int, second_id: int) -> bool:
            return (
                _recommendation_score(first_id, recommendation_type)
                < _recommendation_score(second_id, recommendation_type)
            )
    )

    selected_provinces.clear()
    for province_index in range(mini(3, owned_provinces.size())):
        selected_provinces.append(owned_provinces[province_index])

    selected_province = selected_provinces.back()
    _game_map().set_selected_provinces(selected_provinces)
    _set_map_mode(recommendation_type)
    _game_map().focus_province(selected_province)
    _notify(
        "AI Assistant가 우선 관리할 %d개 Province를 선택했습니다."
        % selected_provinces.size(),
        "info"
    )


func _recommendation_score(
    province_id: int,
    recommendation_type: String
) -> float:
    if recommendation_type == "economy":
        return float(gateway.province(province_id).get("economy", 0))
    return read_model.supply_score(province_id)


func _toggle_governor() -> void:
    governor_enabled = not governor_enabled
    _notify(
        "Governor 자동 관리 %s"
        % ("활성" if governor_enabled else "비활성"),
        "success" if governor_enabled else "info"
    )


func _before_turn(_commands: Array) -> void:
    if governor_enabled:
        _governor_plan()


func _governor_plan() -> void:
    var owned_provinces := _owned(selected_country)
    owned_provinces.sort_custom(
        func(first_id: int, second_id: int) -> bool:
            return (
                float(gateway.province(first_id).get("economy", 0))
                < float(gateway.province(second_id).get("economy", 0))
            )
    )
    if owned_provinces.is_empty():
        return

    var target_id := int(owned_provinces[0])
    gateway.queue_command(
        "develop",
        {"province_id": target_id},
        {
            "title": "Governor 자동 투자",
            "from": _province_name(target_id),
            "cost": 40,
            "warning": "AI 추천"
        }
    )


func _open_ai_assistant() -> void:
    var owned_provinces := _owned(selected_country)
    if owned_provinces.is_empty():
        return

    var weakest_id := int(owned_provinces[0])
    for province_id in owned_provinces:
        if (
            float(gateway.province(province_id).get("economy", 0))
            < float(gateway.province(weakest_id).get("economy", 0))
        ):
            weakest_id = province_id

    var dialog := ConfirmationDialog.new()
    dialog.title = "AI Assistant · 전략 브리핑"
    dialog.dialog_text = (
        "추천 1순위: %s 개발 투자\n"
        + "이유: 자국 내 경제 수치가 가장 낮습니다.\n\n"
        + "[추천 적용]을 누르면 선택하고 Task Queue에 개발을 예약합니다."
    ) % _province_name(weakest_id)
    dialog.ok_button_text = "추천 적용"
    dialog.confirmed.connect(
        _apply_ai_development_recommendation.bind(weakest_id, dialog)
    )
    dialog.canceled.connect(dialog.queue_free)
    add_child(dialog)
    dialog.popup_centered(Vector2i(560, 300))


func _apply_ai_development_recommendation(
    province_id: int,
    dialog: ConfirmationDialog
) -> void:
    selected_provinces = [province_id]
    selected_province = province_id
    _game_map().set_selected_provinces(selected_provinces)
    _simple_command("develop")
    dialog.queue_free()


# Command queue --------------------------------------------------------------

func _rebuild_queue(commands: Array) -> void:
    if not ui.has("queue"):
        return

    for child in ui.queue.get_children():
        child.queue_free()

    var command_paths: Array = []
    if commands.is_empty():
        ui.queue.add_child(
            _label(
                "예약된 명령이 없습니다.",
                13,
                Color("#829098")
            )
        )

    for command_value in commands:
        if command_value is not Dictionary:
            continue
        var command: Dictionary = command_value
        ui.queue.add_child(_build_queue_row(command))

        var payload: Dictionary = command.get("payload", {})
        if payload.has("from_id") and payload.has("to_id"):
            command_paths.append({
                "from_id": payload.get("from_id", -1),
                "to_id": payload.get("to_id", -1),
                "type": command.get("type", "move")
            })

    _game_map().set_command_paths(command_paths)


func _build_queue_row(command: Dictionary) -> Control:
    var row := HBoxContainer.new()
    var presentation: Dictionary = command.get("presentation", {})
    var text := "#%d  %s  %s" % [
        int(command.get("id", 0)),
        _command_icon(String(command.get("type", ""))),
        String(
            presentation.get(
                "title",
                command.get("type", "명령")
            )
        )
    ]

    if not String(presentation.get("from", "")).is_empty():
        text += " · " + String(presentation.get("from", ""))
    if not String(presentation.get("to", "")).is_empty():
        text += " → " + String(presentation.get("to", ""))
    if presentation.has("amount"):
        text += " · 병력 %s" % str(presentation.get("amount", 0))

    var label := _label(text, 13, Color("#d9d4c5"))
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(label)

    var warning := String(presentation.get("warning", ""))
    if not warning.is_empty():
        row.add_child(
            _label("⚠ " + warning, 11, Color("#d9986f"))
        )

    row.add_child(
        _button(
            "수정",
            func(): _notify(
                "수정 API 준비됨 · 취소 후 다시 입력하세요.",
                "info"
            ),
            "small"
        )
    )
    row.add_child(
        _button(
            "취소",
            _cancel_queued.bind(int(command.get("id", 0))),
            "small"
        )
    )
    return row


func _cancel_queued(command_id: int) -> void:
    if gateway.cancel_command(command_id):
        _notify("명령 #%d을 취소했습니다." % command_id, "success")


# Diplomacy ------------------------------------------------------------------

func _open_diplomacy() -> void:
    var target_country_id := _foreign_country()
    if target_country_id.is_empty():
        target_country_id = _first_foreign_country()
    if target_country_id.is_empty():
        return

    for child in ui.diplomacy_box.get_children():
        child.queue_free()

    var relation_value := gateway.relation(
        selected_country,
        target_country_id
    )
    var at_war := gateway.at_war(selected_country, target_country_id)

    ui.diplomacy_box.add_child(
        _label(
            "%s ↔ %s" % [
                _country_name(selected_country),
                _country_name(target_country_id)
            ],
            25,
            Color("#dec77f")
        )
    )
    ui.diplomacy_box.add_child(
        _label(
            _diplomacy_summary(
                target_country_id,
                relation_value,
                at_war
            ),
            14,
            Color("#b9c2c2")
        )
    )

    var grid := GridContainer.new()
    grid.columns = 2
    ui.diplomacy_box.add_child(grid)
    _add_diplomacy_actions(
        grid,
        target_country_id,
        relation_value
    )
    diplomacy_dialog.popup_centered()


func _first_foreign_country() -> String:
    for country_id_value in gateway.countries().keys():
        var country_id := String(country_id_value)
        if country_id != selected_country:
            return country_id
    return ""


func _diplomacy_summary(
    target_country_id: String,
    relation_value: int,
    at_war: bool
) -> String:
    var relation_name := "중립"
    if at_war:
        relation_name = "전쟁"
    elif relation_value >= 20:
        relation_name = "우호"
    elif relation_value <= -20:
        relation_name = "긴장"

    return (
        "관계도 %d · %s\n"
        + "현재 전쟁 %s · 동맹 없음 · 불가침 없음 · 휴전 없음\n"
        + "국력 비교  아군 %s : 상대 %s\n"
        + "국경 Province  %s"
    ) % [
        relation_value,
        relation_name,
        "진행 중" if at_war else "없음",
        _number(_army_total(selected_country)),
        _number(_army_total(target_country_id)),
        _border_names(selected_country, target_country_id)
    ]


func _add_diplomacy_actions(
    grid: GridContainer,
    target_country_id: String,
    relation_value: int
) -> void:
    var actions := [
        ["관계 개선", "improve_relations", 25],
        ["모욕", "insult", 0],
        ["전쟁 선포", "declare_war", 50],
        ["평화 제안", "offer_peace", 20],
        ["동맹 제안", "offer_alliance", 35],
        ["불가침 제안", "offer_non_aggression", 20],
        ["군사 통행 요청", "request_access", 15],
        ["속국화 요구", "demand_vassalization", 80],
        ["독립 요구", "demand_independence", 60]
    ]

    for action in actions:
        var action_name := String(action[0])
        var command_type := String(action[1])
        var cost := int(action[2])
        var acceptance := clampi(
            50 + relation_value - cost / 2,
            0,
            100
        )
        grid.add_child(
            _button(
                "%s\n비용 %d · 수락 예상 %d%%" % [
                    action_name,
                    cost,
                    acceptance
                ],
                _queue_diplomacy.bind(
                    command_type,
                    target_country_id,
                    cost,
                    acceptance
                ),
                "danger" if command_type == "declare_war" else "list",
                58
            )
        )


func _queue_diplomacy(
    command_type: String,
    target_country_id: String,
    cost: int,
    acceptance: int
) -> void:
    if command_type == "offer_peace":
        diplomacy_dialog.hide()
        _open_peace()
        return

    var command_id := gateway.queue_command(
        command_type,
        {"target_country_id": target_country_id},
        {
            "title": _diplomacy_name(command_type),
            "to": _country_name(target_country_id),
            "cost": cost,
            "warning": "수락 예상 %d%%" % acceptance
        }
    )
    if command_id == -1:
        return

    diplomacy_dialog.hide()
    _add_log(
        "외교",
        "명령 #%d · %s → %s" % [
            command_id,
            _diplomacy_name(command_type),
            _country_name(target_country_id)
        ],
        "important"
    )
    _notify("외교 명령을 예약했습니다.", "success")


# Peace negotiation ----------------------------------------------------------

func _open_peace() -> void:
    var target_country_id := _foreign_country()
    if target_country_id.is_empty():
        _notify("협상 상대 Province를 먼저 선택하세요.", "warning")
        return

    for child in ui.peace_box.get_children():
        child.queue_free()

    ui.peace_box.add_child(
        _label(
            "%s 평화 협상" % _country_name(target_country_id),
            24,
            Color("#dec77f")
        )
    )
    ui.peace_box.add_child(
        _label(
            "전쟁 점수 0 · 점령 Province 0\n"
            + "지도에서 요구할 Province를 직접 선택할 수 있습니다.",
            14,
            Color("#b9c2c2")
        )
    )

    var reparations := SpinBox.new()
    reparations.name = "Reparations"
    reparations.min_value = 0
    reparations.max_value = 1000
    reparations.step = 25
    reparations.suffix = " 배상금"
    ui.peace_box.add_child(reparations)

    var vassalize := CheckBox.new()
    vassalize.name = "Vassalize"
    vassalize.text = "속국화 요구"
    ui.peace_box.add_child(vassalize)

    var independence := CheckBox.new()
    independence.name = "Independence"
    independence.text = "독립 승인"
    ui.peace_box.add_child(independence)

    ui.peace_box.add_child(
        _label(
            "제안 전송 시 코어가 전쟁 점수와 협상 비용을 검증합니다.",
            12,
            Color("#d09b70")
        )
    )

    var row := HBoxContainer.new()
    row.add_child(_button("제안 초기화", _reset_peace))
    row.add_child(_button("지도에서 Province 요구", _begin_peace))
    row.add_child(
        _button(
            "제안 전송",
            _submit_peace.bind(target_country_id),
            "primary"
        )
    )
    ui.peace_box.add_child(row)
    peace_dialog.popup_centered()


func _begin_peace() -> void:
    peace_dialog.hide()
    pending_kind = "peace"
    _game_map().set_interaction_state(
        StrategicMap.InputState.SELECTING_PEACE_TERMS
    )
    _notify(
        "지도에서 요구할 Province를 선택한 뒤 평화 창을 다시 여세요.",
        "info"
    )


func _toggle_peace_demand(province_id: int) -> void:
    if province_id in peace_demands:
        peace_demands.erase(province_id)
    else:
        peace_demands.append(province_id)
    _game_map().set_peace_demands(peace_demands)


func _reset_peace() -> void:
    peace_demands.clear()
    _game_map().set_peace_demands(peace_demands)
    _notify("평화 제안을 초기화했습니다.", "info")


func _submit_peace(target_country_id: String) -> void:
    var reparations := (
        ui.peace_box.get_node_or_null("Reparations") as SpinBox
    )
    var vassalize := (
        ui.peace_box.get_node_or_null("Vassalize") as CheckBox
    )
    var independence := (
        ui.peace_box.get_node_or_null("Independence") as CheckBox
    )

    var payload := {
        "target_country_id": target_country_id,
        "province_demands": peace_demands.duplicate(),
        "reparations": int(reparations.value if reparations else 0),
        "vassalize": vassalize.button_pressed if vassalize else false,
        "recognize_independence": (
            independence.button_pressed if independence else false
        )
    }
    var command_id := gateway.queue_command(
        "peace_offer",
        payload,
        {
            "title": "평화 제안",
            "to": _country_name(target_country_id),
            "cost": (
                peace_demands.size() * 20
                + int(payload.get("reparations", 0)) / 25
            ),
            "warning": "코어 검증 완료"
        }
    )
    if command_id == -1:
        return

    _close_peace()
    _notify("평화 제안을 명령 큐에 추가했습니다.", "success")


func _close_peace() -> void:
    peace_dialog.hide()
    if pending_kind == "peace":
        pending_kind = ""
    _game_map().clear_interaction()


# Map mode, search, and tooltip ----------------------------------------------

func _set_map_mode(mode: String) -> void:
    _game_map().set_mode(mode)
    map_mode_index = _map_mode_index(mode)
    ui.mode_title.text = "%s 지도" % _game_map().mode_label()
    _legend()
    _notify("%s 지도 모드" % _game_map().mode_label(), "info")


func _map_mode_index(mode: String) -> int:
    for index in range(MAP_MODES.size()):
        if String(MAP_MODES[index][0]) == mode:
            return index
    return map_mode_index


func _legend() -> void:
    if not ui.has("legend") or not maps.has(ScreenState.GAME):
        return

    var mode := _game_map().map_mode
    if mode == "political":
        ui.legend.text = (
            "[color=#d2b16c]범례[/color]\n"
            + "■ 국가색  ▣ 선택\n"
            + "청록 국경: 자국\n"
            + "적색 국경: 적국"
        )
    elif mode in ["relations", "war"]:
        ui.legend.text = (
            "[color=#d2b16c]범례[/color]\n"
            + "■ 자국  ■ 동맹/우호\n"
            + "■ 적국/전쟁  ■ 중립"
        )
    elif mode == "terrain":
        ui.legend.text = (
            "[color=#d2b16c]범례[/color]\n"
            + "■ 평원  ■ 구릉\n"
            + "■ 숲  ■ 해안"
        )
    else:
        ui.legend.text = (
            "[color=#d2b16c]범례[/color]\n"
            + "낮음  ░▒▓█  높음\n"
            + "8–92 분위수 정규화"
        )


func _map_tooltip(text: String, position: Vector2) -> void:
    if text.is_empty():
        ui.tooltip.hide()
        return

    ui.tooltip_label.text = text
    ui.tooltip.position = position + Vector2(14, 14)
    ui.tooltip.show()
    ui.tooltip.position = ui.tooltip.position.clamp(
        Vector2(8, 8),
        get_viewport_rect().size - ui.tooltip.size - Vector2(8, 8)
    )


func _search_province(query: String) -> void:
    var needle := query.strip_edges().to_lower()
    for province_id_value in gateway.snapshot().get("provinces", {}).keys():
        var province_id := int(province_id_value)
        if needle in _province_name(province_id).to_lower():
            selected_province = province_id
            _game_map().selected_province_id = province_id
            _game_map().focus_province(province_id)
            _refresh_province()
            return
    _notify("일치하는 Province가 없습니다.", "warning")


# War and event presentation -------------------------------------------------

func _refresh_wars() -> void:
    if not ui.has("wars"):
        return

    var wars: Array = gateway.snapshot().get("wars", [])
    if wars.is_empty():
        ui.wars.text = (
            "[color=#85949a]진행 중인 전쟁이 없습니다.[/color]"
        )
        return

    var text := "[font_size=18][color=#dec77f]전쟁 현황[/color][/font_size]\n"
    for war_value in wars:
        if war_value is not Dictionary:
            continue
        var war: Dictionary = war_value
        text += "\n%s ⚔ %s · 전쟁 점수 %s" % [
            _country_name(String(war.get("attacker", ""))),
            _country_name(String(war.get("defender", ""))),
            str(war.get("war_score", war.get("score", 0)))
        ]
    ui.wars.text = text


func _add_log(
    category: String,
    message: String,
    importance: String = "normal"
) -> void:
    logs.append({
        "category": category,
        "message": message,
        "importance": importance,
        "time": Time.get_time_string_from_system()
    })
    if logs.size() > LOG_LIMIT:
        logs.pop_front()

    if ui.has("alert_button"):
        ui.alert_button.text = "알림 %d" % logs.size()
    _refresh_logs("전체")


func _filter_logs(category: String) -> void:
    _refresh_logs(category)


func _refresh_logs(filter: String) -> void:
    if not ui.has("log"):
        return

    var text := ""
    for entry in logs:
        if not _log_matches_filter(entry, filter):
            continue

        var color := _log_color(entry)
        text += (
            "[color=#748087]%s[/color] "
            + "[color=%s][%s][/color] %s\n"
        ) % [
            entry.get("time", ""),
            color,
            entry.get("category", ""),
            entry.get("message", "")
        ]

    ui.log.text = text
    ui.log.scroll_to_line(maxi(0, ui.log.get_line_count() - 1))


func _log_matches_filter(entry: Dictionary, filter: String) -> bool:
    if filter == "전체":
        return true
    if String(entry.get("category", "")) == filter:
        return true
    return (
        filter == "중요"
        and String(entry.get("importance", "")) == "important"
    )


func _log_color(entry: Dictionary) -> String:
    if String(entry.get("importance", "")) == "important":
        return "#e1b56d"

    match String(entry.get("category", "")):
        "전쟁":
            return "#e18070"
        "외교":
            return "#78b7c5"
        "경제":
            return "#83bd8d"
    return "#d4cfc0"


func _notify(message: String, kind: String = "info") -> void:
    ui.toast_label.text = message
    var border := "#d0ad64"

    match kind:
        "success":
            border = "#6fb292"
        "warning":
            border = "#d38d62"
        "error":
            border = "#c85c5c"

    toast.add_theme_stylebox_override(
        "panel",
        _style("#22313a", border, 1, 8)
    )
    toast.show()
    toast_timer.start(3.2)
    _on_resize()


# Settings and layout --------------------------------------------------------

func _settings() -> void:
    var dialog := AcceptDialog.new()
    dialog.title = "설정"
    dialog.dialog_text = (
        "UI 배율·접근성 설정은 저장 API 연결 후 영구 보관됩니다.\n"
        + "현재 화면은 Container와 anchor로 반응형 배치됩니다."
    )
    dialog.confirmed.connect(dialog.queue_free)
    dialog.canceled.connect(dialog.queue_free)
    add_child(dialog)
    dialog.popup_centered(Vector2i(520, 220))


func _on_resize() -> void:
    if toast == null:
        return
    toast.position = Vector2(
        get_viewport_rect().size.x * 0.5
        - toast.custom_minimum_size.x * 0.5,
        18
    )


func _frame_map(strategy_map: StrategicMap) -> void:
    if strategy_map != null:
        strategy_map.frame_world()


func _bottom_tab(index: int) -> void:
    ui.bottom_tabs.current_tab = clampi(
        index,
        0,
        ui.bottom_tabs.get_tab_count() - 1
    )


func _game_map() -> StrategicMap:
    return maps.get(ScreenState.GAME) as StrategicMap


# Compatibility and semantic helper adapters --------------------------------

func _owned_selected() -> bool:
    if selected_province == -1:
        _notify("먼저 Province를 선택하세요.", "warning")
        return false
    if (
        String(gateway.province(selected_province).get("owner", ""))
        != selected_country
    ):
        _notify("자국 Province에서만 실행할 수 있습니다.", "warning")
        return false
    return true


func _foreign_country() -> String:
    return read_model.foreign_country(
        selected_province,
        selected_country
    )


func _margin(amount: int) -> MarginContainer:
    return ProjectEpochUiFactoryScript.margin_container(amount)


func _header(
    title: String,
    subtitle: String,
    back_action: Callable
) -> Control:
    return ProjectEpochUiFactoryScript.header(
        title,
        subtitle,
        back_action
    )


func _section(title: String, minimum_width: int = 0) -> VBoxContainer:
    return ProjectEpochUiFactoryScript.section(title, minimum_width)


func _window_box(window: Window) -> VBoxContainer:
    return ProjectEpochUiFactoryScript.window_box(window)


func _label(
    text: String,
    font_size: int = 14,
    color: Color = Color.WHITE,
    alignment: int = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
    return ProjectEpochUiFactoryScript.label(
        text,
        font_size,
        color,
        alignment
    )


func _button(
    text: String,
    action: Callable,
    variant: String = "default",
    minimum_height: int = 40
) -> Button:
    return ProjectEpochUiFactoryScript.button(
        text,
        action,
        variant,
        minimum_height
    )


func _stat(caption: String, value: String) -> Label:
    return ProjectEpochUiFactoryScript.stat(caption, value)


func _style(
    background: String,
    border: String,
    border_width: int,
    corner_radius: int
) -> StyleBoxFlat:
    return ProjectEpochUiFactoryScript.style(
        background,
        border,
        border_width,
        corner_radius
    )


func _number(value: int) -> String:
    return read_model.number(value)


func _country_name(country_id: String) -> String:
    return read_model.country_name(country_id)


func _province_name(province_id: int) -> String:
    return read_model.province_name(province_id)


func _terrain(terrain_id: String) -> String:
    return read_model.terrain_name(terrain_id)


func _difficulty(country: Dictionary) -> String:
    return read_model.difficulty(country)


func _owned(country_id: String) -> Array[int]:
    return read_model.owned_provinces(country_id)


func _country_total(country_id: String, field_name: String) -> int:
    return read_model.country_total(country_id, field_name)


func _army_total(country_id: String) -> int:
    return read_model.army_total(country_id)


func _income(country_id: String) -> int:
    return read_model.income(country_id)


func _has_neighbor(province: Dictionary, target_id: int) -> bool:
    return read_model.has_neighbor(province, target_id)


func _neighbor_names(neighbor_ids: Array) -> String:
    return read_model.neighbor_names(neighbor_ids)


func _border_names(
    first_country_id: String,
    second_country_id: String
) -> String:
    return read_model.border_names(
        first_country_id,
        second_country_id
    )


func _command_icon(command_type: String) -> String:
    return read_model.command_icon(command_type)


func _diplomacy_name(command_type: String) -> String:
    return read_model.diplomacy_name(command_type)
