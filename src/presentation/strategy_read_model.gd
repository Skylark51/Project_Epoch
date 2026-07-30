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
    if abs(value) >= 1_000_000:
        return "%.1fM" % _truncate_decimal(float(value) / 1_000_000.0)
    if abs(value) >= 1_000:
        return "%.1fK" % _truncate_decimal(float(value) / 1_000.0)
    return str(value)


func _truncate_decimal(value: float) -> float:
    return signf(value) * floorf(absf(value) * 10.0) / 10.0


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


func _snapshot() -> Dictionary:
    return gateway.snapshot()
