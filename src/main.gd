extends Node

const SEASONS = ["봄", "여름", "가을", "겨울"]

var turn: int = 1
var year: int = 1000
var season_index: int = 0
var player_country_id: String = "AUR"
var selected_province_id: int = -1
var move_source_id: int = -1
var map_mode: String = "political"
var next_command_id: int = 1

var countries: Dictionary = {}
var provinces: Dictionary = {}
var armies: Dictionary = {}
var relations: Dictionary = {}
var wars: Dictionary = {}
var commands: Array = []
var province_fills: Dictionary = {}
var province_buttons: Dictionary = {}
var province_names: Dictionary = {}
var province_armies: Dictionary = {}

@onready var root: Control = get_parent() as Control
@onready var turn_label: Label = root.get_node("TopBar/TurnLabel") as Label
@onready var country_label: Label = root.get_node("TopBar/CountryLabel") as Label
@onready var country_option: OptionButton = root.get_node("RightPanel/CountryOption") as OptionButton
@onready var info_label: Label = root.get_node("RightPanel/InfoLabel") as Label
@onready var command_label: Label = root.get_node("RightPanel/CommandLabel") as Label
@onready var queue_label: RichTextLabel = root.get_node("RightPanel/QueueLabel") as RichTextLabel
@onready var log_label: RichTextLabel = root.get_node("RightPanel/LogLabel") as RichTextLabel

func _ready() -> void:
    _cache_nodes()
    _connect_ui()
    _load_game_data()
    if countries.is_empty() or provinces.is_empty():
        turn_label.text = "데이터 로딩 실패"
        country_label.text = "JSON 파일을 확인하십시오."
        log_label.text = "초기화 실패 · Godot Output 확인"
        return
    _populate_country_option()
    _refresh_all()
    _log("게임 시작 · Province를 선택하십시오.")

func _cache_nodes() -> void:
    for province_id in range(1, 7):
        province_fills[province_id] = root.get_node("MapFrame/GameWorld/P%dFill" % province_id)
        province_buttons[province_id] = root.get_node("MapFrame/P%dButton" % province_id)
        province_names[province_id] = root.get_node("MapFrame/P%dName" % province_id)
        province_armies[province_id] = root.get_node("MapFrame/P%dArmy" % province_id)

func _connect_ui() -> void:
    (root.get_node("TopBar/RunTurnButton") as Button).pressed.connect(_on_run_turn)
    country_option.item_selected.connect(_on_country_changed)
    (root.get_node("RightPanel/PoliticalButton") as Button).pressed.connect(_on_political_mode)
    (root.get_node("RightPanel/EconomyButton") as Button).pressed.connect(_on_economy_mode)
    (root.get_node("RightPanel/PopulationButton") as Button).pressed.connect(_on_population_mode)
    (root.get_node("RightPanel/RelationsButton") as Button).pressed.connect(_on_relations_mode)
    (root.get_node("RightPanel/RecruitButton") as Button).pressed.connect(_on_recruit)
    (root.get_node("RightPanel/MoveButton") as Button).pressed.connect(_on_prepare_move)
    (root.get_node("RightPanel/WarButton") as Button).pressed.connect(_on_declare_war)
    (root.get_node("RightPanel/PeaceButton") as Button).pressed.connect(_on_offer_peace)
    (root.get_node("RightPanel/ClearButton") as Button).pressed.connect(_on_clear_commands)
    for province_id_value in province_buttons.keys():
        var province_id: int = int(province_id_value)
        var button: Button = province_buttons[province_id]
        button.pressed.connect(_on_province_clicked.bind(province_id))

func _load_json(path: String):
    var file = FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("파일을 열 수 없습니다: " + path)
        return null
    var parsed = JSON.parse_string(file.get_as_text())
    if parsed == null:
        push_error("JSON 파싱 실패: " + path)
    return parsed

func _load_game_data() -> void:
    var scenario_data = _load_json("res://data/scenarios/001_prototype.json")
    if scenario_data is Dictionary:
        var scenario: Dictionary = scenario_data
        var start_date = scenario.get("start_date", {})
        if start_date is Dictionary:
            year = int(start_date.get("year", 1000))
        player_country_id = String(scenario.get("player_country", "AUR"))

    var country_data = _load_json("res://data/countries.json")
    if country_data is Dictionary:
        for item in country_data.get("countries", []):
            if item is Dictionary:
                var country: Dictionary = item.duplicate(true)
                countries[String(country.get("id", ""))] = country

    var province_data = _load_json("res://data/provinces.json")
    if province_data is Dictionary:
        for item in province_data.get("provinces", []):
            if item is Dictionary:
                var province: Dictionary = item.duplicate(true)
                var province_id: int = int(province.get("id", -1))
                provinces[province_id] = province
                armies[province_id] = int(province.get("army", 0))

    var diplomacy_data = _load_json("res://data/diplomacy.json")
    if diplomacy_data is Dictionary:
        for item in diplomacy_data.get("relations", []):
            if item is Dictionary:
                var first: String = String(item.get("a", ""))
                var second: String = String(item.get("b", ""))
                relations[_pair_key(first, second)] = int(item.get("value", 0))
        for item in diplomacy_data.get("wars", []):
            if item is Dictionary:
                var attacker: String = String(item.get("attacker", ""))
                var defender: String = String(item.get("defender", ""))
                wars[_pair_key(attacker, defender)] = {"attacker": attacker, "defender": defender, "score": int(item.get("war_score", 0))}

func _populate_country_option() -> void:
    country_option.clear()
    var selected_index: int = 0
    var index: int = 0
    for country_id_value in countries.keys():
        var country_id: String = String(country_id_value)
        var country: Dictionary = countries[country_id]
        country_option.add_item("%s · %s" % [String(country.get("name", country_id)), String(country.get("government", "정부"))])
        country_option.set_item_metadata(index, country_id)
        if country_id == player_country_id:
            selected_index = index
        index += 1
    country_option.select(selected_index)

func _on_province_clicked(province_id: int) -> void:
    if move_source_id != -1 and province_id != move_source_id:
        _log(_queue_move(move_source_id, province_id))
        move_source_id = -1
        command_label.text = "이동 명령 입력 완료"
    else:
        selected_province_id = province_id
        move_source_id = -1
        command_label.text = "Province 선택 완료"
    _refresh_all()

func _on_prepare_move() -> void:
    if selected_province_id == -1:
        _log("먼저 출발 Province를 선택하십시오.")
        return
    var province: Dictionary = provinces[selected_province_id]
    if String(province.get("owner", "")) != player_country_id:
        _log("자국 Province만 출발지로 지정할 수 있습니다.")
        return
    if int(armies.get(selected_province_id, 0)) <= 1:
        _log("이동 가능한 병력이 부족합니다.")
        return
    move_source_id = selected_province_id
    command_label.text = "%s → 대상 Province 클릭" % String(province.get("name", "Province"))

func _on_recruit() -> void:
    if selected_province_id == -1:
        _log("병력을 모집할 Province를 선택하십시오.")
        return
    var province: Dictionary = provinces[selected_province_id]
    if String(province.get("owner", "")) != player_country_id:
        _log("자국 Province에서만 모집할 수 있습니다.")
        return
    _add_command("recruit", player_country_id, {"province_id": selected_province_id, "amount": 10})
    _log("명령 #%d: %s 병력 10 모집 예약" % [next_command_id - 1, String(province.get("name", "Province"))])
    _refresh_all()

func _queue_move(from_id: int, to_id: int) -> String:
    var source: Dictionary = provinces.get(from_id, {})
    var target: Dictionary = provinces.get(to_id, {})
    if source.is_empty() or target.is_empty():
        return "유효하지 않은 이동입니다."
    if to_id not in source.get("neighbors", []):
        return "인접 Province로만 이동할 수 있습니다."
    var amount: int = int(armies.get(from_id, 0)) - 1
    if amount <= 0:
        return "이동 가능한 병력이 없습니다."
    var target_owner: String = String(target.get("owner", ""))
    if target_owner != player_country_id and not _is_at_war(player_country_id, target_owner) and not _queued_war(target_owner):
        return "%s과 전쟁 중이 아닙니다." % _country_name(target_owner)
    _add_command("move", player_country_id, {"from_id": from_id, "to_id": to_id, "amount": amount})
    return "명령 #%d: %s → %s 병력 %d 이동 예약" % [next_command_id - 1, String(source.get("name", "Province")), String(target.get("name", "Province")), amount]

func _on_declare_war() -> void:
    var target_id: String = _selected_foreign_country()
    if target_id == "":
        _log("전쟁을 선포할 외국 Province를 선택하십시오.")
        return
    if _is_at_war(player_country_id, target_id) or _queued_war(target_id):
        _log("이미 전쟁 중이거나 선포가 예약되어 있습니다.")
        return
    _add_command("declare_war", player_country_id, {"target_country_id": target_id})
    _log("명령 #%d: %s에 전쟁 선포 예약" % [next_command_id - 1, _country_name(target_id)])
    _refresh_all()

func _on_offer_peace() -> void:
    var target_id: String = _selected_foreign_country()
    if target_id == "" or not _is_at_war(player_country_id, target_id):
        _log("전쟁 상대의 Province를 선택하십시오.")
        return
    _add_command("offer_peace", player_country_id, {"target_country_id": target_id})
    _log("명령 #%d: %s에 평화 제안 예약" % [next_command_id - 1, _country_name(target_id)])
    _refresh_all()

func _on_clear_commands() -> void:
    commands.clear()
    next_command_id = 1
    move_source_id = -1
    _log("예약 명령을 모두 취소했습니다.")
    _refresh_all()

func _add_command(command_type: String, country_id: String, payload: Dictionary) -> void:
    commands.append({"id": next_command_id, "type": command_type, "country_id": country_id, "payload": payload.duplicate(true)})
    next_command_id += 1

func _queued_war(target_id: String) -> bool:
    for command_value in commands:
        var command: Dictionary = command_value
        var payload: Dictionary = command.get("payload", {})
        if String(command.get("type", "")) == "declare_war" and String(payload.get("target_country_id", "")) == target_id:
            return true
    return false

func _on_run_turn() -> void:
    var all_commands: Array = commands.duplicate(true)
    commands.clear()
    next_command_id = 1
    all_commands.append_array(_build_ai_commands())
    _log("[명령 수집] 총 %d건" % all_commands.size())
    _process_diplomacy(all_commands)
    _process_recruitment(all_commands)
    _process_movement(all_commands)
    _process_economy()
    turn += 1
    season_index += 1
    if season_index >= SEASONS.size():
        season_index = 0
        year += 1
    move_source_id = -1
    command_label.text = "턴 처리 완료"
    _refresh_all()

func _build_ai_commands() -> Array:
    var result: Array = []
    for country_id_value in countries.keys():
        var country_id: String = String(country_id_value)
        if country_id == player_country_id:
            continue
        var owned: Array = _owned_provinces(country_id)
        if owned.is_empty():
            continue
        var country: Dictionary = countries[country_id]
        if int(country.get("treasury", 0)) >= 10 and int(country.get("manpower", 0)) >= 5:
            result.append({"type": "recruit", "country_id": country_id, "payload": {"province_id": int(owned[0]), "amount": 5}})
        var enemies: Array = _enemies_of(country_id)
        var neighbors: Array = _neighboring_countries(country_id)
        if enemies.is_empty() and not neighbors.is_empty() and int(country.get("aggression", 50)) >= 65:
            var target_country: String = String(neighbors[0])
            result.append({"type": "declare_war", "country_id": country_id, "payload": {"target_country_id": target_country}})
            enemies.append(target_country)
        if not enemies.is_empty():
            for source_id_value in owned:
                var source_id: int = int(source_id_value)
                if int(armies.get(source_id, 0)) <= 3:
                    continue
                for neighbor_id_value in provinces[source_id].get("neighbors", []):
                    var neighbor_id: int = int(neighbor_id_value)
                    if String(provinces[neighbor_id].get("owner", "")) in enemies:
                        result.append({"type": "move", "country_id": country_id, "payload": {"from_id": source_id, "to_id": neighbor_id, "amount": int(armies.get(source_id, 0)) - 1}})
                        break
    return result

func _process_diplomacy(all_commands: Array) -> void:
    _log("[외교 단계]")
    for command_value in all_commands:
        var command: Dictionary = command_value
        var command_type: String = String(command.get("type", ""))
        var country_id: String = String(command.get("country_id", ""))
        var payload: Dictionary = command.get("payload", {})
        var target_id: String = String(payload.get("target_country_id", ""))
        if command_type == "declare_war" and not _is_at_war(country_id, target_id):
            wars[_pair_key(country_id, target_id)] = {"attacker": country_id, "defender": target_id, "score": 0}
            relations[_pair_key(country_id, target_id)] = -80
            _log("%s → %s: 전쟁 시작" % [_country_name(country_id), _country_name(target_id)])
        elif command_type == "offer_peace" and _is_at_war(country_id, target_id):
            wars.erase(_pair_key(country_id, target_id))
            relations[_pair_key(country_id, target_id)] = -20
            _log("%s–%s: 평화 체결" % [_country_name(country_id), _country_name(target_id)])

func _process_recruitment(all_commands: Array) -> void:
    _log("[모집 단계]")
    for command_value in all_commands:
        var command: Dictionary = command_value
        if String(command.get("type", "")) != "recruit":
            continue
        var country_id: String = String(command.get("country_id", ""))
        var payload: Dictionary = command.get("payload", {})
        var province_id: int = int(payload.get("province_id", -1))
        var amount: int = int(payload.get("amount", 0))
        var province: Dictionary = provinces.get(province_id, {})
        var country: Dictionary = countries.get(country_id, {})
        if province.is_empty() or country.is_empty() or String(province.get("owner", "")) != country_id:
            continue
        if int(country.get("treasury", 0)) < amount * 2 or int(country.get("manpower", 0)) < amount:
            continue
        country["treasury"] = int(country.get("treasury", 0)) - amount * 2
        country["manpower"] = int(country.get("manpower", 0)) - amount
        countries[country_id] = country
        armies[province_id] = int(armies.get(province_id, 0)) + amount
        _log("%s: %s에서 병력 %d 모집" % [_country_name(country_id), String(province.get("name", "Province")), amount])

func _process_movement(all_commands: Array) -> void:
    _log("[이동·전투 단계]")
    for command_value in all_commands:
        var command: Dictionary = command_value
        if String(command.get("type", "")) != "move":
            continue
        var country_id: String = String(command.get("country_id", ""))
        var payload: Dictionary = command.get("payload", {})
        var from_id: int = int(payload.get("from_id", -1))
        var to_id: int = int(payload.get("to_id", -1))
        var source: Dictionary = provinces.get(from_id, {})
        var target: Dictionary = provinces.get(to_id, {})
        if source.is_empty() or target.is_empty() or String(source.get("owner", "")) != country_id:
            continue
        var moving: int = min(int(payload.get("amount", 0)), max(0, int(armies.get(from_id, 0)) - 1))
        if moving <= 0:
            continue
        var target_owner: String = String(target.get("owner", ""))
        if target_owner == country_id:
            armies[from_id] = int(armies.get(from_id, 0)) - moving
            armies[to_id] = int(armies.get(to_id, 0)) + moving
            _log("%s: %s → %s 병력 %d 이동" % [_country_name(country_id), String(source.get("name", "Province")), String(target.get("name", "Province")), moving])
        elif _is_at_war(country_id, target_owner):
            armies[from_id] = int(armies.get(from_id, 0)) - moving
            var attack_power: float = float(moving) * (1.0 + float(countries[country_id].get("technology", 1)) * 0.06)
            var defense_power: float = _estimated_defense(to_id)
            if attack_power > defense_power:
                armies[to_id] = max(1, int(round(float(moving) * 0.55)))
                target["owner"] = country_id
                provinces[to_id] = target
                _log("%s: %s 점령 성공" % [_country_name(country_id), String(target.get("name", "Province"))])
            else:
                armies[to_id] = max(1, int(armies.get(to_id, 0)) - max(1, int(moving * 0.25)))
                _log("%s: %s 공격 실패" % [_country_name(country_id), String(target.get("name", "Province"))])

func _process_economy() -> void:
    _log("[경제 단계]")
    for country_id_value in countries.keys():
        var country_id: String = String(country_id_value)
        var owned: Array = _owned_provinces(country_id)
        if owned.is_empty():
            continue
        var country: Dictionary = countries[country_id]
        var income: int = 0
        var manpower_gain: int = 0
        for province_id_value in owned:
            var province: Dictionary = provinces[int(province_id_value)]
            income += max(1, int(float(province.get("economy", 0)) * float(country.get("tax_rate", 0.25))))
            manpower_gain += max(1, int(float(province.get("population", 0)) / 24.0))
        var maintenance: int = int(ceil(float(_total_army(country_id)) / 12.0))
        country["treasury"] = int(country.get("treasury", 0)) + income - maintenance
        country["manpower"] = int(country.get("manpower", 0)) + manpower_gain
        countries[country_id] = country
        _log("%s: 세입 +%d · 유지비 -%d · 인력 +%d" % [_country_name(country_id), income, maintenance, manpower_gain])

func _on_political_mode() -> void:
    map_mode = "political"
    _refresh_map()

func _on_economy_mode() -> void:
    map_mode = "economy"
    _refresh_map()

func _on_population_mode() -> void:
    map_mode = "population"
    _refresh_map()

func _on_relations_mode() -> void:
    map_mode = "relations"
    _refresh_map()

func _on_country_changed(index: int) -> void:
    player_country_id = String(country_option.get_item_metadata(index))
    selected_province_id = -1
    move_source_id = -1
    commands.clear()
    next_command_id = 1
    _log("플레이 국가를 %s으로 변경했습니다." % _country_name(player_country_id))
    _refresh_all()

func _selected_foreign_country() -> String:
    if selected_province_id == -1:
        return ""
    var owner_id: String = String(provinces[selected_province_id].get("owner", ""))
    return "" if owner_id == player_country_id else owner_id

func _owned_provinces(country_id: String) -> Array:
    var result: Array = []
    for province_id_value in provinces.keys():
        var province_id: int = int(province_id_value)
        if String(provinces[province_id].get("owner", "")) == country_id:
            result.append(province_id)
    return result

func _neighboring_countries(country_id: String) -> Array:
    var result: Array = []
    for province_id_value in _owned_provinces(country_id):
        var province_id: int = int(province_id_value)
        for neighbor_id_value in provinces[province_id].get("neighbors", []):
            var neighbor_id: int = int(neighbor_id_value)
            var owner_id: String = String(provinces[neighbor_id].get("owner", ""))
            if owner_id != country_id and owner_id not in result:
                result.append(owner_id)
    return result

func _total_army(country_id: String) -> int:
    var total: int = 0
    for province_id_value in _owned_provinces(country_id):
        total += int(armies.get(int(province_id_value), 0))
    return total

func _estimated_defense(province_id: int) -> float:
    var province: Dictionary = provinces[province_id]
    var base: float = float(armies.get(province_id, 0)) + float(province.get("population", 0)) / 15.0
    var terrain: String = String(province.get("terrain", "plains"))
    var terrain_bonus: float = 0.0
    if terrain == "hills":
        terrain_bonus = 0.25
    elif terrain == "forest":
        terrain_bonus = 0.20
    elif terrain == "coast":
        terrain_bonus = 0.10
    return base * (1.0 + terrain_bonus) * (1.0 + float(province.get("fort", 0)) * 0.18)

func _pair_key(first: String, second: String) -> String:
    return first + "|" + second if first < second else second + "|" + first

func _is_at_war(first: String, second: String) -> bool:
    return first != second and wars.has(_pair_key(first, second))

func _enemies_of(country_id: String) -> Array:
    var result: Array = []
    for war_value in wars.values():
        var war: Dictionary = war_value
        if String(war.get("attacker", "")) == country_id:
            result.append(String(war.get("defender", "")))
        elif String(war.get("defender", "")) == country_id:
            result.append(String(war.get("attacker", "")))
    return result

func _relation(first: String, second: String) -> int:
    return 100 if first == second else int(relations.get(_pair_key(first, second), 0))

func _relation_label(first: String, second: String) -> String:
    if first == second:
        return "자국"
    if _is_at_war(first, second):
        return "전쟁 중"
    var value: int = _relation(first, second)
    if value >= 20:
        return "친선"
    if value > -20:
        return "중립"
    return "긴장"

func _country_name(country_id: String) -> String:
    var country: Dictionary = countries.get(country_id, {})
    return String(country.get("name", country_id))

func _refresh_all() -> void:
    turn_label.text = "턴 %d · %d년 %s" % [turn, year, SEASONS[season_index]]
    var country: Dictionary = countries[player_country_id]
    country_label.text = "%s · 국고 %d · 안정 %d · 인력 %d · 군대 %d · 영토 %d" % [_country_name(player_country_id), int(country.get("treasury", 0)), int(country.get("stability", 0)), int(country.get("manpower", 0)), _total_army(player_country_id), _owned_provinces(player_country_id).size()]
    _refresh_info()
    _refresh_queue()
    _refresh_map()

func _refresh_info() -> void:
    if selected_province_id == -1:
        info_label.text = "Province를 클릭하면 상세 정보가 표시됩니다."
        return
    var province: Dictionary = provinces[selected_province_id]
    var owner_id: String = String(province.get("owner", ""))
    var owner: Dictionary = countries[owner_id]
    info_label.text = "[ %s ]\n소유국: %s · %s (%d)\n정부: %s · 기술: %d\n인구: %d · 경제: %d · 개발: %d\n지형: %s · 요새: %d\n주둔군: %d · 방어력: %.1f\n인접: %s" % [String(province.get("name", "Province")), _country_name(owner_id), _relation_label(player_country_id, owner_id), _relation(player_country_id, owner_id), String(owner.get("government", "정부")), int(owner.get("technology", 1)), int(province.get("population", 0)), int(province.get("economy", 0)), int(province.get("development", 1)), String(province.get("terrain", "plains")), int(province.get("fort", 0)), int(armies.get(selected_province_id, 0)), _estimated_defense(selected_province_id), str(province.get("neighbors", []))]

func _refresh_queue() -> void:
    if commands.is_empty():
        queue_label.text = "예약 명령 없음"
        return
    var output: String = ""
    for command_value in commands:
        var command: Dictionary = command_value
        var payload: Dictionary = command.get("payload", {})
        var line: String = "#%d %s" % [int(command.get("id", 0)), String(command.get("type", ""))]
        if String(command.get("type", "")) == "recruit":
            line = "#%d 모집 · %s +%d" % [int(command.get("id", 0)), String(provinces[int(payload.get("province_id", -1))].get("name", "Province")), int(payload.get("amount", 0))]
        elif String(command.get("type", "")) == "move":
            line = "#%d 이동 · %s → %s" % [int(command.get("id", 0)), String(provinces[int(payload.get("from_id", -1))].get("name", "Province")), String(provinces[int(payload.get("to_id", -1))].get("name", "Province"))]
        output += ("\n" if output != "" else "") + line
    queue_label.text = output

func _refresh_map() -> void:
    for province_id_value in provinces.keys():
        var province_id: int = int(province_id_value)
        var province: Dictionary = provinces[province_id]
        var fill: Polygon2D = province_fills[province_id]
        var owner_id: String = String(province.get("owner", ""))
        var color: Color
        if map_mode == "economy":
            var economy_value: float = clamp(float(province.get("economy", 0)) / 65.0, 0.15, 1.0)
            color = Color(0.16, 0.28 + economy_value * 0.52, 0.22, 1.0)
        elif map_mode == "population":
            var population_value: float = clamp(float(province.get("population", 0)) / 85.0, 0.15, 1.0)
            color = Color(0.26 + population_value * 0.52, 0.22, 0.18, 1.0)
        elif map_mode == "relations":
            if owner_id == player_country_id:
                color = Color(String(countries[owner_id].get("color", "#777777"))).lightened(0.18)
            elif _is_at_war(player_country_id, owner_id):
                color = Color("#8c3434")
            elif _relation(player_country_id, owner_id) >= 20:
                color = Color("#4f8a78")
            else:
                color = Color("#8b6f53")
        else:
            color = Color(String(countries[owner_id].get("color", "#777777")))
        if province_id == selected_province_id:
            color = color.lightened(0.25)
        fill.color = color
        (province_names[province_id] as Label).text = String(province.get("name", "Province"))
        (province_armies[province_id] as Label).text = str(int(armies.get(province_id, 0)))

func _log(message: String) -> void:
    if log_label.text == "정적 지도와 UI 로드 완료":
        log_label.text = ""
    log_label.append_text(("\n" if log_label.text != "" else "") + "턴 %d | %s" % [turn, message])
    log_label.scroll_to_line(max(0, log_label.get_line_count() - 1))