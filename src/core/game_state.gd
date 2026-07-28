class_name GameState
extends RefCounted

var turn: int = 1
var date_year: int = 1000
var selected_province_id: int = -1
var countries: Dictionary = {}
var provinces: Dictionary = {}

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
    var country_data = load_json("res://data/countries.json")
    var province_data = load_json("res://data/provinces.json")
    if country_data:
        for country in country_data.countries:
            countries[country.id] = country
    if province_data:
        for province in province_data.provinces:
            provinces[int(province.id)] = province

func advance_turn() -> Array[String]:
    turn += 1
    date_year += 1
    var log: Array[String] = []
    for country_id in countries.keys():
        var country: Dictionary = countries[country_id]
        var income := 0
        for province_id in provinces.keys():
            var province: Dictionary = provinces[province_id]
            if province.owner == country_id:
                income += int(province.economy / 5.0)
        country.treasury += income
        countries[country_id] = country
        log.append("%s: 세입 +%d" % [country.name, income])
    return log
