class_name GameState
extends RefCounted

var turn: int = 1
var date_year: int = 1000
var season_index: int = 0
var selected_province_id: int = -1
var player_country_id: String = "AUR"
var map_mode: String = "political"
var countries: Dictionary = {}
var provinces: Dictionary = {}
var armies: Dictionary = {}

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

func set_player_country(country_id: String) -> void:
    if countries.has(country_id):
        player_country_id = country_id

func set_map_mode(mode: String) -> void:
    if mode in ["political", "economy", "population"]:
        map_mode = mode

func current_date_text() -> String:
    return "%d년 %s" % [date_year, SEASONS[season_index]]

func owned_provinces(country_id: String) -> Array[int]:
    var result: Array[int] = []
    for province_id in provinces.keys():
        if String(provinces[province_id].owner) == country_id:
            result.append(int(province_id))
    return result

func recruit_army(province_id: int, amount: int = 10) -> String:
    if not provinces.has(province_id):
        return "유효하지 않은 Province입니다."
    var province: Dictionary = provinces[province_id]
    if String(province.owner) != player_country_id:
        return "자국 영토에서만 병력을 모집할 수 있습니다."
    var country: Dictionary = countries[player_country_id]
    var cost := amount * 2
    if int(country.manpower) < amount:
        return "가용 인력이 부족합니다."
    if int(country.treasury) < cost:
        return "국고가 부족합니다. 필요 금액: %d" % cost
    country.manpower = int(country.manpower) - amount
    country.treasury = int(country.treasury) - cost
    countries[player_country_id] = country
    armies[province_id] = int(armies.get(province_id, 0)) + amount
    return "%s에서 병력 %d명을 모집했습니다. 비용 -%d" % [province.name, amount, cost]

func move_or_attack(from_id: int, to_id: int) -> String:
    if not provinces.has(from_id) or not provinces.has(to_id):
        return "유효하지 않은 이동 명령입니다."
    var source: Dictionary = provinces[from_id]
    var target: Dictionary = provinces[to_id]
    if String(source.owner) != player_country_id:
        return "자국 Province에서만 명령할 수 있습니다."
    if to_id not in source.neighbors:
        return "인접한 Province로만 이동할 수 있습니다."
    var attackers := int(armies.get(from_id, 0))
    if attackers <= 0:
        return "이동시킬 군대가 없습니다."

    if String(target.owner) == player_country_id:
        armies[to_id] = int(armies.get(to_id, 0)) + attackers
        armies[from_id] = 0
        return "%s의 병력 %d명이 %s로 이동했습니다." % [source.name, attackers, target.name]

    var defender_army := int(armies.get(to_id, 0))
    var terrain_bonus := _terrain_defense_bonus(String(target.terrain))
    var fort_bonus := int(target.get("fort", 0)) * 3
    var defenders := defender_army + int(int(target.population) / 12.0) + terrain_bonus + fort_bonus
    var attack_power := attackers + int(int(source.get("development", 1)) / 2.0)
    var old_owner := String(target.owner)

    if attack_power > defenders:
        var survivors := max(1, attack_power - defenders)
        armies[from_id] = 0
        armies[to_id] = survivors
        target.owner = player_country_id
        target.population = max(8, int(target.population) - 2)
        provinces[to_id] = target
        _change_stability(player_country_id, -1)
        _change_stability(old_owner, -3)
        return "%s 점령 성공. 생존 병력 %d명" % [target.name, survivors]

    var losses := max(1, int(attackers * 0.65))
    armies[from_id] = max(0, attackers - losses)
    armies[to_id] = max(0, defender_army - int(attackers * 0.25))
    _change_stability(player_country_id, -2)
    return "%s 공격 실패. 공격군 손실 %d명" % [target.name, losses]

func advance_turn() -> Array[String]:
    turn += 1
    season_index += 1
    if season_index >= SEASONS.size():
        season_index = 0
        date_year += 1

    var log: Array[String] = []
    for country_id in countries.keys():
        var country: Dictionary = countries[country_id]
        var income := 0
        var manpower_gain := 0
        for province_id in provinces.keys():
            var province: Dictionary = provinces[province_id]
            if String(province.owner) == String(country_id):
                income += max(1, int(province.economy / 5.0))
                manpower_gain += max(1, int(province.population / 20.0))
                if turn % 4 == 0:
                    province.population = int(province.population) + 1
                    if int(province.get("development", 1)) >= 2:
                        province.economy = int(province.economy) + 1
                    provinces[province_id] = province
        country.treasury = int(country.treasury) + income
        country.manpower = int(country.manpower) + manpower_gain
        countries[country_id] = country
        log.append("%s: 세입 +%d, 인력 +%d" % [country.name, income, manpower_gain])

    log.append_array(_run_basic_ai())
    return log

func _run_basic_ai() -> Array[String]:
    var logs: Array[String] = []
    for country_id in countries.keys():
        if String(country_id) == player_country_id:
            continue
        var owned := owned_provinces(String(country_id))
        if owned.is_empty():
            continue
        var country: Dictionary = countries[country_id]
        var recruit_at := owned[(turn + String(country_id).length()) % owned.size()]
        if int(country.treasury) >= 12 and int(country.manpower) >= 5:
            country.treasury = int(country.treasury) - 10
            country.manpower = int(country.manpower) - 5
            countries[country_id] = country
            armies[recruit_at] = int(armies.get(recruit_at, 0)) + 5
            logs.append("%s이(가) %s에서 병력을 증원했습니다." % [country.name, provinces[recruit_at].name])
    return logs

func _terrain_defense_bonus(terrain: String) -> int:
    match terrain:
        "hills": return 5
        "forest": return 4
        "coast": return 2
        _: return 0

func _change_stability(country_id: String, amount: int) -> void:
    if not countries.has(country_id):
        return
    var country: Dictionary = countries[country_id]
    country.stability = clamp(int(country.stability) + amount, 0, 100)
    countries[country_id] = country
