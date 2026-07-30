extends SceneTree


const StrategyCommandMapperScript = preload(
    "res://src/presentation/strategy_command_mapper.gd"
)
const StrategySnapshotPresenterScript = preload(
    "res://src/presentation/strategy_snapshot_presenter.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    _test_command_mapping()
    _test_snapshot_presentation()

    if failures.is_empty():
        print("Presentation refactor test: PASS")
        quit(0)
        return

    push_error(
        "Presentation refactor test: %d failure(s)" % failures.size()
    )
    for failure in failures:
        push_error(" - %s" % failure)
    quit(1)


func _test_command_mapping() -> void:
    var recruit := StrategyCommandMapperScript.build(
        "recruit",
        {"province_id": 7, "amount": 300},
        "goguryeo"
    )
    _expect(
        String(recruit.get("type", "")) == "recruit",
        "모집 명령의 코어 명칭을 유지해야 한다."
    )
    _expect(
        int(recruit.get("values", {}).get("target_id", -1)) == 7,
        "모집 대상 프로빈스를 코어 target_id로 번역해야 한다."
    )

    var fortify := StrategyCommandMapperScript.build(
        "fortify",
        {"province_id": 3},
        "baekje"
    )
    _expect(
        String(fortify.get("type", "")) == "build_fort",
        "화면의 fortify 명령을 코어 build_fort 명령으로 번역해야 한다."
    )

    var peace_offer := StrategyCommandMapperScript.build(
        "peace_offer",
        {
            "target_country_id": "silla",
            "province_demands": [4, 5],
            "reparations": 120,
            "vassalize": false,
            "recognize_independence": true
        },
        "goguryeo"
    )
    var peace_terms: Dictionary = peace_offer.get(
        "values",
        {}
    ).get("payload", {}).get("terms", {})
    _expect(
        peace_terms.get("province_ids", []) == [4, 5],
        "평화 협상의 프로빈스 요구를 손실 없이 전달해야 한다."
    )
    _expect(
        bool(peace_terms.get("recognize_independence", false)),
        "독립 승인 조건을 코어 협상 조건으로 전달해야 한다."
    )

    _expect(
        StrategyCommandMapperScript.build("unknown", {}, "gaya").is_empty(),
        "지원하지 않는 화면 명령은 빈 번역 결과를 반환해야 한다."
    )


func _test_snapshot_presentation() -> void:
    var presenter := StrategySnapshotPresenterScript.new()
    presenter.configure(
        {},
        {
            "map_id": "test_east_asia",
            "tile_size": 8.0,
            "province_anchors": {
                "alpha_basin": {"map_x": 10, "map_y": 20}
            }
        }
    )

    var core_snapshot := {
        "scenario_id": "prototype_east_asia",
        "player_country_id": "alpha",
        "turn": 4,
        "date": {"year": 100, "season": "spring"},
        "relations": {"alpha|beta": -20},
        "countries": {
            "alpha": {
                "name": "알파",
                "capital_province_id": 1,
                "government_id": "tribal_union"
            }
        },
        "provinces": {
            1: {
                "id": 1,
                "name": "알파 분지",
                "owner_id": "alpha",
                "controller_id": "alpha",
                "fort_level": 2,
                "unrest": 14.0,
                "source_province_id": "alpha_basin"
            }
        },
        "armies": {
            "army_alpha": {
                "province_id": 1,
                "soldiers": 320
            }
        },
        "wars": {
            "war_alpha_beta": {
                "id": "war_alpha_beta",
                "attackers": ["alpha"],
                "defenders": ["beta"],
                "score": 4.5
            }
        }
    }

    var snapshot: Dictionary = presenter.present(core_snapshot)
    var country: Dictionary = snapshot.get("countries", {}).get("alpha", {})
    var province: Dictionary = snapshot.get("provinces", {}).get(1, {})

    _expect(
        int(country.get("capital_province", -1)) == 1,
        "코어 수도 ID를 화면용 capital_province로 제공해야 한다."
    )
    _expect(
        String(province.get("owner", "")) == "alpha",
        "코어 owner_id를 화면용 owner로 제공해야 한다."
    )
    _expect(
        int(snapshot.get("armies", {}).get(1, 0)) == 320,
        "같은 프로빈스의 병력을 화면용 합계로 집계해야 한다."
    )
    _expect(
        String(snapshot.get("world_map_id", "")) == "test_east_asia",
        "동아시아 시나리오에 월드맵 ID를 부착해야 한다."
    )
    _expect(
        province.get("polygon", []).size() == 4,
        "월드맵 앵커로 선택용 사각 폴리곤을 생성해야 한다."
    )
    _expect(
        snapshot.get("wars", []).size() == 1,
        "코어 전쟁 Dictionary를 화면용 전쟁 배열로 변환해야 한다."
    )


func _expect(condition: bool, message: String) -> void:
    if condition:
        print("[PASS] %s" % message)
        return

    failures.append(message)
    push_error("[FAIL] %s" % message)
