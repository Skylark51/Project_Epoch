extends RefCounted
const StrategicMilitary=preload("res://src/systems/strategic_military_system.gd")
var strategic:=StrategicMilitary.new()
func resolve_attack(state,command:Dictionary)->Dictionary:
 var source:=int(command.source_id);var target:=int(command.target_id);var attacker:=_army_at(state,source,str(command.country_id));var defender_country:=str(state.provinces[target].controller_id);var defender:=_army_at(state,target,defender_country)
 if attacker.is_empty():return {"valid":false,"reason":"공격 군단이 없음"}
 if defender.is_empty():defender=strategic.create_corps("garrison_%d"%target,defender_country,target,[{"unit_id":"levy_infantry","strength":maxi(100,int(state.provinces[target].get("fort_level",0))*200),"training":0.35}])
 var context:={"command_id":str(command.command_id),"river_crossing":bool(command.get("payload",{}).get("river_crossing",false)),"siege":int(state.provinces[target].get("fort_level",0))>0}
 var result:=strategic.resolve_battle(state,attacker,defender,state.provinces[target],context);result.type="battle";result.attacker_id=command.country_id;result.defender_id=defender_country;result.province_id=target;result.attacker_loss=int(result.initial.attacker)-int(attacker.soldiers);result.defender_loss=int(result.initial.defender)-int(defender.soldiers)
 if result.attacker_wins and int(attacker.soldiers)>0:attacker.province_id=target;state.provinces[target].controller_id=command.country_id
 elif int(result.retreat_province_id)>=0:attacker.province_id=result.retreat_province_id
 if int(attacker.soldiers)<=0:state.armies.erase(str(attacker.army_id))
 if state.armies.has(str(defender.get("army_id",""))) and int(defender.soldiers)<=0:state.armies.erase(str(defender.army_id))
 _update_war_score(state,result);return result
func _army_at(state,province_id:int,country_id:String)->Dictionary:
 for army in state.armies.values():if int(army.province_id)==province_id and str(army.owner_id)==country_id:return army
 return {}
func _update_war_score(state,result:Dictionary)->void:
 for war in state.wars.values():
  if result.attacker_id in war.attackers and result.defender_id in war.defenders:war.score=float(war.get("score",0))+(5 if result.attacker_wins else -3)
  elif result.attacker_id in war.defenders and result.defender_id in war.attackers:war.score=float(war.get("score",0))+(-5 if result.attacker_wins else 3)