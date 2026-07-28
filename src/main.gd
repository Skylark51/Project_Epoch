extends Node2D

var state := GameState.new()
var map: ProvinceMap
var info_label: Label
var turn_label: Label
var log_label: RichTextLabel

func _ready() -> void:
    state.load_game_data()
    _build_background()
    _build_map()
    _build_ui()

func _build_background() -> void:
    RenderingServer.set_default_clear_color(Color("#171b20"))

func _build_map() -> void:
    map = ProvinceMap.new()
    map.position = Vector2(30, 60)
    map.setup(state)
    map.province_selected.connect(_on_province_selected)
    add_child(map)

func _build_ui() -> void:
    var panel := Panel.new()
    panel.position = Vector2(800, 24)
    panel.size = Vector2(450, 660)
    add_child(panel)

    var title := Label.new()
    title.text = "PROJECT EPOCH — 전략 프로토타입"
    title.position = Vector2(24, 20)
    title.add_theme_font_size_override("font_size", 22)
    panel.add_child(title)

    turn_label = Label.new()
    turn_label.position = Vector2(24, 66)
    panel.add_child(turn_label)
    _refresh_turn_label()

    var next_turn := Button.new()
    next_turn.text = "다음 턴"
    next_turn.position = Vector2(300, 56)
    next_turn.size = Vector2(120, 42)
    next_turn.pressed.connect(_on_next_turn)
    panel.add_child(next_turn)

    info_label = Label.new()
    info_label.position = Vector2(24, 126)
    info_label.size = Vector2(400, 220)
    info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info_label.text = "Province를 클릭하면 상세 정보가 표시됩니다."
    panel.add_child(info_label)

    var divider := HSeparator.new()
    divider.position = Vector2(24, 350)
    divider.size = Vector2(400, 8)
    panel.add_child(divider)

    var log_title := Label.new()
    log_title.text = "턴 처리 로그"
    log_title.position = Vector2(24, 376)
    panel.add_child(log_title)

    log_label = RichTextLabel.new()
    log_label.position = Vector2(24, 410)
    log_label.size = Vector2(400, 210)
    log_label.fit_content = false
    log_label.text = "프로토타입 시작\n"
    panel.add_child(log_label)

func _on_province_selected(id: int) -> void:
    state.selected_province_id = id
    var province: Dictionary = state.provinces[id]
    var owner: Dictionary = state.countries[province.owner]
    info_label.text = "[ %s ]\n\n소유국: %s\n인구: %d\n경제: %d\n지형: %s\n인접 Province: %s\n\n국고: %d\n안정도: %d\n가용 인력: %d" % [
        province.name, owner.name, province.population, province.economy,
        province.terrain, str(province.neighbors), owner.treasury,
        owner.stability, owner.manpower
    ]

func _on_next_turn() -> void:
    var logs := state.advance_turn()
    _refresh_turn_label()
    for line in logs:
        log_label.append_text("턴 %d | %s\n" % [state.turn, line])
    if state.selected_province_id != -1:
        _on_province_selected(state.selected_province_id)

func _refresh_turn_label() -> void:
    turn_label.text = "턴 %d · %d년" % [state.turn, state.date_year]
