extends Node2D

var state := GameState.new()
var map: ProvinceMap
var info_label: Label
var turn_label: Label
var country_label: Label
var log_label: RichTextLabel
var command_label: Label
var queue_label: RichTextLabel
var selected_country_option: OptionButton
var selected_source_id: int = -1

func _ready() -> void:
    state.load_game_data()
    _build_background()
    _build_map()
    _build_ui()
    _refresh_all()

func _build_background() -> void:
    RenderingServer.set_default_clear_color(Color("#0d1219"))

func _build_map() -> void:
    map = ProvinceMap.new()
    map.position = Vector2(34, 74)
    map.setup(state)
    map.province_selected.connect(_on_province_selected)
    map.province_commanded.connect(_on_province_commanded)
    add_child(map)

func _build_ui() -> void:
    var top_bar := Panel.new()
    top_bar.position = Vector2(16, 12)
    top_bar.size = Vector2(1248, 50)
    add_child(top_bar)

    var title := Label.new()
    title.text = "PROJECT EPOCH · %s" % String(state.scenario.get("name", "시나리오"))
    title.position = Vector2(18, 13)
    title.add_theme_font_size_override("font_size", 19)
    top_bar.add_child(title)

    turn_label = Label.new()
    turn_label.position = Vector2(350, 15)
    top_bar.add_child(turn_label)

    country_label = Label.new()
    country_label.position = Vector2(535, 15)
    top_bar.add_child(country_label)

    var next_turn := Button.new()
    next_turn.text = "턴 실행"
    next_turn.position = Vector2(1100, 7)
    next_turn.size = Vector2(128, 36)
    next_turn.pressed.connect(_on_next_turn)
    top_bar.add_child(next_turn)

    var panel := Panel.new()
    panel.position = Vector2(870, 76)
    panel.size = Vector2(394, 620)
    add_child(panel)

    var nation_title := Label.new()
    nation_title.text = "플레이 국가"
    nation_title.position = Vector2(18, 14)
    panel.add_child(nation_title)

    selected_country_option = OptionButton.new()
    selected_country_option.position = Vector2(18, 38)
    selected_country_option.size = Vector2(358, 34)
    for country_id_value in state.countries.keys():
        var country_id := String(country_id_value)
        var country: Dictionary = state.countries[country_id]
        selected_country_option.add_item("%s · %s" % [country.name, country.government])
        selected_country_option.set_item_metadata(selected_country_option.item_count - 1, country_id)
        if country_id == state.player_country_id:
            selected_country_option.select(selected_country_option.item_count - 1)
    selected_country_option.item_selected.connect(_on_country_changed)
    panel.add_child(selected_country_option)

    var mode_title := Label.new()
    mode_title.text = "지도 모드"
    mode_title.position = Vector2(18, 82)
    panel.add_child(mode_title)

    var mode_specs := [
        ["정치", "political"],
        ["경제", "economy"],
        ["인구", "population"],
        ["관계", "relations"]
    ]
    for index in range(mode_specs.size()):
        var button := Button.new()
        button.text = mode_specs[index][0]
        button.position = Vector2(18 + index * 88, 106)
        button.size = Vector2(82, 32)
        var mode := String(mode_specs[index][1])
        button.pressed.connect(func(): _set_map_mode(mode))
        panel.add_child(button)

    info_label = Label.new()
    info_label.position = Vector2(18, 150)
    info_label.size = Vector2(358, 160)
    info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info_label.text = "Province를 클릭하면 상세 정보가 표시됩니다."
    panel.add_child(info_label)

    var recruit := Button.new()
    recruit.text = "병력 10 모집 예약"
    recruit.position = Vector2(18, 314)
    recruit.size = Vector2(172, 38)
    recruit.pressed.connect(_on_recruit)
    panel.add_child(recruit)

    var command := Button.new()
    command.text = "이동 명령 준비"
    command.position = Vector2(204, 314)
    command.size = Vector2(172, 38)
    command.pressed.connect(_on_prepare_command)
    panel.add_child(command)

    var war_button := Button.new()
    war_button.text = "전쟁 선포 예약"
    war_button.position = Vector2(18, 360)
    war_button.size = Vector2(172, 36)
    war_button.pressed.connect(_on_declare_war)
    panel.add_child(war_button)

    var peace_button := Button.new()
    peace_button.text = "평화 제안 예약"
    peace_button.position = Vector2(204, 360)
    peace_button.size = Vector2(172, 36)
    peace_button.pressed.connect(_on_offer_peace)
    panel.add_child(peace_button)

    var clear_button := Button.new()
    clear_button.text = "예약 명령 전체 취소"
    clear_button.position = Vector2(18, 404)
    clear_button.size = Vector2(172, 32)
    clear_button.pressed.connect(_on_clear_commands)
    panel.add_child(clear_button)

    command_label = Label.new()
    command_label.position = Vector2(204, 404)
    command_label.size = Vector2(172, 42)
    command_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    command_label.text = "중클릭 드래그 · 휠 확대"
    panel.add_child(command_label)

    var queue_title := Label.new()
    queue_title.text = "이번 턴 예약 명령"
    queue_title.position = Vector2(18, 446)
    panel.add_child(queue_title)

    queue_label = RichTextLabel.new()
    queue_label.position = Vector2(18, 468)
    queue_label.size = Vector2(358, 62)
    queue_label.fit_content = false
    queue_label.scroll_active = true
    panel.add_child(queue_label)

    var log_title := Label.new()
    log_title.text = "턴 처리 로그"
    log_title.position = Vector2(18, 536)
    panel.add_child(log_title)

    log_label = RichTextLabel.new()
    log_label.position = Vector2(18, 558)
    log_label.size = Vector2(358, 50)
    log_label.fit_content = false
    log_label.scroll_active = true
    log_label.text = "시나리오 시작 · 명령을 예약한 뒤 턴을 실행하십시오.\n"
    panel.add_child(log_label)

func _on_province_selected(id: int) -> void:
    state.selected_province_id = id
    selected_source_id = -1
    command_label.text = "선택 완료 · 이동 버튼으로 출발지 지정"
    _refresh_province_info()

func _on_prepare_command() -> void:
    if state.selected_province_id == -1:
        _append_log("먼저 출발 Province를 선택하십시오.")
        return
    var province: Dictionary = state.provinces[state.selected_province_id]
    if String(province.owner) != state.player_country_id:
        _append_log("자국 Province만 출발지로 지정할 수 있습니다.")
        return
    selected_source_id = state.selected_province_id
    command_label.text = "%s → 대상 우클릭" % province.name

func _on_province_commanded(target_id: int) -> void:
    if selected_source_id == -1:
        command_label.text = "이동 명령 준비 후 대상 Province를 우클릭"
        return
    var result := state.queue_move(selected_source_id, target_id)
    _append_log(result)
    if result.begins_with("명령 #"):
        selected_source_id = -1
        command_label.text = "이동 명령 예약 완료"
    _refresh_all()

func _on_recruit() -> void:
    if state.selected_province_id == -1:
        _append_log("병력을 모집할 Province를 선택하십시오.")
        return
    _append_log(state.queue_recruit(state.selected_province_id, 10))
    _refresh_all()

func _on_declare_war() -> void:
    var target_country := _selected_foreign_country()
    if target_country == "":
        _append_log("전쟁을 선포할 외국 Province를 선택하십시오.")
        return
    _append_log(state.queue_declare_war(target_country))
    _refresh_all()

func _on_offer_peace() -> void:
    var target_country := _selected_foreign_country()
    if target_country == "":
        _append_log("평화를 제안할 외국 Province를 선택하십시오.")
        return
    _append_log(state.queue_offer_peace(target_country))
    _refresh_all()

func _on_clear_commands() -> void:
    selected_source_id = -1
    _append_log(state.clear_player_commands())
    _refresh_all()

func _on_next_turn() -> void:
    selected_source_id = -1
    var logs := state.advance_turn()
    for line in logs:
        _append_log(line)
    command_label.text = "턴 처리 완료"
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
    command_label.text = "지도: %s" % {"political":"정치", "economy":"경제", "population":"인구", "relations":"관계"}[mode]

func _selected_foreign_country() -> String:
    if state.selected_province_id == -1 or not state.provinces.has(state.selected_province_id):
        return ""
    var owner := String(state.provinces[state.selected_province_id].owner)
    return "" if owner == state.player_country_id else owner

func _refresh_all() -> void:
    _refresh_turn_label()
    _refresh_country_label()
    _refresh_province_info()
    _refresh_command_queue()
    map.refresh()

func _refresh_turn_label() -> void:
    turn_label.text = "턴 %d · %s" % [state.turn, state.current_date_text()]

func _refresh_country_label() -> void:
    var country: Dictionary = state.countries[state.player_country_id]
    country_label.text = "%s · 국고 %d · 안정 %d · 인력 %d · 군대 %d · 영토 %d" % [
        country.name, country.treasury, country.stability, country.manpower,
        state.total_army(state.player_country_id), state.owned_provinces(state.player_country_id).size()
    ]

func _refresh_province_info() -> void:
    if state.selected_province_id == -1 or not state.provinces.has(state.selected_province_id):
        info_label.text = "Province를 클릭하면 상세 정보가 표시됩니다."
        return
    var province: Dictionary = state.provinces[state.selected_province_id]
    var owner_id := String(province.owner)
    var owner: Dictionary = state.countries[owner_id]
    var relation_text := state.diplomacy.relation_label(state.player_country_id, owner_id)
    var relation_value := state.diplomacy.relation(state.player_country_id, owner_id)
    var war_score := state.diplomacy.war_score(state.player_country_id, owner_id)
    info_label.text = "[ %s ]\n소유국: %s · %s (%d)\n정부: %s · 기술: %d\n인구: %d · 경제: %d · 개발: %d\n지형: %s · 요새: %d\n주둔군: %d · 예상 방어력: %.1f\n전쟁 점수: %d · 인접: %s" % [
        province.name, owner.name, relation_text, relation_value,
        owner.government, int(owner.technology), province.population, province.economy,
        int(province.get("development", 1)), province.terrain, int(province.get("fort", 0)),
        int(state.armies.get(state.selected_province_id, 0)), state.estimated_defense(state.selected_province_id),
        war_score, str(province.neighbors)
    ]

func _refresh_command_queue() -> void:
    var lines := state.command_queue.summary_for_country(state.player_country_id, state)
    queue_label.text = "예약 명령 없음" if lines.is_empty() else "\n".join(lines)

func _append_log(text: String) -> void:
    log_label.append_text("턴 %d | %s\n" % [state.turn, text])
    log_label.scroll_to_line(max(0, log_label.get_line_count() - 1))
