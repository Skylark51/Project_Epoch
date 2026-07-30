class_name StrategySnapshotPresenter
extends RefCounted


## Converts the core simulation snapshot into the stable read model consumed by
## the current UI and map. It does not load files, emit signals, or mutate the
## GameSession; it only translates data.
var _visual_geometry: Dictionary = {}
var _world_map_manifest: Dictionary = {}


func configure(
    visual_geometry: Dictionary,
    world_map_manifest: Dictionary
) -> void:
    _visual_geometry = visual_geometry.duplicate(true)
    _world_map_manifest = world_map_manifest.duplicate(true)


func present(core: Dictionary) -> Dictionary:
    var presented_countries := _present_countries(core.get("countries", {}))
    var presented_provinces := _present_provinces(core.get("provinces", {}))
    var presented_armies := _present_armies(
        core.get("armies", {}),
        presented_provinces
    )

    var result: Dictionary = {
        "countries": presented_countries,
        "provinces": presented_provinces,
        "armies": presented_armies,
        "relations": core.get("relations", {}).duplicate(true),
        "wars": _present_wars(core.get("wars", {})),
        "scenario_id": String(core.get("scenario_id", "")),
        "player_country_id": String(core.get("player_country_id", "")),
        "date": core.get("date", {}).duplicate(true),
        "turn": int(core.get("turn", 1)),
        "map_tiles": [],
        "map_labels": []
    }

    if result["scenario_id"] == "prototype_east_asia":
        _attach_east_asia_map_data(result)

    return result


func _present_countries(core_countries: Dictionary) -> Dictionary:
    var countries: Dictionary = {}

    for country_id_value in core_countries.keys():
        var country_id := String(country_id_value)
        var source: Dictionary = core_countries[country_id_value]
        var country := source.duplicate(true)

        country["capital_province"] = int(
            source.get("capital_province_id", -1)
        )
        country["government"] = String(source.get("government_id", "정부"))
        country["income"] = 0
        countries[country_id] = country

    return countries


func _present_provinces(core_provinces: Dictionary) -> Dictionary:
    var provinces: Dictionary = {}

    for province_id_value in core_provinces.keys():
        var province_id := int(province_id_value)
        var source: Dictionary = core_provinces[province_id_value]
        var province := source.duplicate(true)
        var owner_id := String(source.get("owner_id", ""))

        province["owner"] = owner_id
        province["controller"] = String(
            source.get("controller_id", owner_id)
        )
        province["fort"] = int(source.get("fort_level", 0))
        province["revolt_risk"] = float(source.get("unrest", 0.0))
        province["polygon"] = source.get(
            "polygon",
            _visual_geometry.get(province_id, _fallback_polygon(province_id))
        ).duplicate(true)

        provinces[province_id] = province

    return provinces


func _present_armies(
    core_armies: Dictionary,
    presented_provinces: Dictionary
) -> Dictionary:
    var armies: Dictionary = {}

    for province_id_value in presented_provinces.keys():
        armies[int(province_id_value)] = 0

    for army_value in core_armies.values():
        if army_value is not Dictionary:
            continue

        var army: Dictionary = army_value
        var province_id := int(army.get("province_id", -1))
        armies[province_id] = int(armies.get(province_id, 0)) + int(
            army.get("soldiers", 0)
        )

    return armies


func _present_wars(core_wars: Dictionary) -> Array:
    var wars: Array = []

    for war_value in core_wars.values():
        if war_value is not Dictionary:
            continue

        var war: Dictionary = war_value
        var attackers: Array = war.get("attackers", [])
        var defenders: Array = war.get("defenders", [])
        var score := float(war.get("score", 0.0))

        wars.append({
            "id": war.get("id", ""),
            "attacker": String(attackers[0]) if not attackers.is_empty() else "",
            "defender": String(defenders[0]) if not defenders.is_empty() else "",
            "score": score,
            "war_score": score,
            "attackers": attackers.duplicate(),
            "defenders": defenders.duplicate()
        })

    return wars


func _attach_east_asia_map_data(snapshot: Dictionary) -> void:
    snapshot["world_map_id"] = String(
        _world_map_manifest.get("map_id", "east_asia_640x480")
    )

    var anchors: Dictionary = _world_map_manifest.get(
        "province_anchors",
        {}
    )
    var tile_size := float(_world_map_manifest.get("tile_size", 8.0))
    var provinces: Dictionary = snapshot["provinces"]

    for province_id_value in provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = provinces[province_id]
        var source_id := String(province.get("source_province_id", ""))

        if not anchors.has(source_id):
            continue

        var anchor: Dictionary = anchors[source_id]
        var center := Vector2(
            float(anchor.get("map_x", 0.0)),
            float(anchor.get("map_y", 0.0))
        ) * tile_size

        province["map_center"] = [center.x, center.y]
        province["polygon"] = [
            [center.x - tile_size, center.y - tile_size],
            [center.x + tile_size, center.y - tile_size],
            [center.x + tile_size, center.y + tile_size],
            [center.x - tile_size, center.y + tile_size]
        ]


func _fallback_polygon(province_id: int) -> Array:
    var index := maxi(0, province_id - 1)
    var column := index % 3
    var row := int(index / 3)
    var x := 70.0 + column * 245.0
    var y := 60.0 + row * 170.0

    return [
        [x, y + 20.0],
        [x + 55.0, y],
        [x + 205.0, y + 12.0],
        [x + 220.0, y + 118.0],
        [x + 150.0, y + 145.0],
        [x + 18.0, y + 130.0]
    ]
