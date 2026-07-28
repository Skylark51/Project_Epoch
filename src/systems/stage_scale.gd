class_name EpochStageScale
extends RefCounted

const INFLUENCE := [
    {"id": "negligible", "name": "미약", "min": 0},
    {"id": "weak", "name": "약함", "min": 20},
    {"id": "ordinary", "name": "보통", "min": 40},
    {"id": "strong", "name": "강함", "min": 60},
    {"id": "overwhelming", "name": "압도적", "min": 80},
]

const SATISFACTION := [
    {"id": "furious", "name": "격렬한 반발", "min": 0},
    {"id": "discontent", "name": "불만", "min": 20},
    {"id": "neutral", "name": "중립", "min": 40},
    {"id": "satisfied", "name": "만족", "min": 60},
    {"id": "supportive", "name": "적극 지지", "min": 80},
]

const REBELLION_RISK := [
    {"id": "stable", "name": "안정", "min": 0},
    {"id": "watch", "name": "주의", "min": 20},
    {"id": "unrest", "name": "불안", "min": 40},
    {"id": "danger", "name": "위험", "min": 60},
    {"id": "imminent", "name": "임박", "min": 80},
]

const CONTROL := [
    {"id": "unsecured", "name": "미확보", "min": 0},
    {"id": "foothold", "name": "교두보", "min": 15},
    {"id": "contested", "name": "분쟁", "min": 35},
    {"id": "advantage", "name": "우세", "min": 55},
    {"id": "de_facto", "name": "사실상 장악", "min": 75},
    {"id": "full_control", "name": "완전 통제", "min": 95},
]

const PROXIMITY := [
    {"id": "far", "name": "멀음", "min": 0},
    {"id": "moving", "name": "진행 중", "min": 20},
    {"id": "over_half", "name": "절반 이상", "min": 45},
    {"id": "near", "name": "임박", "min": 70},
    {"id": "next_turn", "name": "다음 턴 변동 가능", "min": 90},
]

static func clamp_hidden(value: float) -> float:
    return clampf(value, 0.0, 100.0)

static func stage(value: float, scale: Array) -> Dictionary:
    var result: Dictionary = scale.front()
    for entry in scale:
        if value >= float(entry.get("min", 0.0)):
            result = entry
        else:
            break
    return result.duplicate(true)

static func stage_id(value: float, scale: Array) -> String:
    return String(stage(value, scale).get("id", ""))

static func stage_name(value: float, scale: Array) -> String:
    return String(stage(value, scale).get("name", ""))

static func next_stage(value: float, scale: Array) -> Dictionary:
    for entry in scale:
        if float(entry.get("min", 0.0)) > value:
            return entry.duplicate(true)
    return {}

static func proximity_to_next_stage(value: float, scale: Array) -> Dictionary:
    var current := stage(value, scale)
    var upcoming := next_stage(value, scale)
    if upcoming.is_empty():
        return {"id": "maximum", "name": "최고 단계", "percent": 100.0}

    var current_min := float(current.get("min", 0.0))
    var next_min := float(upcoming.get("min", 100.0))
    var span := maxf(next_min - current_min, 1.0)
    var percent := clamp_hidden(((value - current_min) / span) * 100.0)
    var proximity := stage(percent, PROXIMITY)
    return {
        "id": proximity.get("id", "far"),
        "name": proximity.get("name", "멀음"),
        "percent": percent,
        "next_stage_id": upcoming.get("id", ""),
        "next_stage_name": upcoming.get("name", ""),
    }

static func direction(delta: float) -> String:
    if delta >= 6.0:
        return "급격히 상승"
    if delta >= 1.0:
        return "상승"
    if delta <= -6.0:
        return "급격히 하락"
    if delta <= -1.0:
        return "하락"
    return "유지"
