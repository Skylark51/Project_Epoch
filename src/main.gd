extends Node

const GameStateScript = preload("res://src/core/game_state.gd")
const ProvinceMapScript = preload("res://src/map/province_map.gd")

var state
var map
var selected_source_id: int = -1

@onready var root = get_parent()
@onready var game_world = root.get_node("MapFrame/GameWorld")
@onready var map_hint = root.get_node("MapFrame/MapHint")
@onready var turn_label = root.get_node("TopBar/TurnLabel")
@onready var country_label = root.get_node("TopBar/CountryLabel")
@onready var run_turn_button = root.get_node("TopBar/RunTurnButton")
@onready var country_option = root.get_node("RightPanel/CountryOption")
@onready var info_label = root.get_node("RightPanel/InfoLabel")
@onready var command_label = root.get_node("RightPanel/CommandLabel")
@onready var queue_label = root.get_node("RightPanel/QueueLabel")
@onready var log_label = root.get_node("RightPanel/LogLabel")
@onready var political_button = root.get_node("RightPanel/PoliticalButton")
@onready var economy_button = root.get_node("RightPanel/EconomyButton")
@onready var population_button = root.get_node("RightPanel/PopulationButton")
@onready var relations_button = root.get_node("RightPanel/RelationsButton")
@onready var recruit_button = root.get_node("RightPanel/RecruitButton")
@onready var move_button = root.get_node("RightPanel/MoveButton")
@onready var war_button = root.get_node("RightPanel/WarButton")
@onready var peace_button = root.get_node("RightPanel/PeaceButton")
@onready var clear_button = root.get_node("RightPanel/ClearButton")

func _ready() -> void:
    log_label.text = "컨트롤러 시작 · 데이터 파일 확인 중"
    state = GameStateScript.new()
    state.load_game_data()

    if state.countries.is_empty() or state.provinces.is_empty():
        turn_label.text = "데이터 로딩 실패"
        country_label.text = "Godot Output에서 JSON 오류를 확인하십시오."
        map_hint.text = "국가 또는 Province 데이터가 비어 있습니다."
        log_label.text = "초기화 실패: data/countries.json 또는 data/provinces.json"
        return

    _connect_ui()
    _populate_country_option()
    _create_map()
    _refresh_all()
    log_label.text = "게임 시작 · 국가와 Province를 선택하십시오."

func _connect_ui() -> void:
    run_turn_button.pressed.connect(_on_next_turn)
    country_option.item_selected.connect(_on_country_changed)
    political_button.pressed.connect(_on_political_mode)
    economy_button.pressed.connect(_on_economy_mode)
    population_button.pressed.connect(_on_population_mode)
    relations_button.pressed.connect(_on_relations_mode)
    recruit_button.pressed.connect(_on_recruit)
    move_button.pressed.connect(_on_prepare_command)
    war_button.pressed.connect(_on_declare_war)
    peace_button.pressed.connect(_on_offer_peace)
    clear_button.pressed.connect(_on_clear_commands)

func _populate_country_option() -> void:
    country_option.clear()
    var selected_index: int = 0
    var index: int = 0
    for country_id_value in state.countries.keys():
        var country_id := String(country_id_value)
        var country: Dictionary = state.countries[country_id]
        country_option.add_item("%s · %s" % [String(country.get("name", country_id)), String(country.get("government", "정부"))])
        country_option.set_item_metadata(index, country_id)
        if country_id == state.player_country_id:
            selected_index = index
        index += 1
    country_option.select(selected_index)

func _create_map() -> void:
    map = ProvinceMapScript.new()
    map.position = Vector2.ZERO
    game_world.add_child(map)
    map.setup(state)
    map.province_selected.connect(_on_province_selected)
    map.province_commanded.connect(_on_province_commanded)
    map_hint.visible = false

func _on_political_mode() -> void:
    _set_map_mode("political", "정치")

func _on_economy_mode() -> void:
    _set_map_mode("economy", "경제")

func _on_population_mode() -> void:
    _set_map_mode("population", "인구")

func _on_relations_mode() -> void:
    _set_map_mode("relations", "관계")

func _set_map_mode(mode: String, label: String) -> void:
    state.set_map_mode(mode)
    command_label.text = "지도 모드: %s" % label
    map.refresh()

func _on_province_selected(province_id: int) -> void:
    state.selected_province_id = province_id
    selected_source_id = -1
    command_label.text = "Province 선택 완료"
    _refresh_province_info()

func _on_prepare_command() -> void:
    if state.selected_province_id == -1:
        _append_log("먼저 출발 Province를 선택하십시오.")
        return
    var province: Dictionary = state.provinces[state.selected_province_id]
    if String(province.get("owner", "")) != state.player_country_id:
        _append_log("자국 Province만 출발지로 지정할 수 있습니다.")
        return
    selected_source_id = state.selected_province_id
    command_label.text = "%s → 대상 우클릭" % String(province.get("name", "Province"))

func _on_province_commanded(target_id: int) -> void:
    if selected_source_id == -1:
        command_label.text = "이동 명령 준비 후 대상을 우클릭"
        return
    var result: String = state.queue_move(selected_source_id, target_id)
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
    var logs: Array[String] = state.advance_turn()
    for line in logs:
        _append_log(line)
    command_label.text = "턴 처리 완료"
    _refresh_all()

func _on_country_changed(index: int) -> void:
    var country_id := String(country_option.get_item_metadata(index))
    state.set_player_country(country_id)
    selected_source_id = -1
    _append_log("플레이 국가를 %s(으)로 변경했습니다." % String(state.countries[country_id].get("name", country_id)))
    _refresh_all()

func _selected_foreign_country() -> String:
    if state.selected_province_id == -1:
        return ""
    if not state.provinces.has(state.selected_province_id):
        return ""
    var owner := String(state.provinces[state.selected_province_id].get("owner", ""))
    if owner == state.player_country_id:
        return ""
    return owner

func _refresh_all() -> void:
    _refresh_turn_label()
    _refresh_country_label()
    _refresh_province_info()
    _refresh_command_queue()
    if map != null:
        map.refresh()

func _refresh_turn_label() -> void:
    turn_label.text = "턴 %d · %s" % [state.turn, state.current_date_text()]

func _refresh_country_label() -> void:
    var country: Dictionary = state.countries[state.player_country_id]
    country_label.text = "%s · 국고 %d · 안정 %d · 인력 %d · 군대 %d · 영토 %d" % [
        String(country.get("name", state.player_country_id)),
        int(country.get("treasury", 0)),
        int(country.get("stability", 0)),
        int(country.get("manpower", 0)),
        state.total_army(state.player_country_id),
        state.owned_provinces(state.player_country_id).size()
    ]

func _refresh_province_info() -> void:
    if state.selected_province_id == -1:
        info_label.text = "Province를 클릭하면 상세 정보가 표시됩니다."
        return
    if not state.provinces.has(state.selected_province_id):
        info_label.text = "선택한 Province 데이터가 없습니다."
        return

    var province: Dictionary = state.provinces[state.selected_province_id]
    var owner_id := String(province.get("owner", ""))
    var owner: Dictionary = state.countries.get(owner_id, {})
    var relation_text := state.diplomacy.relation_label(state.player_country_id, owner_id)
    var relation_value := state.diplomacy.relation(state.player_country_id, owner_id)
    var war_score := state.diplomacy.war_score(state.player_country_id, owner_id)

    info_label.text = "[ %s ]\n소유국: %s · %s (%d)\n정부: %s · 기술: %d\n인구: %d · 경제: %d · 개발: %d\n지형: %s · 요새: %d\n주둔군: %d · 예상 방어력: %.1f\n전쟁 점수: %d · 인접: %s" % [
        String(province.get("name", "Province")),
        String(owner.get("name", owner_id)),
        relation_text,
        relation_value,
        String(owner.get("government", "정부")),
        int(owner.get("technology", 1)),
        int(province.get("population", 0)),
        int(province.get("economy", 0)),
        int(province.get("development", 1)),
        String(province.get("terrain", "plains")),
        int(province.get("fort", 0)),
        int(state.armies.get(state.selected_province_id, 0)),
        state.estimated_defense(state.selected_province_id),
        war_score,
        str(province.get("neighbors", []))
    ]

func _refresh_command_queue() -> void:
    var lines: Array[String] = state.command_queue.summary_for_country(state.player_country_id, state)
    if lines.is_empty():
        queue_label.text = "예약 명령 없음"
    else:
        queue_label.text = "\n".join(lines)

func _append_log(text: String) -> void:
    log_label.append_text("\n턴 %d | %s" % [state.turn, text])
    log_label.scroll_to_line(max(0, log_label.get_line_count() - 1))
