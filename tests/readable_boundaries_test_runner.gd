extends SceneTree


const StrategicMapGeometryScript = preload(
    "res://src/map/strategic_map_geometry.gd"
)
const StrategicMapPaletteScript = preload(
    "res://src/map/strategic_map_palette.gd"
)
const StrategyReadModelScript = preload(
    "res://src/presentation/strategy_read_model.gd"
)
const ProjectEpochUiFactoryScript = preload(
    "res://src/ui/project_epoch_ui_factory.gd"
)


class FakeGateway:
    extends RefCounted

    var data := {
        "countries": {
            "goguryeo": {
                "id": "goguryeo",
                "name": "고구려",
                "treasury": 150,
                "tax_rate": 0.2,
                "manpower": 40
            },
            "baekje": {
                "id": "baekje",
                "name": "백제",
                "treasury": 90,
                "tax_rate": 0.25,
                "manpower": 30
            }
        },
        "provinces": {
            1: {
                "id": 1,
                "name": "국내성 권역",
                "owner": "goguryeo",
                "population": 1000,
                "economy": 50,
                "development": 2,
                "neighbors": [2]
            },
            2: {
                "id": 2,
                "name": "한성 권역",
                "owner": "baekje",
                "population": 800,
                "economy": 40,
                "development": 1,
                "neighbors": [1]
            }
        },
        "armies": {
            1: 120,
            2: 80
        }
    }

    func snapshot() -> Dictionary:
        return data.duplicate(true)

    func country(country_id: String) -> Dictionary:
        return data.countries.get(country_id, {}).duplicate(true)

    func province(province_id: int) -> Dictionary:
        return data.provinces.get(province_id, {}).duplicate(true)


var failures: Array[String] = []


func _initialize() -> void:
    _test_geometry_boundary()
    _test_palette_boundary()
    _test_read_model_boundary()
    _test_ui_factory_boundary()
    _finish()


func _test_geometry_boundary() -> void:
    var screen_point := Vector2(400, 240)
    var pan := Vector2(80, 40)
    var zoom := 2.0
    var world_point := StrategicMapGeometryScript.screen_to_world(
        screen_point,
        pan,
        zoom
    )
    _expect(
        world_point == Vector2(160, 100),
        "화면 좌표를 월드 좌표로 변환한다."
    )

    var camera := StrategicMapGeometryScript.zoom_at(
        screen_point,
        1.5,
        pan,
        zoom,
        0.1,
        8.0
    )
    var next_zoom := float(camera.get("zoom", 0.0))
    var next_pan := Vector2(camera.get("pan", Vector2.ZERO))
    var anchored_world_point := StrategicMapGeometryScript.screen_to_world(
        screen_point,
        next_pan,
        next_zoom
    )
    _expect(
        anchored_world_point.distance_to(world_point) < 0.001,
        "확대 전후 마우스 아래 월드 좌표가 유지된다."
    )

    var polygon := StrategicMapGeometryScript.polygon_from([
        [0, 0],
        [10, 0],
        [10, 10],
        [0, 10]
    ])
    _expect(polygon.size() == 4, "배열 좌표를 폴리곤으로 변환한다.")

    var center := StrategicMapGeometryScript.province_center({
        "polygon": [[0, 0], [10, 0], [10, 10], [0, 10]]
    })
    _expect(center == Vector2(5, 5), "프로빈스 중심을 계산한다.")

    var robust_range := StrategicMapGeometryScript.robust_range([
        1.0,
        1.0,
        1.0
    ])
    _expect(
        robust_range.y > robust_range.x,
        "동일한 값에서도 유효한 시각화 범위를 만든다."
    )

    var buckets := {}
    StrategicMapGeometryScript.add_polygon_to_buckets(
        buckets,
        7,
        polygon,
        8.0
    )
    _expect(not buckets.is_empty(), "공간 선택 버킷을 구성한다.")


func _test_palette_boundary() -> void:
    var countries := {
        "goguryeo": {"color": "#335577", "stability": 70},
        "baekje": {"color": "#884433", "stability": 50}
    }
    var province := {
        "id": 1,
        "owner": "goguryeo",
        "economy": 50,
        "population": 1000,
        "development": 2,
        "fort": 1
    }
    var armies := {1: 100}
    var relations := {"baekje|goguryeo": -40}
    var wars := [{"attacker": "goguryeo", "defender": "baekje"}]

    _expect(
        StrategicMapPaletteScript.numeric_value(
            province,
            "economy",
            countries,
            armies
        ) == 50.0,
        "경제 지도 수치를 계산한다."
    )
    _expect(
        StrategicMapPaletteScript.at_war(
            "goguryeo",
            "baekje",
            wars
        ),
        "전쟁 관계를 양방향으로 판정한다."
    )
    _expect(
        StrategicMapPaletteScript.relation(
            "goguryeo",
            "baekje",
            relations
        ) == -40,
        "정렬된 국가 쌍 키로 관계도를 읽는다."
    )

    var political_color := StrategicMapPaletteScript.province_color(
        province,
        "political",
        Vector2(0, 100),
        countries,
        armies,
        relations,
        wars,
        "goguryeo"
    )
    _expect(
        political_color == Color("#335577"),
        "정치 지도는 국가색을 사용한다."
    )


func _test_read_model_boundary() -> void:
    var gateway := FakeGateway.new()
    var read_model := StrategyReadModelScript.new(gateway)

    _expect(
        read_model.country_name("goguryeo") == "고구려",
        "국가 이름을 화면용으로 읽는다."
    )
    _expect(
        read_model.province_name(1) == "국내성 권역",
        "프로빈스 이름을 화면용으로 읽는다."
    )
    _expect(
        read_model.owned_provinces("goguryeo") == [1],
        "국가 소유 프로빈스를 찾는다."
    )
    _expect(
        read_model.country_total("goguryeo", "economy") == 50,
        "국가 단위 프로빈스 수치를 합산한다."
    )
    _expect(
        read_model.army_total("goguryeo") == 120,
        "국가 총병력을 합산한다."
    )
    _expect(
        read_model.income("goguryeo") == 10,
        "경제와 세율로 예상 수입을 계산한다."
    )
    _expect(
        read_model.border_names("goguryeo", "baekje") == "국내성 권역",
        "국경 프로빈스 이름을 설명한다."
    )
    _expect(
        read_model.number(1_250) == "1.2K",
        "큰 수를 일관된 형식으로 표현한다."
    )


func _test_ui_factory_boundary() -> void:
    var label := ProjectEpochUiFactoryScript.label(
        "설명",
        16,
        Color.WHITE
    )
    _expect(label.text == "설명", "공통 라벨을 생성한다.")

    var button := ProjectEpochUiFactoryScript.button(
        "확인",
        func(): pass,
        "primary"
    )
    _expect(button.text == "확인", "공통 버튼을 생성한다.")
    _expect(
        button.has_theme_stylebox_override("normal"),
        "기본 버튼 변형의 시각 규칙을 적용한다."
    )

    var margin := ProjectEpochUiFactoryScript.margin_container(12)
    _expect(
        margin.get_theme_constant("margin_left") == 12,
        "공통 여백 컨테이너를 생성한다."
    )


func _expect(condition: bool, message: String) -> void:
    if condition:
        print("[PASS] %s" % message)
    else:
        failures.append(message)
        push_error("[FAIL] %s" % message)


func _finish() -> void:
    if failures.is_empty():
        print("Readable boundary tests: PASS")
        quit(0)
        return

    push_error("Readable boundary tests: %d failure(s)" % failures.size())
    for failure in failures:
        push_error(" - %s" % failure)
    quit(1)
