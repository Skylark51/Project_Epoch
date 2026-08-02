class_name TurnEndValidator
extends RefCounted


## Produces an actionable review before a turn advances.  The validator does
## not mutate the session: callers can show blocking items, warnings, and
## recommendations in different parts of the UI before deciding to continue.

const SEVERITY_BLOCKING := "blocking"
const SEVERITY_IMPORTANT := "important"
const SEVERITY_RECOMMENDATION := "recommendation"


func evaluate(
    state,
    commands: Array,
    processor,
    ui_preferences_dirty: bool = false
) -> Dictionary:
    var result := {
        "blocking": [],
        "important": [],
        "recommendations": [],
        "items": [],
    }
    if state == null:
        _append(
            result,
            SEVERITY_BLOCKING,
            "시나리오가 시작되지 않았습니다",
            "턴을 진행하려면 먼저 시나리오를 시작해야 합니다.",
            {}
        )
        return result

    _validate_queued_commands(state, commands, processor, result)
    _validate_rebellion_risk(state, result)
    _validate_occupation_and_policy(state, result)
    _validate_wartime_garrisons(state, result)
    if ui_preferences_dirty:
        _append(
            result,
            SEVERITY_RECOMMENDATION,
            "저장되지 않은 UI 설정",
            "상단 정보 바 또는 패널 폭 변경을 저장하면 다음 실행에도 유지됩니다.",
            {"type": "save_preferences"}
        )
    return result


func _validate_queued_commands(
    state,
    commands: Array,
    processor,
    result: Dictionary
) -> void:
    for command_value in commands:
        if command_value is not Dictionary:
            continue
        var command: Dictionary = command_value
        var validation: Dictionary = processor.validate_command(state, command)
        if bool(validation.get("valid", false)):
            continue
        var title := "실행 불가 명령 · %s" % String(
            command.get("command_type", "명령")
        )
        var detail := String(validation.get("reason", "검증 실패"))
        var mandatory := bool(command.get("payload", {}).get("mandatory", false))
        var vanished_target := _target_is_missing(state, command)
        _append(
            result,
            SEVERITY_BLOCKING if mandatory or vanished_target else SEVERITY_IMPORTANT,
            title,
            detail,
            {
                "type": "inspect_command",
                "command_id": String(command.get("command_id", "")),
                "province_id": int(command.get("target_id", command.get("source_id", -1))),
            }
        )


func _validate_rebellion_risk(state, result: Dictionary) -> void:
    for province_id_value in state.provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = state.provinces[province_id_value]
        var risk := float(province.get("rebellion_risk", province.get("unrest", 0.0)))
        if risk < 70.0:
            continue
        _append(
            result,
            SEVERITY_IMPORTANT,
            "%s · 반란 임박" % String(province.get("name", "도시")),
            "반란 위험 %.0f. 주둔군 보강, 행정 부담 완화, 정책 안정화를 검토하세요." % risk,
            {"type": "focus_province", "province_id": province_id}
        )


func _validate_occupation_and_policy(state, result: Dictionary) -> void:
    for province_id_value in state.provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = state.provinces[province_id_value]
        var stage := String(province.get("occupation_stage", "formal"))
        if stage == "immediate":
            _append(
                result,
                SEVERITY_IMPORTANT,
                "%s · 점령지 통제 미정착" % String(province.get("name", "도시")),
                "점령 직후 도시입니다. 주둔군과 통합 정책을 확인한 뒤 진행하세요.",
                {"type": "focus_province", "province_id": province_id}
            )
        var cooldown_until := int(province.get("policy_cooldown_until", 0))
        if cooldown_until > int(state.turn):
            _append(
                result,
                SEVERITY_RECOMMENDATION,
                "%s · 정책 변경 대기" % String(province.get("name", "도시")),
                "%d턴부터 융화 정책을 다시 변경할 수 있습니다." % cooldown_until,
                {"type": "focus_province", "province_id": province_id}
            )


func _validate_wartime_garrisons(state, result: Dictionary) -> void:
    var player_id := String(state.player_country_id)
    if player_id.is_empty() or not _at_war(state, player_id):
        return
    for province_id_value in state.provinces.keys():
        var province_id := int(province_id_value)
        var province: Dictionary = state.provinces[province_id_value]
        if String(province.get("controller_id", "")) != player_id:
            continue
        if not _has_hostile_neighbor(state, province, player_id):
            continue
        if _garrison_strength(state, province_id, player_id) >= 300:
            continue
        _append(
            result,
            SEVERITY_IMPORTANT,
            "%s · 전시 주둔군 부족" % String(province.get("name", "도시")),
            "전쟁 중 접경 또는 점령 도시의 주둔군이 300명 미만입니다.",
            {"type": "focus_province", "province_id": province_id}
        )


func _target_is_missing(state, command: Dictionary) -> bool:
    var command_type := String(command.get("command_type", ""))
    if command_type in ["declare_war", "improve_relations", "form_alliance", "break_alliance", "create_vassal", "release_vassal", "offer_peace"]:
        return not state.countries.has(String(command.get("target_id", "")))
    var target_id: Variant = command.get("target_id", command.get("source_id", null))
    if target_id == null:
        return false
    return not state.provinces.has(int(target_id))


func _at_war(state, country_id: String) -> bool:
    for war_value in state.wars.values():
        if war_value is not Dictionary:
            continue
        var war: Dictionary = war_value
        if country_id in war.get("attackers", []) or country_id in war.get("defenders", []):
            return true
    return false


func _has_hostile_neighbor(state, province: Dictionary, country_id: String) -> bool:
    for neighbor_value in province.get("neighbors", []):
        var neighbor: Dictionary = state.provinces.get(int(neighbor_value), {})
        var controller_id := String(neighbor.get("controller_id", ""))
        if not controller_id.is_empty() and controller_id != country_id:
            return true
    return false


func _garrison_strength(state, province_id: int, country_id: String) -> int:
    var total := 0
    for army_value in state.armies.values():
        if army_value is not Dictionary:
            continue
        var army: Dictionary = army_value
        if int(army.get("province_id", -1)) == province_id \
                and String(army.get("owner_id", "")) == country_id:
            total += int(army.get("soldiers", 0))
    return total


func _append(
    result: Dictionary,
    severity: String,
    title: String,
    detail: String,
    action: Dictionary
) -> void:
    var entry := {
        "severity": severity,
        "title": title,
        "detail": detail,
        "action": action.duplicate(true),
    }
    result["items"].append(entry)
    match severity:
        SEVERITY_BLOCKING:
            result["blocking"].append(entry)
        SEVERITY_IMPORTANT:
            result["important"].append(entry)
        _:
            result["recommendations"].append(entry)
