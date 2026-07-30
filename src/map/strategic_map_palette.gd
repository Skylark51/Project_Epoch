class_name StrategicMapPalette
extends RefCounted


## Converts strategy state into map colors and numeric overlays.
##
## The renderer decides where and how to draw. This module decides what a
## province means visually in each map mode.


const TERRAIN_COLORS := {
    "plains": Color("#7d8a63"),
    "hills": Color("#81725b"),
    "forest": Color("#4f6c55"),
    "coast": Color("#58788a"),
    "coastal_water": Color("#1d4b60"),
    "deep_water": Color("#102f42")
}


static func numeric_values(
    provinces: Dictionary,
    mode: String,
    countries: Dictionary,
    armies: Dictionary
) -> Array[float]:
    var result: Array[float] = []
    for province_value in provinces.values():
        if province_value is Dictionary:
            result.append(
                numeric_value(province_value, mode, countries, armies)
            )
    return result


static func numeric_value(
    province: Dictionary,
    mode: String,
    countries: Dictionary,
    armies: Dictionary
) -> float:
    match mode:
        "economy":
            return float(province.get("economy", 0))
        "population":
            return log(1.0 + float(province.get("population", 0)))
        "development":
            return float(province.get("development", 0))
        "manpower":
            return float(
                province.get(
                    "manpower",
                    float(province.get("population", 0)) * 0.2
                )
            )
        "stability":
            var owner_id := String(province.get("owner", ""))
            var owner: Dictionary = countries.get(owner_id, {})
            return float(
                province.get("stability", owner.get("stability", 50))
            )
        "revolt":
            return float(
                province.get(
                    "revolt_risk",
                    maxf(
                        0.0,
                        100.0 - float(province.get("stability", 70))
                    )
                )
            )
        "fort":
            return float(province.get("fort", 0))
        "supply":
            var province_id := int(province.get("id", -1))
            return clampf(
                float(province.get("development", 0)) * 18.0
                + float(province.get("economy", 0))
                - float(armies.get(province_id, 0)) * 0.01,
                0.0,
                100.0
            )
    return 0.0


static func province_color(
    province: Dictionary,
    mode: String,
    robust_range: Vector2,
    countries: Dictionary,
    armies: Dictionary,
    relations: Dictionary,
    wars: Array,
    player_country_id: String
) -> Color:
    var owner_id := String(province.get("owner", ""))

    match mode:
        "political":
            return Color(
                String(
                    countries.get(owner_id, {}).get("color", "#6b7378")
                )
            )
        "relations":
            return _relations_color(
                owner_id,
                player_country_id,
                relations,
                wars
            )
        "war":
            if owner_id == player_country_id:
                return Color("#3f7580")
            if at_war(player_country_id, owner_id, wars):
                return Color("#9b3e3e")
            return Color("#4e5458")
        "terrain":
            return terrain_color(
                String(province.get("terrain", "plains")),
                Color("#6c735f")
            )

    var value := numeric_value(province, mode, countries, armies)
    var normalized := inverse_lerp(
        robust_range.x,
        robust_range.y,
        clampf(value, robust_range.x, robust_range.y)
    )
    var low := Color("#27343b")
    var high := Color("#d2a75f")

    if mode == "revolt":
        high = Color("#b34c45")
    elif mode == "stability":
        high = Color("#4d9a78")
    elif mode == "fort":
        high = Color("#9e87bd")

    return low.lerp(high, normalized)


static func border_color(
    province: Dictionary,
    player_country_id: String,
    relations: Dictionary,
    wars: Array
) -> Color:
    var owner_id := String(province.get("owner", ""))
    if owner_id == player_country_id:
        return Color("#87b6ba")
    if at_war(player_country_id, owner_id, wars):
        return Color("#e0655b")
    if relation(player_country_id, owner_id, relations) >= 25:
        return Color("#6e9aa5")
    return Color("#252a2d")


static func tile_land_color(
    tile: Dictionary,
    province: Dictionary,
    mode: String,
    robust_range: Vector2,
    countries: Dictionary,
    armies: Dictionary,
    relations: Dictionary,
    wars: Array,
    player_country_id: String
) -> Color:
    if mode == "terrain":
        return terrain_color(
            String(
                tile.get(
                    "terrain",
                    province.get("terrain", "plains")
                )
            ),
            Color("#6c735f")
        )

    var color := province_color(
        province,
        mode,
        robust_range,
        countries,
        armies,
        relations,
        wars,
        player_country_id
    )
    if bool(tile.get("coastal", false)):
        color = color.lerp(Color("#527787"), 0.08)
    return color


static func terrain_color(
    terrain_id: String,
    fallback: Color = Color("#102f42")
) -> Color:
    return TERRAIN_COLORS.get(terrain_id, fallback)


static func relation(
    first_country_id: String,
    second_country_id: String,
    relations: Dictionary
) -> int:
    if first_country_id == second_country_id:
        return 100
    return int(
        relations.get(
            pair_key(first_country_id, second_country_id),
            0
        )
    )


static func at_war(
    first_country_id: String,
    second_country_id: String,
    wars: Array
) -> bool:
    for war_value in wars:
        if war_value is not Dictionary:
            continue

        var war: Dictionary = war_value
        var attacker := String(war.get("attacker", ""))
        var defender := String(war.get("defender", ""))
        var direct_match := (
            attacker == first_country_id
            and defender == second_country_id
        )
        var reverse_match := (
            attacker == second_country_id
            and defender == first_country_id
        )
        if direct_match or reverse_match:
            return true
    return false


static func pair_key(first_country_id: String, second_country_id: String) -> String:
    if first_country_id < second_country_id:
        return first_country_id + "|" + second_country_id
    return second_country_id + "|" + first_country_id


static func _relations_color(
    owner_id: String,
    player_country_id: String,
    relations: Dictionary,
    wars: Array
) -> Color:
    if owner_id == player_country_id:
        return Color("#4f8a72")
    if at_war(player_country_id, owner_id, wars):
        return Color("#9c4343")

    var relation_value := relation(
        player_country_id,
        owner_id,
        relations
    )
    if relation_value >= 25:
        return Color("#4d7f91")
    if relation_value <= -25:
        return Color("#8f6447")
    return Color("#777a70")
