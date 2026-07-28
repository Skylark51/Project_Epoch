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
var command_queue := CommandQueue.new()
var diplomacy := DiplomacyState.new()
var turn_processor := TurnProcessor.new()

const SEASONS := ["봄", "여름", "가을", "겨울"]

func load_json(path: String) -> Variant:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("데이터 파일을 열 수 없음: %s" % path)
        return null
    var parsed := JSON.parse_string(file.get_as_text())
    if parsed == null:
        push_error("JSON 파싱 실패: %s" % path)
    return parsed

func load_game_data() -> void:
    countries.clear()
    provinces.clear()
    armies.clear()
    command_queue.clear()

    var scenario_data = load_json("res://data/scenarios/001_prototype.json")
    scenario = scenario_data.duplicate(true) if scenario_data else {}
    var start_date: Dictionary = scenario.get("start_date", {})
    date_year = int(start_date.get("year", 1000))
    season_index = int(scenario.get("start_season", 0))
    player_country_id = String(scenario.get("player_country", "AUR"))
    turn = 1

    var country_data = load_json("res://data/countries.json")
    var province_data = load_json("res://data/provinces.json")
    if country_data:
        for source_country in country_data.countries:
            var country: Dictionary = source_country.duplicate(true)
            countries[String(country.id)] = country
    if province_data:
        for source_province in province_data.provinces:
            var province: Dictionary = source_province.duplicate(true)
            var id := int(province.id)
            provinces[id] = province
            armies[id] = int(province.get("army", 0))

    var diplomacy_file := String(scenario.get("diplomacy_file", "res://data/diplomacy.json"))
    diplomacy.load_from_data(load_json(diplomacy_file))

func set_player_country(country_id: String) -> void:
    if countries.has(country_id):
        player_country_id = country_id
        command_queue.clear()

func set_map_mode(mode: String) -> void:
    if mode in ["political", "economy", "population", "relations"]:
        map_mode = mode

func current_date_text() -> String:
    return "%d년 %s" % [date_year, SEASONS[season_index]]

func country_is_alive(country_id: String) -> bool:
    return countries.has(country_id) and not owned_provinces(country_id).is_empty()

func owned_provinces(country_id: String) -> Array[int]:
    var result: Array[int] = []
    for province_id in provinces.keys():
        if String(provinces[province_id].owner) == country_id:
            result.append(int(province_id))
    return result

func border_provinces(country_id: String) -> Array[int]:
    var result: Array[int] = []
    for province_id in owned_provinces(country_id):
        for neighbor_id_value in provinces[province_id].neighbors:
            var neighbor_id := int(neighbor_id_value)
            if String(provinces[neighbor_id].owner) != country_id:
                result.append(province_id)
                break
    return result

func neighboring_countries(country_id: String) -> Array[String]:
    var result: Array[String] = []
    for province_id in owned_provinces(country_id):
        for neighbor_id_value in provinces[province_id].neighbors:
            var neighbor_id := int(neighbor_id_value)
            var owner := String(provinces[neighbor_id].owner)
            if owner != country_id and owner not in result:
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
    var country: Dictionary = countries[country_id]
    var economy_total: int = 0
    var province_count := owned_provinces(country_id).size()
    for province_id in owned_provinces(country_id):
        economy_total += int(provinces[province_id].economy)
    return float(total_army(country_id)) + float(economy_total) * 0.35 + float(province_count * 8) + float(country.get("technology", 1)) * 5.0

func queue_recruit(province_id: int, amount: int = 10) -> String:
    if not provinces.has(province_id):
        return "유효하지 않은 Province입니다."
    var province: Dictionary = provinces[province_id]
    if String(province.owner) != player_country_id:
        return "자국 영토에서만 병력을 모집할 수 있습니다."
    var country: Dictionary = countries[player_country_id]
    var reserved := command_queue.reserved_recruitment(player_country_id)
    var cost := amount * 2
    if int(country.manpower) - int(reserved.manpower) < amount:
        return "예약된 모집을 포함하면 가용 인력이 부족합니다."
    if int(country.treasury) - int(reserved.treasury) < cost:
        return "예약된 지출을 포함하면 국고가 부족합니다."
    var command := command_queue.queue_recruit(player_country_id, province_id, amount)
    return "명령 #%d: %s에서 병력 %d명 모집 예약" % [command.id, province.name, amount]

func queue_move(from_id: int, to_id: int, amount: int = -1) -> String:
    if not provinces.has(from_id) or not provinces.has(to_id):
        return "유효하지 않은 이동 명령입니다."
    var source: Dictionary = provinces[from_id]
    var target: Dictionary = provinces[to_id]
    if String(source.owner) != player_country_id:
        return "자국 Province에서만 명령할 수 있습니다."
    if to_id not in source.neighbors:
        return "인접한 Province로만 이동할 수 있습니다."
    if command_queue.has_move_from(player_country_id, from_id):
        return "이 Province에는 이미 이동 명령이 예약되어 있습니다."
    var available := int(armies.get(from_id, 0))
    if available <= 1:
        return "이동 가능한 병력이 부족합니다. 최소 1명은 주둔해야 합니다."
    if amount < 0:
        amount = available - 1
    amount = clamp(amount, 1, available - 1)
    var target_owner := String(target.owner)
    if target_owner != player_country_id:
        var war_queued := command_queue.has_diplomacy_command("declare_war", player_country_id, target_owner)
        if not diplomacy.at_war(player_country_id, target_owner) and not war_queued:
            return "%s과(와) 전쟁 중이 아닙니다. 먼저 전쟁을 선포하십시오." % countries[target_owner].name
    var command := command_queue.queue_move(player_country_id, from_id, to_id, amount)
    return "명령 #%d: %s → %s 병력 %d명 이동 예약" % [command.id, source.name, target.name, amount]

func queue_declare_war(target_country_id: String) -> String:
    if target_country_id == player_country_id:
        return "자국에는 전쟁을 선포할 수 없습니다."
    if not country_is_alive(target_country_id):
        return "존재하지 않는 국가입니다."
    if diplomacy.at_war(player_country_id, target_country_id):
        return "이미 전쟁 중입니다."
    if command_queue.has_diplomacy_command("declare_war", player_country_id, target_country_id):
        return "이미 전쟁 선포 명령이 예약되어 있습니다."
    var command := command_queue.queue_declare_war(player_country_id, target_country_id)
    return "명령 #%d: %s에 대한 전쟁 선포 예약" % [command.id, countries[target_country_id].name]

func queue_offer_peace(target_country_id: String) -> String:
    if not diplomacy.at_war(player_country_id, target_country_id):
        return "현재 전쟁 중인 국가가 아닙니다."
    if command_queue.has_diplomacy_command("offer_peace", player_country_id, target_country_id):
        return "이미 평화 제안이 예약되어 있습니다."
    var command := command_queue.queue_offer_peace(player_country_id, target_country_id)
    return "명령 #%d: %s에 평화 제안 예약" % [command.id, countries[target_country_id].name]

func clear_player_commands() -> String:
    command_queue.clear()
    return "예약된 플레이어 명령을 모두 취소했습니다."

func execute_recruit(country_id: String, province_id: int, amount: int) -> String:
    if not countries.has(country_id) or not provinces.has(province_id):
        return "모집 명령 무효"
    var province: Dictionary = provinces[province_id]
    if String(province.owner) != country_id:
        return "%s: 소유권이 변경되어 모집 명령이 취소되었습니다." % province.name
    var country: Dictionary = countries[country_id]
    var cost := amount * 2
    if int(country.manpower) < amount or int(country.treasury) < cost:
        return "%s: 자원이 부족하여 모집에 실패했습니다." % country.name
    country.manpower = int(country.manpower) - amount
    country.treasury = int(country.treasury) - cost
    countries[country_id] = country
    armies[province_id] = int(armies.get(province_id, 0)) + amount
    return "%s: %s에서 병력 %d명 모집" % [country.name, province.name, amount]

func execute_move(country_id: String, from_id: int, to_id: int, amount: int) -> String:
    if not countries.has(country_id) or not provinces.has(from_id) or not provinces.has(to_id):
        return "이동 명령 무효"
    var source: Dictionary = provinces[from_id]
    var target: Dictionary = provinces[to_id]
    if String(source.owner) != country_id:
        return "%s: 출발지 소유권이 변경되어 명령이 취소되었습니다." % source.name
    if to_id not in source.neighbors:
        return "%s: 인접하지 않아 이동할 수 없습니다." % source.name
    var source_army := int(armies.get(from_id, 0))
    var moving := min(amount, max(0, source_army - 1))
    if moving <= 0:
        return "%s: 이동 가능한 병력이 없습니다." % source.name

    var target_owner := String(target.owner)
    if target_owner == country_id:
        armies[from_id] = source_army - moving
        armies[to_id] = int(armies.get(to_id, 0)) + moving
        return "%s: %s에서 %s로 병력 %d명 이동" % [countries[country_id].name, source.name, target.name, moving]

    if not diplomacy.at_war(country_id, target_owner):
        return "%s: %s과(와) 전쟁 중이 아니어서 공격이 취소되었습니다." % [countries[country_id].name, countries[target_owner].name]

    armies[from_id] = source_army - moving
    var attacker_tech := float(countries[country_id].get("technology", 1))
    var attack_power := float(moving) * (1.0 + attacker_tech * 0.06) * (1.0 + float(source.get("development", 1)) * 0.02)
    var defense_power := estimated_defense(to_id)
    var defender_army := int(armies.get(to_id, 0))

    if attack_power > defense_power:
        var survival_ratio := clamp(1.0 - defense_power / max(attack_power, 1.0) * 0.55, 0.12, 0.9)
        var survivors := max(1, int(round(float(moving) * survival_ratio)))
        armies[to_id] = survivors
        target.owner = country_id
        target.population = max(8, int(target.population) - 2)
        provinces[to_id] = target
        _change_stability(country_id, -1)
        _change_stability(target_owner, -3)
        diplomacy.record_battle(country_id, target_owner, 12)
        return "%s: %s 점령 성공 · 생존 병력 %d명" % [countries[country_id].name, target.name, survivors]

    var defense_ratio := clamp(1.0 - attack_power / max(defense_power, 1.0) * 0.45, 0.15, 0.95)
    armies[to_id] = max(1, int(round(float(max(defender_army, 1)) * defense_ratio)))
    _change_stability(country_id, -2)
    diplomacy.record_battle(target_owner, country_id, 6)
    return "%s: %s 공격 실패 · 공격군 %d명 소멸" % [countries[country_id].name, target.name, moving]

func estimated_defense(province_id: int) -> float:
    if not provinces.has(province_id):
        return 0.0
    var province: Dictionary = provinces[province_id]
    var base := float(armies.get(province_id, 0)) + float(province.population) / 15.0
    var fort_multiplier := 1.0 + float(province.get("fort", 0)) * 0.18
    return base * (1.0 + _terrain_defense_modifier(String(province.terrain))) * fort_multiplier

func apply_economy_phase() -> Array[String]:
    var logs: Array[String] = ["[경제 단계]"]
    for country_id_value in countries.keys():
        var country_id := String(country_id_value)
        if not country_is_alive(country_id):
            continue
        var country: Dictionary = countries[country_id]
        var tax_rate := float(country.get("tax_rate", 0.25))
        var stability_modifier := 0.55 + float(country.stability) / 200.0
        var gross_income: int = 0
        var manpower_gain: int = 0
        for province_id in owned_provinces(country_id):
            var province: Dictionary = provinces[province_id]
            gross_income += max(1, int(round(float(province.economy) * tax_rate * stability_modifier)))
            manpower_gain += max(1, int(round(float(province.population) / 24.0)))
        var maintenance := int(ceil(float(total_army(country_id)) / 12.0))
        var net_income := gross_income - maintenance
        country.treasury = int(country.treasury) + net_income
        country.manpower = int(country.manpower) + manpower_gain
        if int(country.treasury) < 0:
            country.stability = max(0, int(country.stability) - 3)
        countries[country_id] = country
        logs.append("%s: 세입 +%d · 유지비 -%d · 인력 +%d" % [country.name, gross_income, maintenance, manpower_gain])
    return logs

func apply_growth_phase() -> Array[String]:
    var logs: Array[String] = ["[성장 단계]"]
    if turn % 4 != 0:
        logs.append("연간 성장 계산 없음")
        return logs
    for province_id in provinces.keys():
        var province: Dictionary = provinces[province_id]
        var owner: Dictionary = countries[String(province.owner)]
        var population_growth := 1 if int(owner.stability) >= 40 else 0
        province.population = int(province.population) + population_growth
        if int(province.get("development", 1)) >= 2 and int(owner.stability) >= 55:
            province.economy = int(province.economy) + 1
        provinces[province_id] = province
    logs.append("모든 Province의 연간 인구·경제 성장을 계산했습니다.")
    return logs

func resolve_peace_offer(proposer: String, target: String) -> String:
    if not diplomacy.at_war(proposer, target):
        return "평화 제안 무효"
    var score := diplomacy.war_score(proposer, target)
    var proposer_stability := int(countries[proposer].stability)
    var target_stability := int(countries[target].stability)
    if abs(score) <= 30 or proposer_stability < 35 or target_stability < 35:
        return diplomacy.make_peace(proposer, target)
    diplomacy.adjust_relation(proposer, target, -2)
    return "상대국이 평화 제안을 거부했습니다."

func advance_turn() -> Array[String]:
    return turn_processor.process_turn(self)

func advance_calendar() -> void:
    turn += 1
    season_index += 1
    if season_index >= SEASONS.size():
        season_index = 0
        date_year += 1

func _terrain_defense_modifier(terrain: String) -> float:
    match terrain:
        "hills": return 0.25
        "forest": return 0.20
        "coast": return 0.10
        _: return 0.0

func _change_stability(country_id: String, amount: int) -> void:
    if not countries.has(country_id):
        return
    var country: Dictionary = countries[country_id]
    country.stability = clamp(int(country.stability) + amount, 0, 100)
    countries[country_id] = country
