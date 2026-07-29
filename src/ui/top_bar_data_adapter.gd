class_name TopBarDataAdapter
extends RefCounted

const CATALOG := {
    "date": {"label": "연도·계절", "icon": "◷", "required": true},
    "treasury": {"label": "국고", "icon": "¤", "required": true},
    "food": {"label": "핵심 자원", "icon": "◆", "required": true},
    "war_status": {"label": "전쟁", "icon": "⚔", "required": true},
    "total_population": {"label": "총인구", "icon": "♟"},
    "average_happiness": {"label": "평균 행복", "icon": "☀"},
    "average_stability": {"label": "평균 안정", "icon": "◈"},
    "administrative_power": {"label": "행정력", "icon": "▣"},
    "legitimacy": {"label": "정통성", "icon": "♛"},
    "military_power": {"label": "군사력", "icon": "⚑"},
    "influence_growth": {"label": "영향권 성장", "icon": "◎"},
    "rebellion_risk_cities": {"label": "반란 위험 도시", "icon": "!"},
    "occupied_provinces": {"label": "점령지", "icon": "▦"},
    "vassal_loyalty": {"label": "종속국 충성", "icon": "◇"},
    "research_progress": {"label": "연구", "icon": "⌁"}
}


func build(snapshot: Dictionary, country_id: String, urgent_count := 0) -> Dictionary:
    var country: Dictionary = snapshot.get("countries", {}).get(country_id, {})
    var provinces: Dictionary = snapshot.get("provinces", {})
    var result := {}
    for id in CATALOG:
        result[id] = _unavailable(id)

    var date: Dictionary = snapshot.get("date", {})
    if date.has("year"):
        var month := int(date.get("month", 1))
        var season: String = ["봄", "여름", "가을", "겨울"][clampi(floori(float(month - 1) / 3.0), 0, 3)]
        result.date = _entry("date", "%d년 %s" % [int(date.year), season])
    if country.has("treasury"):
        result.treasury = _entry("treasury", _number(int(country.treasury)), float(country.treasury) < 0.0)

    var food_total := 0
    var has_food := false
    var population_total := 0
    var owned_count := 0
    var occupied_count := 0
    var military_total := 0
    var armies: Dictionary = snapshot.get("armies", {})
    for province_value in provinces.values():
        if province_value is not Dictionary:
            continue
        var province: Dictionary = province_value
        var owner := String(province.get("owner", province.get("owner_id", "")))
        if owner != country_id:
            continue
        owned_count += 1
        population_total += int(province.get("population", 0))
        var resources: Dictionary = province.get("resources", {})
        if resources.has("food"):
            has_food = true
            food_total += int(resources.food)
        var controller := String(province.get("controller", province.get("controller_id", owner)))
        if controller != owner:
            occupied_count += 1
        var province_id = province.get("id", province.get("province_id", -1))
        military_total += int(armies.get(province_id, armies.get(str(province_id), 0)))
    if has_food:
        result.food = _entry("food", _number(food_total), food_total <= 0)
    if owned_count > 0:
        result.total_population = _entry("total_population", _number(population_total))
        result.occupied_provinces = _entry("occupied_provinces", str(occupied_count), occupied_count > 0)
        result.military_power = _entry("military_power", _number(military_total + int(country.get("manpower", 0))))

    var wars: Array = snapshot.get("wars", [])
    var player_wars := 0
    for war_value in wars:
        if war_value is Dictionary and country_id in [String(war_value.get("attacker", "")), String(war_value.get("defender", ""))]:
            player_wars += 1
    result.war_status = _entry("war_status", "평시" if player_wars == 0 else "%d개 전쟁" % player_wars, player_wars > 0)

    _copy_number(country, result, "average_happiness", ["average_happiness", "happiness"], true)
    _copy_number(country, result, "average_stability", ["average_stability", "stability"], true)
    _copy_number(country, result, "administrative_power", ["administrative_power", "administration_capacity"])
    _copy_number(country, result, "legitimacy", ["legitimacy", "legitimacy_hidden"])
    _copy_number(country, result, "influence_growth", ["influence_growth"])
    _copy_number(country, result, "rebellion_risk_cities", ["rebellion_risk_city_count"], false, true)
    _copy_number(country, result, "vassal_loyalty", ["vassal_loyalty"], true)
    _copy_number(country, result, "research_progress", ["research_progress"])
    result.urgent_count = urgent_count
    return result


func _copy_number(source: Dictionary, target: Dictionary, id: String, keys: Array, low_is_risk := false, high_is_risk := false) -> void:
    for key in keys:
        if source.has(key):
            var value := float(source[key])
            var shown := str(roundi(value))
            if id in ["average_happiness", "average_stability", "legitimacy", "vassal_loyalty", "research_progress"]:
                shown += "%"
            target[id] = _entry(id, shown, (low_is_risk and value < 35.0) or (high_is_risk and value > 0.0))
            return


func _unavailable(id: String) -> Dictionary:
    var meta: Dictionary = CATALOG[id]
    return {"id": id, "label": meta.label, "icon": meta.icon, "value": "—", "available": false, "risk": false}


func _entry(id: String, value: String, risk := false) -> Dictionary:
    var meta: Dictionary = CATALOG[id]
    return {"id": id, "label": meta.label, "icon": meta.icon, "value": value, "available": true, "risk": risk}


func _number(value: int) -> String:
    var text := str(abs(value))
    var output := ""
    while text.length() > 3:
        output = "," + text.substr(text.length() - 3) + output
        text = text.substr(0, text.length() - 3)
    return ("-" if value < 0 else "") + text + output
