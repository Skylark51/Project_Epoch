class_name StrategyReadModel
extends RefCounted


## Provides named, read-only questions about the current strategy snapshot.
##
## UI code should ask questions such as "which provinces belong to this
## country?" or "what is the total army?". It should not repeat dictionary
## traversal and fallback rules every time a label is refreshed.


const TERRAIN_NAMES := {
    "plains": "평원",
    "hills": "구릉",
    "forest": "숲",
    "coast": "해안"
}

const COMMAND_ICONS := {
    "move": "→",
    "attack": "⚔",
    "recruit": "+",
    "declare_war": "!",
    "peace_offer": "◇",
    "develop": "◆",
    "fortify": "▣"
}

const DIPLOMACY_NAMES := {
    "improve_relations": "관계 개선",
    "insult": "모욕",
    "declare_war": "전쟁 선포",
    "offer_peace": "평화 제안",
    "offer_alliance": "동맹 제안",
    "offer_non_aggression": "불가침 제안",
    "request_access": "군사 통행 요청",
    "demand_vassalization": "속국화 요구",
    "demand_independence": "독립 요구"
}


var gateway


func _init(strategy_gateway) -> void:
    gateway = strategy_gateway


func number(value: int) -> String:
    var sign_multiplier := -1.0 if value < 0 else 1.0
    var magnitude := float(abs(value))
    if magnitude >= 1_000_000.0:
        return "%.1fM" % (sign_multiplier * floor(magnitude / 100_000.0) / 10.0)
    if magnitude >= 1_000.0:
        return "%.1fK" % (sign_multiplier * floor(magnitude / 100.0) / 10.0)
    return str(value)

func country_name(country_id: String) -> String:
    return String(gateway.country(country_id).get("name", country_id))


func province_name(province_id: int) -> String:
    return String(
        gateway.province(province_id).get(
            "name",
            "Province %d" % province_id
        )
    )


func terrain_name(terrain_id: String) -> String:
    return String(TERRAIN_NAMES.get(terrain_id, terrain_id))


func difficulty(country: Dictionary) -> String:
    if int(country.get("treasury", 0)) >= 130:
        return "쉬움"
    if int(country.get("aggression", 50)) >= 70:
        return "어려움"
    return "보통"


func owned_provinces(country_id: String) -> Array[int]:
    var result: Array[int] = []
    for province_id_value in _snapshot().get("provinces", {}).keys():
        var province_id := int(province_id_value)
        if String(gateway.province(province_id).get("owner", "")) == country_id:
            result.append(province_id)
    return result

func managed_provinces(country_id: String) -> Array[int]:
    var result: Array[int] = []
    for province_id_value in _snapshot().get("provinces", {}).keys():
        var province_id := int(province_id_value)
        var province: Dictionary = gateway.province(province_id)
        if String(province.get("owner", "")) == country_id \
                or String(province.get("controller", "")) == country_id:
            result.append(province_id)
    return result



func active_selection(
    selected_province_ids: Array[int],
    selected_province_id: int
) -> Array[int]:
    if not selected_province_ids.is_empty():
        return selected_province_ids.duplicate()
    if selected_province_id != -1:
        return [selected_province_id]
    return []


func owned_selection(
    selected_province_ids: Array[int],
    selected_province_id: int,
    country_id: String
) -> Array[int]:
    var result: Array[int] = []
    for province_id in active_selection(
        selected_province_ids,
        selected_province_id
    ):
        if String(gateway.province(province_id).get("owner", "")) == country_id:
            result.append(province_id)
    return result


func country_total(country_id: String, field_name: String) -> int:
    var total := 0
    for province_id in owned_provinces(country_id):
        total += int(gateway.province(province_id).get(field_name, 0))
    return total


func army_total(country_id: String) -> int:
    var total := 0
    var armies: Dictionary = _snapshot().get("armies", {})
    for province_id in owned_provinces(country_id):
        total += int(armies.get(province_id, 0))
    return total


func income(country_id: String) -> int:
    var economy := float(country_total(country_id, "economy"))
    var tax_rate := float(gateway.country(country_id).get("tax_rate", 0.2))
    return int(economy * tax_rate)
func average_city_value(country_id: String, field_name: String) -> float:
    var province_ids := managed_provinces(country_id)
    if province_ids.is_empty():
        return 0.0
    var total := 0.0
    for province_id in province_ids:
        total += float(gateway.province(province_id).get(field_name, 0.0))
    return total / float(province_ids.size())
func revolt_risk_city_count(country_id: String, threshold: float = 50.0) -> int:
    var count := 0
    for province_id in managed_provinces(country_id):
        if float(gateway.province(province_id).get("rebellion_risk", 0.0)) >= threshold:
            count += 1
    return count
func city_rows(country_id: String, sort_key: String, filter_id: String, descending: bool) -> Array:
    var rows: Array = []
    for province_id in managed_provinces(country_id):
        var province: Dictionary = gateway.province(province_id)
        if not _city_matches_filter(province, filter_id):
            continue
        var row: Dictionary = Dictionary(province.duplicate(true))
        row["province_id"] = province_id
        rows.append(row)
    rows.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
        var first_value: Variant = _city_sort_value(first, sort_key)
        var second_value: Variant = _city_sort_value(second, sort_key)
        var before := false
        if first_value is String or second_value is String:
            before = String(first_value).naturalnocasecmp_to(String(second_value)) < 0
        else:
            before = float(first_value) < float(second_value)
        return not before if descending else before
    )
    return rows


func available_army(province_ids: Array[int], leave_garrison: int = 1) -> int:
    var total := 0
    var armies: Dictionary = _snapshot().get("armies", {})
    for province_id in province_ids:
        total += maxi(0, int(armies.get(province_id, 0)) - leave_garrison)
    return total


func supply_score(province_id: int) -> float:
    var province: Dictionary = gateway.province(province_id)
    var armies: Dictionary = _snapshot().get("armies", {})
    return (
        float(province.get("development", 0)) * 18.0
        + float(province.get("economy", 0))
        - float(armies.get(province_id, 0)) * 0.01
    )


func has_neighbor(province: Dictionary, target_id: int) -> bool:
    for neighbor_value in province.get("neighbors", []):
        if int(neighbor_value) == target_id:
            return true
    return false


func neighbor_names(neighbor_ids: Array) -> String:
    var names := PackedStringArray()
    for neighbor_id in neighbor_ids:
        names.append(province_name(int(neighbor_id)))
    return ", ".join(names)


func border_names(first_country_id: String, second_country_id: String) -> String:
    var names := PackedStringArray()
    for province_id in owned_provinces(first_country_id):
        var province: Dictionary = gateway.province(province_id)
        for neighbor_value in province.get("neighbors", []):
            var neighbor_id := int(neighbor_value)
            var neighbor_owner := String(
                gateway.province(neighbor_id).get("owner", "")
            )
            if neighbor_owner == second_country_id:
                names.append(province_name(province_id))
                break

    if names.is_empty():
        return "없음"
    return ", ".join(names)


func foreign_country(
    selected_province_id: int,
    player_country_id: String
) -> String:
    if selected_province_id == -1:
        return ""

    var owner := String(
        gateway.province(selected_province_id).get("owner", "")
    )
    if owner == player_country_id:
        return ""
    return owner


func command_icon(command_type: String) -> String:
    return String(COMMAND_ICONS.get(command_type, "•"))


func diplomacy_name(command_type: String) -> String:
    return String(DIPLOMACY_NAMES.get(command_type, command_type))
func city_risk_causes(province: Dictionary) -> String:
    var items := PackedStringArray()
    for factor_value in province.get("risk_factors", []):
        var factor: Dictionary = factor_value
        if float(factor.get("value", 0.0)) <= 0.0:
            continue
        items.append("%s %.1f" % [String(factor.get("name", "factor")), float(factor.get("value", 0.0))])
        if items.size() == 3:
            break
    return ", ".join(items)
func _city_matches_filter(province: Dictionary, filter_id: String) -> bool:
    if filter_id == "all":
        return true
    if filter_id == "occupied":
        return String(province.get("occupation_stage", "formal")) != "formal"
    if filter_id == "risk":
        return float(province.get("rebellion_risk", 0.0)) >= 50.0
    if filter_id in ["direct", "delegated", "autonomous"]:
        return String(province.get("governance_level", "direct")) == filter_id
    if filter_id == "policy":
        return String(province.get("assimilation_policy", "status_quo")) != "status_quo"
    return true
func _city_sort_value(province: Dictionary, sort_key: String) -> Variant:
    match sort_key:
        "city_name":
            return String(province.get("name", ""))
        "population", "economy", "happiness", "stability", "rebellion_risk":
            return float(province.get(sort_key, 0.0))
        "occupation":
            var stage_order: Dictionary = {"immediate": 0, "sustained": 1, "de_facto": 2, "formal": 3}
            return int(stage_order.get(String(province.get("occupation_stage", "formal")), 3))
        "governance":
            var level_order: Dictionary = {"direct": 0, "delegated": 1, "autonomous": 2}
            return int(level_order.get(String(province.get("governance_level", "direct")), 3))
        "policy":
            return String(province.get("assimilation_policy", "status_quo"))
        _:
            return String(province.get("name", ""))


func _snapshot() -> Dictionary:
    return gateway.snapshot()
