class_name StrategyCommandMapper
extends RefCounted


## Translates player-facing command names into the core command protocol.
##
## This class deliberately contains no game state and no side effects. A caller
## gives it a command, payload, and acting country; it returns the exact command
## envelope expected by GameSession.
static func build(
    command_type: String,
    payload: Dictionary,
    player_country_id: String
) -> Dictionary:
    var core_type := command_type
    var values: Dictionary = {"country_id": player_country_id}

    match command_type:
        "recruit":
            values["target_id"] = int(payload.get("province_id", -1))
            values["amount"] = int(payload.get("amount", 0))

        "move", "attack":
            values["source_id"] = int(payload.get("from_id", -1))
            values["target_id"] = int(payload.get("to_id", -1))
            values["amount"] = int(payload.get("amount", 0))
            values["payload"] = {
                "leave_garrison": int(payload.get("leave_garrison", 1))
            }

        "develop":
            values["target_id"] = int(payload.get("province_id", -1))

        "fortify":
            core_type = "build_fort"
            values["target_id"] = int(payload.get("province_id", -1))

        "declare_war", "improve_relations":
            values["target_id"] = String(payload.get("target_country_id", ""))

        "offer_alliance":
            core_type = "form_alliance"
            values["target_id"] = String(payload.get("target_country_id", ""))

        "demand_vassalization":
            core_type = "create_vassal"
            values["target_id"] = String(payload.get("target_country_id", ""))

        "peace_offer":
            core_type = "offer_peace"
            values["target_id"] = String(payload.get("target_country_id", ""))
            values["payload"] = {
                "terms": {
                    "province_ids": payload.get("province_demands", []).duplicate(),
                    "reparations": float(payload.get("reparations", 0)),
                    "vassalize": bool(payload.get("vassalize", false)),
                    "recognize_independence": bool(
                        payload.get("recognize_independence", false)
                    )
                }
            }

        _:
            return {}

    return {
        "type": core_type,
        "values": values
    }
