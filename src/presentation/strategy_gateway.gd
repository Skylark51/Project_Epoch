class_name StrategyGateway
extends RefCounted

signal snapshot_changed(snapshot: Dictionary)
signal command_queue_changed(commands: Array)
signal turn_requested(commands: Array)
signal integration_notice(message: String)

var _countries: Dictionary = {}
var _provinces: Dictionary = {}
var _relations: Dictionary = {}
var _wars: Array = []
var _armies: Dictionary = {}
var _scenarios: Array[Dictionary] = []
var _commands: Array[Dictionary] = []
var _player_country_id := "AUR"
var _year := 1000
var _month := 1
var _day := 1
var _next_command_id := 1

func load_local_catalog() -> bool:
    var country_data = _load_json("res://data/countries.json")
    var province_data = _load_json("res://data/provinces.json")
    var diplomacy_data = _load_json("res://data/diplomacy.json")
    var scenario_data = _load_json("res://data/scenarios/001_prototype.json")
    if not country_data is Dictionary or not province_data is Dictionary or not scenario_data is Dictionary:
        integration_notice.emit("기본 JSON 데이터를 불러오지 못했습니다.")
        return false
    _countries.clear()
    for value in country_data.get("countries", []):
        if value is Dictionary:
            _countries[String(value.get("id", ""))] = value.duplicate(true)
    _provinces.clear()
    _armies.clear()
    for value in province_data.get("provinces", []):
        if value is Dictionary:
            var id := int(value.get("id", -1))
            _provinces[id] = value.duplicate(true)
            _armies[id] = int(value.get("army", 0))
    _relations.clear()
    _wars.clear()
    if diplomacy_data is Dictionary:
        for value in diplomacy_data.get("relations", []):
            if value is Dictionary:
                _relations[_pair_key(String(value.get("a", "")), String(value.get("b", "")))] = int(value.get("value", 0))
        for value in diplomacy_data.get("wars", []):
            if value is Dictionary: _wars.append(value.duplicate(true))
    _scenarios = [scenario_data.duplicate(true)]
    _player_country_id = String(scenario_data.get("player_country", "AUR"))
    var date: Dictionary = scenario_data.get("start_date", {})
    _year = int(date.get("year", 1000)); _month = int(date.get("month", 1)); _day = int(date.get("day", 1))
    snapshot_changed.emit(snapshot())
    return true

func snapshot() -> Dictionary:
    return {
        "countries": _countries.duplicate(true), "provinces": _provinces.duplicate(true),
        "relations": _relations.duplicate(true), "wars": _wars.duplicate(true), "armies": _armies.duplicate(true),
        "player_country_id": _player_country_id, "date": {"year": _year, "month": _month, "day": _day}
    }

func scenarios() -> Array[Dictionary]:
    return _scenarios.duplicate(true)

func countries() -> Dictionary:
    return _countries.duplicate(true)

func select_player_country(country_id: String) -> bool:
    if not _countries.has(country_id): return false
    _player_country_id = country_id
    _commands.clear(); _next_command_id = 1
    snapshot_changed.emit(snapshot()); command_queue_changed.emit(commands())
    return true

func commands() -> Array:
    return _commands.duplicate(true)

func queue_command(command_type: String, payload: Dictionary, presentation: Dictionary = {}) -> int:
    var command := {
        "id": _next_command_id, "type": command_type, "country_id": _player_country_id,
        "payload": payload.duplicate(true), "presentation": presentation.duplicate(true), "status": "awaiting_core"
    }
    _commands.append(command)
    _next_command_id += 1
    command_queue_changed.emit(commands())
    return int(command.id)

func update_command(command_id: int, payload: Dictionary) -> bool:
    for index in range(_commands.size()):
        if int(_commands[index].get("id", -1)) == command_id:
            _commands[index]["payload"] = payload.duplicate(true)
            command_queue_changed.emit(commands())
            return true
    return false

func cancel_command(command_id: int) -> bool:
    for index in range(_commands.size()):
        if int(_commands[index].get("id", -1)) == command_id:
            _commands.remove_at(index)
            command_queue_changed.emit(commands())
            return true
    return false

func clear_commands() -> void:
    _commands.clear(); _next_command_id = 1
    command_queue_changed.emit(commands())

func submit_turn() -> void:
    if _commands.is_empty():
        integration_notice.emit("예약된 명령이 없습니다. 코어 턴 API 연결을 기다리고 있습니다.")
        return
    turn_requested.emit(commands())
    integration_notice.emit("명령을 코어 턴 처리기로 전달했습니다. 현재 브랜치에는 코어 구현이 없어 상태는 변경하지 않습니다.")

func province(province_id: int) -> Dictionary:
    return _provinces.get(province_id, {}).duplicate(true)

func country(country_id: String) -> Dictionary:
    return _countries.get(country_id, {}).duplicate(true)

func relation(a: String, b: String) -> int:
    return 100 if a == b else int(_relations.get(_pair_key(a, b), 0))

func at_war(a: String, b: String) -> bool:
    for war in _wars:
        var attacker := String(war.get("attacker", "")); var defender := String(war.get("defender", ""))
        if (attacker == a and defender == b) or (attacker == b and defender == a): return true
    return false

func _load_json(path: String):
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("파일을 열 수 없습니다: " + path)
        return null
    var parsed = JSON.parse_string(file.get_as_text())
    if parsed == null: push_error("JSON 파싱 실패: " + path)
    return parsed

func _pair_key(a: String, b: String) -> String:
    return a + "|" + b if a < b else b + "|" + a