extends Node2D

var state := GameState.new()
var map: ProvinceMap
var info_label: Label
var turn_label: Label
var country_label: Label
var log_label: RichTextLabel
var command_label: Label
var selected_country_option: OptionButton
var selected_source_id: int = -1

func _ready() -> void:
    state.load_game_data()
    _build_background()
    _build_map()
    _build_ui()
    _refresh_all()

func _build_background() -> void:
    RenderingServer.set_default_clear_color(Color("#11161d"))

func _build_map() -> void:
    map = ProvinceMap.new()
    map.position = Vector2(40, 70)
    map.setup(state)
    map.province_selected.connect(_on_province_selected)
    map.province_commanded.connect(_on_province_commanded)
    add_child(map)

func _build_ui() -> void:
    var top_bar := Panel.new()
    top_bar.position = Vector2(18, 14)
    top_bar.size = Vector2(1244, 48)
    add_child(top_bar)

    var title := Label.new()
    title.text = "PROJECT EPOCH"
    title.position = Vector2(18, 12)
    title.add_theme_font_size_override("font_size", 20)
    top_bar.add_child(title)

    turn_label = Label.new()
    turn_label.position = Vector2(220, 14)
    top_bar.add_child(turn_label)

    country_label = Label.new()
    country_label.position = Vector2(430, 14)
    top_bar.add_child(country_label)

    var next_turn := Button.new()
    next_turn.text = "다음 턴"
    next_turn.position = Vector2(1100, 6)
    next_turn.size = Vector2(125, 36)
    next_turn.pressed.connect(_on_next_turn)
    top_bar.add_child(next_turn)

    var panel := Panel.new()
    panel.position = Vector2(890, 76)
    panel.size = Vector2(372, 620)
    add_child(panel)

    var nation_title := Label.new()
    nation_title.text = "플레이 국가"
    nation_title.position = Vector2(20, 18)
    panel.add_child(nation_title)

    selected_country_option = OptionButton.new()
    selected_country_option.position = Vector2(20, 44)
    selected_country_option.size = Vector2(330, 36)
    for country_id in state.countries.keys():
        var country: Dictionary = state.countries[country_id]
        selected_country_option.add_item(String(country.name))
        selected_country_option.set_item_metadata(selected_country_option.item_count - 1, String(country_id))
        if String(country_id) == state.player_country_id:
            selected_country_option.select(selected_country_option.item_count - 1)
    selected_country_option.item_selected.connect(_on_country_changed)
    panel.add_child(selected_country_option)

    var mode_title := Label.new()
    mode_title.text = "지도 모드"
    mode_title.position = Vector2(20, 94)
    panel.add_child(mode_title)

    var political := Button.new()
    political.text = "정치"
    political.position = Vector2(20, 120)
    political.size = Vector2(100, 34)
    political.pressed.connect(func(): _set_map_mode("political"))
    panel.add_child(political)

    var economy := Button.new()
    economy.text = "경제"
    economy.position = Vector2(130, 120)
    economy.size = Vector2(100, 34)
    economy.pressed.connect(func(): _set_map_mode("economy"))
    panel.add_child(economy)

    var population := Button.new()
    population.text = "인구"
    population.position = Vector2(240, 120)
    population.size = Vector2(100, 34)
    population.pressed.connect(func(): _set_map_mode("population"))
    panel.add_child(population)

    info_label = Label.new()
    info_label.position = Vector2(20, 174)
    info_label.size = Vector2(330, 205)
    info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info_label.text = "Province를 클릭하면 상세 정보가 표시됩니다."
    panel.add_child(info_label)

    var recruit := Button.new()
    recruit.text = "병력 10 모집"
    recruit.position = Vector2(20, 384)
    recruit.size = Vector2(155, 40)
    recruit.pressed.connect(_on_recruit)
    panel.add_child(recruit)

    var command := Button.new()
    command.text = "이동/공격 준비"
    command.position = Vector2(190, 384)
    command.size = Vector2(160, 40)
    command.pressed.connect(_on_prepare_command)
    panel.add_child(command)

    command_label = Label.new()
    command_label.position = Vector2(20, 432)
    command_label.size = Vector2(330, 48)
    command_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    command_label.text = "중클릭 드래그: 지도 이동 · 휠: 확대/축소"
    panel.add_child(command_label)

    var divider := HSeparator.new()
    divider.position = Vector2(20, 478)
    divider.size = Vector2(330, 8)
    panel.add_child(divider)

    var log_title := Label.new()
    log_title.text = "전략 로그"
    log_title.position = Vector2(20, 494)
    panel.add_child(log_title)

    log_label = RichTextLabel.new()
    log_label.position = Vector2(20, 522)
    log_label.size = Vector2(330, 82)
    log_label.fit_content = false
    log_label.scroll_active = true
    log_label.text = "시뮬레이션 시작\n"
    panel.add_child(log_label)

func _on_province_selected(id: int) -> void:
    state.selected_province_id = id
    selected_source_id = -1
    command_label.text = "Province 선택 완료. 이동/공격 준비 버튼으로 명령을 시작하십시오."
    _refresh_province_info()

func _on_prepare_command() -> void:
    if state.selected_province_id == -1:
        _append_log("먼저 출발 Province를 선택하십시오.")
        return
    var province: Dictionary = state.provinces[state.selected_province_id]
    if String(province.owner) != state.player_country_id:
        _append_log("자국 Province만 출발지로 선택할 수 있습니다.")
        return
    selected_source_id = state.selected_province_id
    command_label.text = "%s에서 출발: 대상 Province를 우클릭하십시오." % province.name

func _on_province_commanded(target_id: int) -> void:
    if selected_source_id == -1:
        command_label.text = "이동/공격 준비를 먼저 누른 뒤 대상 Province를 우클릭하십시오."
        return
    var result := state.move_or_attack(selected_source_id, target_id)
    _append_log(result)
    state.selected_province_id = target_id
    map.selected_id = target_id
    selected_source_id = -1
    command_label.text = "명령 처리 완료."
    _refresh_all()

func _on_recruit() -> void:
    if state.selected_province_id == -1:
        _append_log("병력을 모집할 Province를 선택하십시오.")
        return
    _append_log(state.recruit_army(state.selected_province_id, 10))
    _refresh_all()

func _on_next_turn() -> void:
    var logs := state.advance_turn()
    for line in logs:
        _append_log(line)
    _refresh_all()

func _on_country_changed(index: int) -> void:
    var country_id := String(selected_country_option.get_item_metadata(index))
    state.set_player_country(country_id)
    selected_source_id = -1
    _append_log("플레이 국가를 %s(으)로 변경했습니다." % state.countries[country_id].name)
    _refresh_all()

func _set_map_mode(mode: String) -> void:
    state.set_map_mode(mode)
    map.refresh()
    command_label.text = "지도 모드: %s" % {"political":"정치", "economy":"경제", "population":"인구"}[mode]

func _refresh_all() -> void:
    _refresh_turn_label()
    _refresh_country_label()
    _refresh_province_info()
    map.refresh()

func _refresh_turn_label() -> void:
    turn_label.text = "턴 %d · %s" % [state.turn, state.current_date_text()]

func _refresh_country_label() -> void:
    var country: Dictionary = state.countries[state.player_country_id]
    country_label.text = "%s · 국고 %d · 안정도 %d · 인력 %d" % [country.name, country.treasury, country.stability, country.manpower]

func _refresh_province_info() -> void:
    if state.selected_province_id == -1 or not state.provinces.has(state.selected_province_id):
        info_label.text = "Province를 클릭하면 상세 정보가 표시됩니다."
        return
    var province: Dictionary = state.provinces[state.selected_province_id]
    var owner: Dictionary = state.countries[province.owner]
    info_label.text = "[ %s ]\n\n소유국: %s\n인구: %d\n경제: %d\n개발도: %d\n지형: %s\n주둔군: %d\n요새: %d\n인접 Province: %s" % [
        province.name, owner.name, province.population, province.economy,
        int(province.get("development", 1)), province.terrain,
        int(state.armies.get(state.selected_province_id, 0)),
        int(province.get("fort", 0)), str(province.neighbors)
    ]

func _append_log(text: String) -> void:
    log_label.append_text("턴 %d | %s\n" % [state.turn, text])
    log_label.scroll_to_line(max(0, log_label.get_line_count() - 1))
