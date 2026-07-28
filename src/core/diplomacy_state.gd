class_name DiplomacyState
extends RefCounted

var relations: Dictionary = {}
var wars: Dictionary = {}

func load_from_data(data: Variant) -> void:
    relations.clear()
    wars.clear()
    if data == null:
        return
    for item in data.get("relations", []):
        var first := String(item.get("a", ""))
        var second := String(item.get("b", ""))
        if first == "" or second == "" or first == second:
            continue
        relations[_pair_key(first, second)] = clamp(int(item.get("value", 0)), -100, 100)
    for item in data.get("wars", []):
        var attacker := String(item.get("attacker", ""))
        var defender := String(item.get("defender", ""))
        if attacker == "" or defender == "" or attacker == defender:
            continue
        wars[_pair_key(attacker, defender)] = {
            "attacker": attacker,
            "defender": defender,
            "start_turn": int(item.get("start_turn", 1)),
            "war_score": int(item.get("war_score", 0))
        }

func relation(first: String, second: String) -> int:
    if first == second:
        return 100
    return int(relations.get(_pair_key(first, second), 0))

func relation_label(first: String, second: String) -> String:
    if first == second:
        return "자국"
    if at_war(first, second):
        return "전쟁 중"
    var value := relation(first, second)
    if value >= 60:
        return "우호"
    if value >= 20:
        return "친선"
    if value > -20:
        return "중립"
    if value > -60:
        return "긴장"
    return "적대"

func adjust_relation(first: String, second: String, amount: int) -> int:
    if first == second:
        return 100
    var key := _pair_key(first, second)
    var next_value := clamp(int(relations.get(key, 0)) + amount, -100, 100)
    relations[key] = next_value
    return next_value

func at_war(first: String, second: String) -> bool:
    if first == second:
        return false
    return wars.has(_pair_key(first, second))

func declare_war(attacker: String, defender: String, turn: int) -> String:
    if attacker == defender:
        return "자국에는 전쟁을 선포할 수 없습니다."
    var key := _pair_key(attacker, defender)
    if wars.has(key):
        return "이미 전쟁 중입니다."
    wars[key] = {
        "attacker": attacker,
        "defender": defender,
        "start_turn": turn,
        "war_score": 0
    }
    relations[key] = min(-80, int(relations.get(key, 0)))
    return "전쟁이 시작되었습니다."

func make_peace(first: String, second: String) -> String:
    var key := _pair_key(first, second)
    if not wars.has(key):
        return "현재 전쟁 중이 아닙니다."
    wars.erase(key)
    relations[key] = -20
    return "평화 협정이 체결되었습니다."

func war_score(first: String, second: String) -> int:
    var war: Dictionary = wars.get(_pair_key(first, second), {})
    if war.is_empty():
        return 0
    var score := int(war.war_score)
    return score if String(war.attacker) == first else -score

func record_battle(winner: String, loser: String, score_change: int) -> void:
    var key := _pair_key(winner, loser)
    if not wars.has(key):
        return
    var war: Dictionary = wars[key]
    if String(war.attacker) == winner:
        war.war_score = clamp(int(war.war_score) + score_change, -100, 100)
    else:
        war.war_score = clamp(int(war.war_score) - score_change, -100, 100)
    wars[key] = war

func enemies_of(country_id: String) -> Array[String]:
    var result: Array[String] = []
    for war in wars.values():
        if String(war.attacker) == country_id:
            result.append(String(war.defender))
        elif String(war.defender) == country_id:
            result.append(String(war.attacker))
    return result

func advance_turn(countries: Dictionary) -> Array[String]:
    var logs: Array[String] = []
    for key in relations.keys():
        if wars.has(key):
            relations[key] = max(-100, int(relations[key]) - 1)
        else:
            var value := int(relations[key])
            if value > 0:
                relations[key] = value - 1
            elif value < 0:
                relations[key] = value + 1
    for key in wars.keys():
        var war: Dictionary = wars[key]
        var attacker := String(war.attacker)
        var defender := String(war.defender)
        if not countries.has(attacker) or not countries.has(defender):
            continue
        if int(war.war_score) >= 80 or int(war.war_score) <= -80:
            logs.append("%s–%s 전쟁의 승패가 기울고 있습니다. 전쟁 점수 %d" % [countries[attacker].name, countries[defender].name, war.war_score])
    return logs

func _pair_key(first: String, second: String) -> String:
    return "%s|%s" % [first, second] if first < second else "%s|%s" % [second, first]
