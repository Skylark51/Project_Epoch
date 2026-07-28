extends SceneTree
const GameSession=preload("res://src/core/game_session.gd")
const Strategic=preload("res://src/systems/strategic_military_system.gd")
var failed:Array[String]=[]
func check(ok:bool,msg:String)->void:
 if ok:print("PASS: ",msg)
 else:failed.append(msg);push_error("FAIL: "+msg)
func _init()->void:call_deferred("run")
func run()->void:
 var game:=GameSession.new();var start:Dictionary=game.start_scenario("res://data/scenarios/sample_campaign.json","AUR");check(start.ok,"scenario loads");var sys:=Strategic.new();check(sys.unit_types.size()>=26,"all unit types load")
 var army:Dictionary=game.state.armies.values()[0];sys.migrate_army(army);check(army.units.size()>=3,"legacy army migrates to corps composition");var before:=int(army.soldiers);var split:Dictionary=sys.split_corps(game.state,str(army.army_id),0.4);check(split.valid,"corps split");var merged:Dictionary=sys.merge_corps(game.state,[army.army_id,split.new_id]);check(merged.valid and int(army.soldiers)==before,"split and merge conserve manpower")
 var defender:=sys.create_corps("test_def","BOR",4,[{"unit_id":"spearman","strength":800,"training":0.5},{"unit_id":"archer","strength":300,"training":0.5}]);var plain:Dictionary=game.state.provinces[2].duplicate(true);plain.terrain="plains";var mountain:=plain.duplicate(true);mountain.terrain="mountain";var a1:=army.duplicate(true);var d1:=defender.duplicate(true);var r1:=sys.resolve_battle(game.state,a1,d1,plain,{"command_id":"same"});var a2:=army.duplicate(true);var d2:=defender.duplicate(true);var r2:=sys.resolve_battle(game.state,a2,d2,plain,{"command_id":"same"});check(r1.power==r2.power and r1.losses==r2.losses,"seeded battle is reproducible");var a3:=army.duplicate(true);var d3:=defender.duplicate(true);var rm:=sys.resolve_battle(game.state,a3,d3,mountain,{"command_id":"same"});check(rm.power!=r1.power,"terrain changes battle result");check(r1.has("decisive_factor") and r1.losses.attacker is Dictionary,"battle explanation includes factors and per-unit losses")
 var siege:Dictionary=sys.start_siege(game.state,str(army.army_id),4,"breach_gate");check(siege.valid,"siege starts");var siege_logs:=sys.process_sieges(game.state);check(game.state.metadata.sieges.has(siege.siege_id),"siege state persists");game.state.armies.erase(str(army.army_id));siege_logs=sys.process_sieges(game.state);check(not game.state.metadata.sieges[siege.siege_id].active,"siege cancels when besieger disappears")
 var reason:Dictionary=sys.ai_reason(game.state,"AUR");check(reason.has("code"),"AI decision leaves reason code")
 for turn in range(100):game.state.turn=turn+1;sys.update_supply(game.state);sys.process_sieges(game.state);for item in game.state.armies.values():check(int(item.get("soldiers",0))>=0 and is_finite(float(item.get("supply",0))),"turn %d invariants"%(turn+1))
 check(true,"100-turn military simulation completes")
 if failed.is_empty():print("ALL STRATEGIC MILITARY TESTS PASSED");quit(0)
 else:print(failed);quit(1)