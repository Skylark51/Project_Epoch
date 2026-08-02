extends SceneTree

const Session = preload("res://src/core/game_session.gd")
const Gateway = preload("res://src/presentation/strategy_gateway.gd")
const ReadModel = preload("res://src/presentation/strategy_read_model.gd")
const NotificationCenter = preload("res://src/core/epoch_notification_center.gd")

const SAMPLE_SCENARIO := "res://data/scenarios/sample_campaign.json"
const LEGACY_SAVE_PATH := "user://wiki_legacy_v2.json"
const ROUND_TRIP_SAVE_PATH := "user://wiki_round_trip.json"
const GATEWAY_SAVE_PATH := "user://wiki_gateway_preferences.json"

var failures: Array[String] = []


func _initialize() -> void:
    for path in [LEGACY_SAVE_PATH, ROUND_TRIP_SAVE_PATH, GATEWAY_SAVE_PATH]:
        _remove_save(path)
    _test_governance_turn_effects()
    _test_risk_and_notification_deduplication()
    _test_occupation_stages()
    _test_assimilation_policy()
    _test_turn_review()
    _test_v2_migration_and_round_trip()
    _test_gateway_ui_preferences_city_rows_and_contract()
    for path in [LEGACY_SAVE_PATH, ROUND_TRIP_SAVE_PATH, GATEWAY_SAVE_PATH]:
        _remove_save(path)
    if failures.is_empty():
        print("Wiki governance/UI test: PASS")
        quit(0)
        return
    for failure in failures:
        push_error("[FAIL] %s" % failure)
    quit(1)


func _new_session() -> Variant:
    var session = Session.new()
    var started: Dictionary = session.start_scenario(SAMPLE_SCENARIO, "AUR")
    _check(bool(started.get("ok", false)), "sample session starts")
    return session


func _test_governance_turn_effects() -> void:
    var session = _new_session()
    var state = session.state
    _check(String(state.provinces[2].get("governance_level", "")) == "direct", "new city defaults to direct governance")
    var command: Dictionary = session.submit_command("change_governance", {
        "target_id": 2, "payload": {"governance_level": "delegated"}
    })
    _check(bool(command.get("valid", false)), "delegated governance command validates")
    _check(bool(session.end_turn().get("ok", false)), "delegated governance command resolves")
    var province: Dictionary = state.provinces[2]
    _check(String(province.get("governance_level", "")) == "delegated", "governance level changes on turn")
    _check(int(province.get("governance_turns", 0)) >= 1, "delegated duration advances")
    _check(float(province.get("command_precision", 1.0)) < 1.0, "delegation changes command precision")
    _check(float(province.get("governance_tax_multiplier", 1.0)) < 1.0, "delegation changes tax outcome")
    _check(float(state.countries.AUR.get("administrative_load", 0.0)) > 0.0, "administrative burden has no absolute city limit")
    var soldiers_before := _soldiers_at(state, "AUR", 2)
    var recruitment: Dictionary = session.submit_command("recruit", {"target_id": 2, "amount": 1000})
    _check(bool(recruitment.get("valid", false)), "delegated recruitment command validates")
    _check(bool(session.end_turn().get("ok", false)), "delegated recruitment resolves")
    _check(_soldiers_at(state, "AUR", 2) - soldiers_before == 760, "delegated precision changes recruited troop count")

    var temporary: Dictionary = state.provinces[2]
    temporary["owner_id"] = "BOR"
    temporary["controller_id"] = "AUR"
    temporary["occupation_stage"] = "immediate"
    state.provinces[2] = temporary
    var blocked: Dictionary = session.submit_command("develop", {"target_id": 2})
    _check(not bool(blocked.get("valid", false)), "immediate occupation blocks direct development order")

func _test_risk_and_notification_deduplication() -> void:
    var session = _new_session()
    var state = session.state
    var country: Dictionary = state.countries.AUR
    country["administration_capacity"] = 5
    state.countries.AUR = country
    state.armies.clear()
    var province: Dictionary = state.provinces[2]
    province["owner_id"] = "BOR"
    province["controller_id"] = "AUR"
    province["occupation_stage"] = "immediate"
    province["governance_level"] = "autonomous"
    province["governance_turns"] = 30
    province["happiness"] = 4.0
    province["local_stability"] = 5.0
    province["unrest"] = 96.0
    province["cultural_assimilation"] = 1.0
    state.provinces[2] = province
    session.processor.provincial_governance.advance_turn(state)
    var risky: Dictionary = state.provinces[2]
    _check(float(risky.get("corruption_risk", 0.0)) > 50.0, "corruption accumulates governance conditions")
    _check(float(risky.get("rebellion_risk", 0.0)) >= 70.0, "rebellion risk reaches imminent threshold")
    _check(String(risky.get("risk_stage", "")) == "imminent", "risk exposes warning stage")
    _check(_has_factor(risky.get("risk_factors", []), "수도 거리"), "risk explains capital-distance cause")
    _check(_has_factor(risky.get("risk_factors", []), "장기 위임"), "risk explains delegated-duration cause")
    _check(_has_factor(risky.get("risk_factors", []), "주둔군 부족"), "risk explains garrison cause")

    state.notifications.clear()
    var first: Dictionary = NotificationCenter.add(state, "important", "중복 방지", "같은 경고", "test:dedupe", {"type": "focus_province", "province_id": 2})
    var repeated: Dictionary = NotificationCenter.add(state, "important", "중복 방지", "같은 경고", "test:dedupe", {"type": "focus_province", "province_id": 2})
    _check(state.notifications.size() == 1, "same-turn notification deduplicates")
    _check(int(repeated.get("count", 0)) == 2 and int(first.get("id", -1)) == int(repeated.get("id", -2)), "deduplicated notification retains one action")
    _check(NotificationCenter.mark_read(state, int(first.get("id", -1))), "notification can become read")
    _check(bool(state.notifications[0].get("read", false)), "read state is stored")


func _test_occupation_stages() -> void:
    var session = _new_session()
    var state = session.state
    var province: Dictionary = state.provinces[4]
    province["controller_id"] = "AUR"
    state.provinces[4] = province
    state.armies["wiki_garrison"] = {"id": "wiki_garrison", "owner_id": "AUR", "province_id": 4, "soldiers": 1200}
    session.provincial_governance.initialize_state(state)

    session.processor.provincial_governance.advance_turn(state)
    var immediate: Dictionary = state.provinces[4].duplicate(true)
    _check(String(immediate.get("occupation_stage", "")) == "immediate", "occupation starts immediate")
    _check(is_equal_approx(float(immediate.get("occupation_tax_multiplier", 0.0)), 0.22), "immediate stage reduces income")
    _check(float(immediate.get("resistance", 0.0)) >= 70.0, "immediate stage raises resistance")

    var progressed: Dictionary = state.provinces[4]
    progressed["political_loyalty"] = 76.0
    progressed["civic_integration"] = 76.0
    progressed["cultural_assimilation"] = 68.0
    state.provinces[4] = progressed
    for index in range(2):
        session.processor.provincial_governance.advance_turn(state)
    var sustained: Dictionary = state.provinces[4].duplicate(true)
    _check(String(sustained.get("occupation_stage", "")) == "sustained", "occupation reaches sustained control")
    _check(float(sustained.get("occupation_tax_multiplier", 0.0)) > float(immediate.get("occupation_tax_multiplier", 0.0)), "sustained control improves income")

    for index in range(3):
        session.processor.provincial_governance.advance_turn(state)
    var de_facto: Dictionary = state.provinces[4].duplicate(true)
    _check(String(de_facto.get("occupation_stage", "")) == "de_facto", "occupation reaches de facto integration")
    _check(float(de_facto.get("resistance", 100.0)) < float(sustained.get("resistance", 100.0)), "integration reduces resistance")

    for index in range(4):
        session.processor.provincial_governance.advance_turn(state)
    var formal: Dictionary = state.provinces[4].duplicate(true)
    _check(String(formal.get("occupation_stage", "")) == "formal", "occupation reaches formal integration")
    _check(String(formal.get("owner_id", "")) == "AUR", "formal integration transfers ownership")
    _check(is_equal_approx(float(formal.get("occupation_tax_multiplier", 0.0)), 1.0), "formal integration restores income")
    _check(float(formal.get("resistance", 100.0)) <= 4.0, "formal integration lowers resistance")


func _test_assimilation_policy() -> void:
    var session = _new_session()
    var state = session.state
    var province: Dictionary = state.provinces[3]
    province["happiness"] = 65.0
    province["cultural_assimilation"] = 0.0
    state.provinces[3] = province
    var cultural_before := float(province.get("cultural_assimilation", 0.0))
    var active: Dictionary = session.submit_command("set_assimilation_policy", {
        "target_id": 3, "payload": {"policy": "active"}
    })
    _check(bool(active.get("valid", false)), "active assimilation policy validates")
    _check(bool(session.end_turn().get("ok", false)), "active policy resolves")
    _check(float(state.provinces[3].get("cultural_assimilation", 0.0)) > cultural_before, "assimilation accumulates per turn")
    var too_soon: Dictionary = session.submit_command("set_assimilation_policy", {
        "target_id": 3, "payload": {"policy": "gradual"}
    })
    _check(not bool(too_soon.get("valid", true)), "policy cooldown/minimum duration rejects rapid switch")
    for index in range(3):
        _check(bool(session.end_turn().get("ok", false)), "cooldown wait turn %d" % index)
    var happiness_before := float(state.provinces[3].get("happiness", 0.0))
    var gradual: Dictionary = session.submit_command("set_assimilation_policy", {
        "target_id": 3, "payload": {"policy": "gradual"}
    })
    _check(bool(gradual.get("valid", false)), "policy changes after minimum duration")
    _check(bool(session.end_turn().get("ok", false)), "second policy resolves")
    _check(float(state.provinces[3].get("happiness", 100.0)) < happiness_before - 2.0, "frequent policy switch applies distrust penalty")


func _test_turn_review() -> void:
    var session = _new_session()
    var state = session.state
    state.armies.clear()
    var province: Dictionary = state.provinces[2]
    province["happiness"] = 2.0
    province["local_stability"] = 2.0
    province["unrest"] = 96.0
    province["cultural_assimilation"] = 0.0
    province["governance_level"] = "autonomous"
    province["governance_turns"] = 25
    state.provinces[2] = province
    session.processor.provincial_governance.advance_turn(state)
    session.queue.submit({
        "command_type": "recruit", "country_id": "AUR", "source_id": null,
        "target_id": 999, "amount": 100.0, "cost": 0.0,
        "payload": {"mandatory": true}, "priority": 0
    }, state.turn)
    var review: Dictionary = session.turn_end_validation()
    _check(not review.get("blocking", []).is_empty(), "missing mandatory target blocks turn")
    _check(not review.get("important", []).is_empty(), "imminent rebellion creates important warning")
    _check(not bool(session.end_turn().get("ok", true)), "normal turn end respects blocking review")


func _test_v2_migration_and_round_trip() -> void:
    var session = _new_session()
    var legacy: Dictionary = session.state.to_dict()
    legacy.erase("notifications")
    legacy.erase("ui_preferences")
    legacy["schema_version"] = 2
    _write_json(LEGACY_SAVE_PATH, legacy)
    var migrated = Session.new()
    _check(bool(migrated.load(LEGACY_SAVE_PATH).get("ok", false)), "v2 save migrates safely")
    _check(migrated.state.notifications is Array and migrated.state.notifications.is_empty(), "migration defaults notifications")
    _check(migrated.state.ui_preferences is Dictionary, "migration defaults UI preferences")

    migrated.update_ui_preferences({"top_bar": {"order": ["treasury", "date"], "visible": {"treasury": true, "date": true}}, "right_panel_width": 410})
    var note: Dictionary = NotificationCenter.add(migrated.state, "caution", "저장 알림", "읽음 상태도 저장", "save:read")
    NotificationCenter.mark_read(migrated.state, int(note.get("id", -1)))
    _check(bool(migrated.save(ROUND_TRIP_SAVE_PATH).get("ok", false)), "new state saves")
    var restored = Session.new()
    _check(bool(restored.load(ROUND_TRIP_SAVE_PATH).get("ok", false)), "new state reloads")
    _check(int(restored.state.ui_preferences.get("right_panel_width", 0)) == 410, "panel width survives round trip")
    _check(restored.state.ui_preferences.get("top_bar", {}).get("order", []) == ["treasury", "date"], "top bar order survives round trip")
    _check(restored.state.notifications.size() == 1 and bool(restored.state.notifications[0].get("read", false)), "notification read state survives round trip")


func _test_gateway_ui_preferences_city_rows_and_contract() -> void:
    var gateway = Gateway.new()
    _check(gateway.has_signal("snapshot_changed") and gateway.has_signal("command_queue_changed"), "StrategyGateway keeps existing public signals")
    _check(gateway.has_signal("notifications_changed"), "StrategyGateway exposes notification signal")
    _check(gateway.has_method("submit_turn") and gateway.has_method("governance_options"), "StrategyGateway keeps command API and exposes governance options")
    _check(gateway.load_local_catalog(), "gateway catalog loads")
    gateway.autosave_path = GATEWAY_SAVE_PATH
    _check(gateway.update_ui_preferences({"top_bar": {"order": ["treasury", "date", "urgent"], "visible": {"treasury": true, "date": true, "urgent": false}}, "right_panel_width": 456}), "gateway accepts UI preference patch")
    _check(bool(gateway.save_autosave().get("ok", false)), "gateway saves UI preferences")
    var reloaded = Gateway.new()
    reloaded.autosave_path = GATEWAY_SAVE_PATH
    _check(reloaded.load_autosave(), "gateway reloads saved UI preferences")
    _check(int(reloaded.ui_preferences().get("right_panel_width", 0)) == 456, "gateway restores panel width")
    _check(reloaded.ui_preferences().get("top_bar", {}).get("order", []) == ["treasury", "date", "urgent"], "gateway restores top bar order")

    var read_model = ReadModel.new(reloaded)
    var country_id := String(reloaded.snapshot().get("player_country_id", ""))
    var rows: Array = read_model.city_rows(country_id, "population", "all", true)
    _check(rows.size() >= 2, "city list returns managed cities")
    if rows.size() >= 2:
        _check(int(rows[0].get("population", 0)) >= int(rows[1].get("population", 0)), "city list sorts population descending")
    var direct_rows: Array = read_model.city_rows(country_id, "city_name", "direct", false)
    var all_direct := true
    for row_value in direct_rows:
        if String(row_value.get("governance_level", "")) != "direct":
            all_direct = false
    _check(all_direct, "city list governance filter is accurate")
    _check(not reloaded.governance_options(country_id).is_empty(), "government profile provides allowed governance options")


func _soldiers_at(state, country_id: String, province_id: int) -> int:
    var total := 0
    for army_value in state.armies.values():
        if army_value is not Dictionary:
            continue
        var army: Dictionary = army_value
        if String(army.get("owner_id", "")) == country_id and int(army.get("province_id", -1)) == province_id:
            total += int(army.get("soldiers", 0))
    return total

func _has_factor(factors: Array, name: String) -> bool:
    for factor_value in factors:
        if factor_value is Dictionary and String(factor_value.get("name", "")) == name:
            return true
    return false


func _write_json(path: String, data: Dictionary) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(data))


func _remove_save(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, label: String) -> void:
    if condition:
        print("[PASS] %s" % label)
        return
    failures.append(label)
    push_error("[FAIL] %s" % label)
