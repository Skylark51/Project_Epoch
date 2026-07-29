class_name TurnEndGuard
extends RefCounted

signal validation_changed(report: Dictionary)

const BLOCKING_TYPES := [
    "expiring_diplomatic_offer", "mandatory_succession", "capital_fall",
    "state_collapse", "mandatory_rebellion_decision", "mandatory_political_event",
    "mandatory_scenario_event", "core_army_without_orders"
]
const WARNING_TYPES := [
    "empty_construction_queue", "occupied_policy_missing", "food_decline",
    "happiness_decline", "stability_decline", "unused_resources",
    "idle_regular_unit", "minor_diplomatic_opportunity", "minor_trade_opportunity"
]

var pending_items: Array[Dictionary] = []
var ignored_this_turn: Dictionary = {}
var notification_center: NotificationCenter


func bind(center: NotificationCenter) -> void:
    notification_center = center
    if not center.notification_added.is_connected(_on_notification_change):
        center.notification_added.connect(_on_notification_change)
    if not center.notification_updated.is_connected(_on_notification_updated):
        center.notification_updated.connect(_on_notification_updated)


func set_pending_items(items: Array) -> void:
    pending_items.clear()
    for value in items:
        if value is Dictionary:
            pending_items.append(_normalize(value))
    _emit_changed()


func upsert_item(value: Dictionary) -> void:
    var item := _normalize(value)
    var id := String(item.id)
    for index in range(pending_items.size()):
        if String(pending_items[index].id) == id:
            pending_items[index] = item
            _emit_changed()
            return
    pending_items.append(item)
    _emit_changed()


func resolve_item(id: String) -> bool:
    for index in range(pending_items.size()):
        if String(pending_items[index].id) == id:
            pending_items.remove_at(index)
            ignored_this_turn.erase(id)
            _emit_changed()
            return true
    return false


func ignore_for_turn(id: String) -> bool:
    for item in pending_items:
        if String(item.id) == id and not bool(item.blocking):
            ignored_this_turn[id] = true
            _emit_changed()
            return true
    return false


func clear_turn_ignores() -> void:
    ignored_this_turn.clear()
    _emit_changed()


func validate() -> Dictionary:
    var blockers: Array[Dictionary] = []
    var warnings: Array[Dictionary] = []
    for item in pending_items:
        if bool(item.get("resolved", false)) or bool(item.get("auto_governed", false)):
            continue
        var id := String(item.id)
        if ignored_this_turn.has(id) and not bool(item.blocking):
            continue
        if bool(item.blocking):
            blockers.append(item.duplicate(true))
        else:
            warnings.append(item.duplicate(true))
    if notification_center != null:
        for decision in notification_center.pending_decisions():
            if bool(decision.get("auto_governed", false)):
                continue
            blockers.append({
                "id": "notification:%d" % int(decision.id),
                "type": String(decision.kind),
                "title": String(decision.title),
                "message": String(decision.message),
                "blocking": true,
                "target": decision.get("target", {}).duplicate(true),
                "notification_id": int(decision.id),
                "count": int(decision.get("repeat_count", 1))
            })
    return {
        "can_end_turn": blockers.is_empty(),
        "blockers": _group(blockers),
        "warnings": _group(warnings),
        "blocker_count": blockers.size(),
        "warning_count": warnings.size()
    }


func has_blockers() -> bool:
    return not bool(validate().can_end_turn)


func blocking_reason() -> String:
    var report := validate()
    if bool(report.can_end_turn):
        return ""
    return "필수 결정 %d건을 먼저 해결해야 합니다." % int(report.blocker_count)


func _normalize(value: Dictionary) -> Dictionary:
    var type := String(value.get("type", "general"))
    var blocking := bool(value.get("blocking", type in BLOCKING_TYPES))
    if type in WARNING_TYPES:
        blocking = false
    return {
        "id": String(value.get("id", "%s:%s" % [type, str(pending_items.size())])),
        "type": type,
        "title": String(value.get("title", _type_name(type))),
        "message": String(value.get("message", "")),
        "blocking": blocking,
        "auto_governed": bool(value.get("auto_governed", false)),
        "resolved": bool(value.get("resolved", false)),
        "target": value.get("target", {}).duplicate(true),
        "count": int(value.get("count", 1))
    }


func _group(items: Array[Dictionary]) -> Array[Dictionary]:
    var groups := {}
    var order: Array[String] = []
    for item in items:
        var key := String(item.type)
        if not groups.has(key):
            groups[key] = item.duplicate(true)
            groups[key].ids = [String(item.id)]
            groups[key].count = int(item.get("count", 1))
            order.append(key)
        else:
            groups[key].ids.append(String(item.id))
            groups[key].count = int(groups[key].count) + int(item.get("count", 1))
    var result: Array[Dictionary] = []
    for key in order:
        result.append(groups[key])
    return result


func _type_name(type: String) -> String:
    return {
        "expiring_diplomatic_offer": "응답 기한이 끝나는 외교 제안",
        "mandatory_succession": "필수 계승·섭정 결정",
        "capital_fall": "수도 함락 위험",
        "state_collapse": "국가 붕괴 위험",
        "mandatory_rebellion_decision": "즉시 반란 결정",
        "mandatory_political_event": "즉시 정치 결정",
        "mandatory_scenario_event": "필수 시나리오 사건",
        "core_army_without_orders": "핵심 군단 명령 누락",
        "empty_construction_queue": "빈 건설 대기열",
        "occupied_policy_missing": "신규 점령지 정책 미지정",
        "food_decline": "식량 악화",
        "happiness_decline": "행복도 악화",
        "stability_decline": "안정도 악화",
        "unused_resources": "사용하지 않은 자원",
        "idle_regular_unit": "이동하지 않은 일반 부대",
        "minor_diplomatic_opportunity": "경미한 외교 기회",
        "minor_trade_opportunity": "경미한 교역 기회"
    }.get(type, type)


func _on_notification_change(_item: Dictionary, _channels: Dictionary) -> void:
    _emit_changed()


func _on_notification_updated(_item: Dictionary) -> void:
    _emit_changed()


func _emit_changed() -> void:
    validation_changed.emit(validate())
