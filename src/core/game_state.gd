class_name GameState
extends RefCounted

var turn: int = 1
var date_year: int = 1000
var season_index: int = 0
var selected_province_id: int = -1
var player_country_id: String = "AUR"
var map_mode: String = "political"
var scenario: Dictionary = {}
var countries: Dictionary = {}
var provinces: Dictionary = {}
var armies: Dictionary = {}
var command_queue
var diplomacy
var turn_processor

const SEASONS := ["봄", "여름", "가을", "겨울"]

func _init() -> void:
    var command_queue_script = load("res://src/core/command_queue.gd")
    var diplomacy_script = load("res://src/core/diplomacy_state.gd")
    var turn_processor_script = load("res://src/core/turn_processor.gd")
    if command_queue_script != null:
        command_queue = command_queue_script.new()
    if diplomacy_script != null:
        diplomacy = diplomacy_script.new()
    if turn_processor_script != null:
        turn_processor = turn_processor_script.new()

func load_json(path: String):
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("데이터 파일을 열 수 없음: %s" % path)
        return null
    var parsed = JSON.parse_string(file.get_as_text())
    if parsed == null:
        push_error("JSON 파싱 실패: %s" % path)
    return parsed

func load_game_data() -> void:
    countries.clear()
    provinces.clear()
    armies.clear()
    if command_queue != null:
        command_queue.clear()

    var scenario_data = load_json("res://data/scenarios/001_prototype.json")
    if scenario_data is Dictionary:
        scenario = scenario_data.duplicate(true)
    else:
        scenario = {}

    var start_date: Dictionary = scenario.get("start_date", {})
    date_year = int(start_date.get("year", 1000))
    season_index = int(scenario.get("start_season", 0))
    player_country_id = String(scenario.get("player_country", "AUR"))
    turn = 1

    var country_data = load_json("res://data/countries.json")
    if country_data is Dictionary:
        for source_country in country_data.get("countries", []):
            var country: Dictionary = source_country.duplicate(true)
            countries[String(country.get("id", ""))] = country

    var province_data = load_json("res://data/provinces.json")
    if province_data is Dictionary:
        for source_province in province_data.get("provinces", []):
            var province: Dictionary = source_province.duplicate(true)
            var province_id := int(province.get("id", -1))
            if province_id < 0:
                continue
            provinces[province_id] = province
            armies[province_id] = int(province.get("army", 0))

    if diplomacy != null:
        var diplomacy_file := String(scenario.get("diplomacy_file", "res://data/diplomacy.json"))
        diplomacy.load_from_data(load_json(diplomacy_file))

func set_player_country(country_id: String) -> void:
    if countries.has(country_id):
        player_country_id = country_id
        if command_queue != null:
            command_queue.clear()

func set_map_mode(mode: String) -> void:
    if mode in ["political", "economy", "population", "relations"]:
        map_mode = mode

func current_date_text() -> String:
    return "%d년 %s" % [date_year, SEASONS[clamp(season_index, 0, SEASONS.size() - 1)]]

func country_is_alive(country_id: String) -> bool:
    return countries.has(country_id) and not owned_provinces(country_id).is_empty()

func owned_provinces(country_id: String) -> Array[int]:
    var result: Array[int] = []
    for province_id_value in provinces.keys():
        var province_id := int(province_id_value)
        if String(provinces[province_id].get("owner", "")) == country_id:
            result.append(province_id)
    return result

func border_provinces(country_id: String) -> Array[int]:
    var result: Array[int] = []
    for province_id in owned_provinces(country_id):
        for neighbor_value in provinces[province_id].get("neighbors", []):
            var neighbor_id := int(neighbor_value)
            if provinces.has(neighbor_id) and String(provinces[neighbor_id].get("owner", "")) != country_id:
                result.append(province_id)
                break
    return result

func neighboring_countries(country_id: String) -> Array[String]:
    var result: Array[String] = []
    for province_id in owned_provinces(country_id):
        for neighbor_value in provinces[province_id].get("neighbors", []):
            var neighbor_id := int(neighbor_value)
            if not provinces.has(neighbor_id):
                continue
            var owner := String(provinces[neighbor_id].get("owner", ""))
            if owner != country_id and owner != "" and owner not in result:
                result.append(owner)
    return result

func total_army(country_id: String) -> int:
    var total: int = 0
    for province_id in owned_provinces(country_id):
        total += int(armies.get(province_id, 0))
    return total

func country_strength(country_id: String) -> float:
    if not countries.has(country_id):
        return 0.0
    var economy_total: int = 0
    var owned := owned_provinces(country_id)
    for province_id in owned:
        economy_total += int(provinces[province_id].get("economy", 0))
    var technology := float(countries[country_id].get("technology", 1))
    return float(total_army(country_id)) + float(economy_total) * 0.35 + float(owned.size() * 8) + technology * 5.0

func queue_recruit(province_id: int, amount: int = 10) -> String:
    if command_queue == null:
        return "명령 큐를 불러오지 못했습니다."
    if not provinces.has(province_id):
        return "유효하지 않은 Province입니다."
    var province: Dictionary = provinces[province_id]
    if String(province.get("owner", "")) != player_country_id:
        return "자국 영토에서만 병력을 모집할 수 있습니다."
    var country: Dictionary = countries[player_country_id]
    var reserved: Dictionary = command_queue.reserved_recruitment(player_country_id)
    var cost := amount * 2
    if int(country.get("manpower", 0)) - int(reserved.get("manpower", 0)) < amount:
        return "예약된 모집을 포함하면 가용 인력이 부족합니다."
    if int(country.get("treasury", 0)) - int(reserved.get("treasury", 0)) < cost:
        return "예약된 지출을 포함하면 국고가 부족합니다."
    var command: Dictionary = command_queue.queue_recruit(player_country_id, province_id, amount)
    return "명령 #%d: %s에서 병력 %d명 모집 예약" % [int(command.get("id", 0)), String(province.get("name", "Province")), amount]

func queue_move(from_id: int, to_id: int, amount: int = -1) -> String:
    if command_queue == null:
        return "명령 큐를 불러오지 못했습니다."
    if not provinces.has(from_id) or not provinces.has(to_id):
        return "유효하지 않은 이동 명령입니다."
    var source: Dictionary = provinces[from_id]
    var target: Dictionary = provinces[to_id]
    if String(source.get("owner", "")) != player_country_id:
        return "자국 Province에서만 명령할 수 있습니다."
    if to_id not in source.get("neighbors", []):
        return "인접한 Province로만 이동할 수 있습니다."
    if command_queue.has_move_from(player_country_id, from_id):
        return "이 Province에는 이미 이동 명령이 예약되어 있습니다."
    var available := int(armies.get(from_id, 0))
    if available <= 1:
        return "이동 가능한 병력이 부족합니다."
    if amount < 0:
        amount = available - 1
    amount = clamp(amount, 1, available - 1)
    var target_owner := String(target.get("owner", ""))
    if target_owner != player_country_id:
        var war_queued := command_queue.has_diplomacy_command("declare_war", player_country_id, target_owner)
        if diplomacy == null or (not diplomacy.at_war(player_country_id, target_owner) and not war_queued):
            return "%s과(와) 전쟁 중이 아닙니다." % String(countries[target_owner].get("name", target_owner))
    var command: Dictionary = command_queue.queue_move(player_country_id, from_id, to_id, amount)
    return "명령 #%d: %s → %s 병력 %d명 이동 예약" % [int(command.get("id", 0)), String(source.get("name", "")), String(target.get("name", "")), amount]

func queue_declare_war(target_country_id: String) -> String:
    if command_queue == null or diplomacy == null:
        return "외교 모듈을 불러오지 못했습니다."
    if target_country_id == player_country_id or not country_is_alive(target_country_id):
        return "유효하지 않은 전쟁 대상입니다."
    if diplomacy.at_war(player_country_id, target_country_id):
        return "이미 전쟁 중입니다."
    if command_queue.has_diplomacy_command("declare_war", player_country_id, target_country_id):
        return "이미 전쟁 선포 명령이 예약되어 있습니다."
    var command: Dictionary = command_queue.queue_declare_war(player_country_id, target_country_id)
    return "명령 #%d: %s에 대한 전쟁 선포 예약" % [int(command.get("id", 0)), String(countries[target_country_id].get("name", target_country_id))]

func queue_offer_peace(target_country_id: String) -> String:
    if command_queue == null or diplomacy == null:
        return "외교 모듈을 불러오지 못했습니다."
    if not diplomacy.at_war(player_country_id, target_country_id):
        return "현재 전쟁 중인 국가가 아닙니다."
    var command: Dictionary = command_queue.queue_offer_peace(player_country_id, target_country_id)
    return "명령 #%d: %s에 평화 제안 예약" % [int(command.get("id", 0)), String(countries[target_country_id].get("name", target_country_id))]

func clear_player_commands() -> String:
    if command_queue != null:
        command_queue.clear()
    return "예약된 플레이어 명령을 모두 취소했습니다."

func execute_recruit(country_id: String, province_id: int, amount: int) -> String:
    if not countries.has(country_id) or not provinces.has(province_id):
        return "모집 명령 무효"
    var province: Dictionary = provinces[province_id]
    if String(province.get("owner", "")) != country_id:
        return "%s: 소유권 변경으로 모집 취소" % String(province.get("name", "Province"))
    var country: Dictionary = countries[country_id]
    var cost := amount * 2
    if int(country.get("manpower", 0)) < amount or int(country.get("treasury", 0)) < cost:
        return "%s: 자원 부족으로 모집 실패" % String(country.get("name", country_id))
    country["manpower"] = int(country.get("manpower", 0)) - amount
    country["treasury"] = int(country.get("treasury", 0)) - cost
    countries[country_id] = country
    armies[province_id] = int(armies.get(province_id, 0)) + amount
    return "%s: %s에서 병력 %d명 모집" % [String(country.get("name", country_id)), String(province.get("name", "Province")), amount]

func execute_move(country_id: String, from_id: int, to_id: int, amount: int) -> String:
    if not countries.has(country_id) or not provinces.has(from_id) or not provinces.has(to_id):
        return "이동 명령 무효"
    var source: Dictionary = provinces[from_id]
    var target: Dictionary = provinces[to_id]
    if String(source.get("owner", "")) != country_id:
        return "출발지 소유권 변경으로 명령 취소"
    if to_id not in source.get("neighbors", []):
        return "인접하지 않아 이동 취소"
    var source_army := int(armies.get(from_id, 0))
    var moving := min(amount, max(0, source_army - 1))
    if moving <= 0:
        return "이동 가능한 병력이 없습니다."
    var target_owner := String(target.get("owner", ""))
    if target_owner == country_id:
        armies[from_id] = source_army - moving
        armies[to_id] = int(armies.get(to_id, 0)) + moving
        return "%s → %s 병력 %d명 이동" % [String(source.get("name", "")), String(target.get("name", "")), moving]
    if diplomacy == null or not diplomacy.at_war(country_id, target_owner):
        return "전쟁 상태가 아니어서 공격 취소"

    armies[from_id] = source_army - moving
    var technology := float(countries[country_id].get("technology", 1))
    var attack_power := float(moving) * (1.0 + technology * 0.06)
    var defense_power := estimated_defense(to_id)
    var defender_army := int(armies.get(to_id, 0))
    if attack_power > defense_power:
        var survivors := max(1, int(round(float(moving) * 0.55)))
        armies[to_id] = survivors
        target["owner"] = country_id
        target["population"] = max(8, int(target.get("population", 0)) - 2)
        provinces[to_id] = target
        _change_stability(country_id, -1)
        _change_stability(target_owner, -3)
        diplomacy.record_battle(country_id, target_owner, 12)
        return "%s 점령 성공 · 생존 병력 %d" % [String(target.get("name", "Province")), survivors]
    armies[to_id] = max(1, defender_army - max(1, int(moving * 0.3)))
    _change_stability(country_id, -2)
    diplomacy.record_battle(target_owner, country_id, 6)
    return "%s 공격 실패 · 공격군 %d 소멸" % [String(target.get("name", "Province")), moving]

func estimated_defense(province_id: int) -> float:
    if not provinces.has(province_id):
        return 0.0
    var province: Dictionary = provinces[province_id]
    var base_value := float(armies.get(province_id, 0)) + float(province.get("population", 0)) / 15.0
    var fort_multiplier := 1.0 + float(province.get("fort", 0)) * 0.18
    return base_value * (1.0 + _terrain_defense_modifier(String(province.get("terrain", "plains")))) * fort_multiplier

func apply_economy_phase() -> Array[String]:
    var logs: Array[String] = ["[경제 단계]"]
    for country_id_value in countries.keys():
        var country_id := String(country_id_value)
        if not country_is_alive(country_id):
            continue
        var country: Dictionary = countries[country_id]
        var gross_income: int = 0
        var manpower_gain: int = 0
        var tax_rate := float(country.get("tax_rate", 0.25))
        var stability_modifier := 0.55 + float(country.get("stability", 50)) / 200.0
        for province_id in owned_provinces(country_id):
            var province: Dictionary = provinces[province_id]
            gross_income += max(1, int(round(float(province.get("economy", 0)) * tax_rate * stability_modifier)))
            manpower_gain += max(1, int(round(float(province.get("population", 0)) / 24.0)))
        var maintenance := int(ceil(float(total_army(country_id)) / 12.0))
        country["treasury"] = int(country.get("treasury", 0)) + gross_income - maintenance
        country["manpower"] = int(country.get("manpower", 0)) + manpower_gain
        countries[country_id] = country
        logs.append("%s: 세입 +%d · 유지비 -%d · 인력 +%d" % [String(country.get("name", country_id)), gross_income, maintenance, manpower_gain])
    return logs

func apply_growth_phase() -> Array[String]:
    var logs: Array[String] = ["[성장 단계]"]
    if turn % 4 != 0:
        logs.append("연간 성장 계산 없음")
        return logs
    for province_id_value in provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = provinces[province_id]
        var owner_id := String(province.get("owner", ""))
        if not countries.has(owner_id):
            continue
        var owner: Dictionary = countries[owner_id]
        if int(owner.get("stability", 0)) >= 40:
            province["population"] = int(province.get("population", 0)) + 1
        if int(province.get("development", 1)) >= 2 and int(owner.get("stability", 0)) >= 55:
            province["economy"] = int(province.get("economy", 0)) + 1
        provinces[province_id] = province
    logs.append("연간 인구·경제 성장 계산 완료")
    return logs

func resolve_peace_offer(proposer: String, target: String) -> String:
    if diplomacy == null or not diplomacy.at_war(proposer, target):
        return "평화 제안 무효"
    var score := diplomacy.war_score(proposer, target)
    if abs(score) <= 30:
        return diplomacy.make_peace(proposer, target)
    return "상대국이 평화 제안을 거부했습니다."

func advance_turn() -> Array[String]:
    if turn_processor == null:
        return ["턴 처리 모듈을 불러오지 못했습니다."]
    return turn_processor.process_turn(self)

func advance_calendar() -> void:
    turn += 1
    season_index += 1
    if season_index >= SEASONS.size():
        season_index = 0
        date_year += 1

func _terrain_defense_modifier(terrain: String) -> float:
    match terrain:
        "hills":
            return 0.25
        "forest":
            return 0.20
        "coast":
            return 0.10
        _:
            return 0.0

func _change_stability(country_id: String, amount: int) -> void:
    if not countries.has(country_id):
        return
    var country: Dictionary = countries[country_id]
    country["stability"] = clamp(int(country.get("stability", 0)) + amount, 0, 100)
    countries[country_id] = country
