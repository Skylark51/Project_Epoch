extends RefCounted

const Loader=preload("res://src/data/data_loader.gd")
var unit_types:Dictionary={}
var path_cache:Dictionary={}

func _init()->void:
 for item in Loader.load_array("res://data/military/unit_types.json","units"): unit_types[str(item.unit_id)]=item

func migrate_army(army:Dictionary)->Dictionary:
 if army.has("units"): return army
 var total:=maxi(0,int(army.get("soldiers",0)))
 army.units=[{"unit_id":"spearman","strength":int(total*0.55),"training":0.55},{"unit_id":"archer","strength":int(total*0.25),"training":0.5},{"unit_id":"levy_infantry","strength":total-int(total*0.8),"training":0.35}]
 army.commander=army.get("commander",{});army.morale=float(army.get("morale",0.7));army.fatigue=float(army.get("fatigue",0));army.supply=float(army.get("supply",1));army.movement_points=float(army.get("movement_points",1));army.stance=str(army.get("stance","balanced"));army.current_order=army.get("current_order",{});army.home_region=int(army.get("province_id",-1));army.reinforcement_source=army.get("reinforcement_source",army.home_region)
 _sync_manpower(army);return army

func create_corps(id:String,owner:String,province_id:int,units:Array,commander:Dictionary={})->Dictionary:
 var army={"id":id,"army_id":id,"owner_id":owner,"province_id":province_id,"units":units.duplicate(true),"commander":commander.duplicate(true),"morale":0.7,"fatigue":0.0,"supply":1.0,"movement_points":1.0,"stance":"balanced","current_order":{},"home_region":province_id,"reinforcement_source":province_id,"organization":1.0,"commander_bonus":0.0}
 _sync_manpower(army);return army

func split_corps(state,army_id:String,ratio:float)->Dictionary:
 if not state.armies.has(army_id) or ratio<=0.05 or ratio>=0.95:return {"valid":false,"reason":"분할 비율 오류"}
 var source:Dictionary=migrate_army(state.armies[army_id]);var parts:Array=[]
 for unit in source.units:
  var moved:=int(float(unit.strength)*ratio);unit.strength-=moved;parts.append({"unit_id":unit.unit_id,"strength":moved,"training":unit.get("training",0.5)})
 var new_id:="%s_split_%d"%[army_id,state.armies.size()+1];state.armies[new_id]=create_corps(new_id,source.owner_id,int(source.province_id),parts,source.commander);_sync_manpower(source)
 return {"valid":true,"source_id":army_id,"new_id":new_id}

func merge_corps(state,ids:Array)->Dictionary:
 if ids.size()<2:return {"valid":false,"reason":"두 군단 이상 필요"}
 var target:Dictionary=migrate_army(state.armies.get(str(ids[0]),{}));if target.is_empty():return {"valid":false,"reason":"군단 없음"}
 var total_before:=0
 for id in ids: total_before+=int(migrate_army(state.armies.get(str(id),{})).get("soldiers",0))
 for index in range(1,ids.size()):
  var other:Dictionary=migrate_army(state.armies.get(str(ids[index]),{}));if other.is_empty() or other.owner_id!=target.owner_id or other.province_id!=target.province_id:continue
  for unit in other.units:_add_unit(target.units,str(unit.unit_id),int(unit.strength),float(unit.get("training",0.5)))
  state.armies.erase(str(ids[index]))
 _sync_manpower(target);return {"valid":int(target.soldiers)==total_before,"army_id":target.army_id,"manpower":target.soldiers}

func resolve_battle(state,attacker:Dictionary,defender:Dictionary,province:Dictionary,context:Dictionary={})->Dictionary:
 attacker=migrate_army(attacker);defender=migrate_army(defender)
 var seed: int=absi(int(state.random_seed)*1000003+int(state.turn)*10007+int(province.id)*509+str(context.get("command_id","")).hash());var rng:=RandomNumberGenerator.new();rng.seed=seed
 var terrain:=str(province.get("terrain","plains"));var attack_detail:=_power(attacker,terrain,false,context);var defense_detail:=_power(defender,terrain,true,context)
 var wall:=1.0+float(province.get("fort_level",0))*0.18 if bool(context.get("siege",false)) else 1.0;defense_detail.total*=wall
 attack_detail.total*=rng.randf_range(0.94,1.06);defense_detail.total*=rng.randf_range(0.94,1.06)
 var attacker_wins:bool=attack_detail.total>defense_detail.total;var ratio:=clampf(defense_detail.total/maxf(1.0,attack_detail.total),0.2,2.0)
 var attacker_loss:=mini(int(attacker.soldiers),maxi(1,int(float(defender.soldiers)*0.12*ratio)));var defender_loss:=mini(int(defender.soldiers),maxi(1,int(float(attacker.soldiers)*0.15/maxf(ratio,0.2))))
 var a_loss:=_apply_losses(attacker,attacker_loss);var d_loss:=_apply_losses(defender,defender_loss);attacker.morale=clampf(float(attacker.morale)+(0.08 if attacker_wins else -0.18),0,1);defender.morale=clampf(float(defender.morale)+(-0.18 if attacker_wins else 0.08),0,1);attacker.fatigue=clampf(float(attacker.fatigue)+0.18,0,1);defender.fatigue=clampf(float(defender.fatigue)+0.16,0,1)
 var retreat:=-1
 if attacker_wins:retreat=_retreat_target(state,int(province.id),str(defender.owner_id))
 else:retreat=_retreat_target(state,int(attacker.province_id),str(attacker.owner_id))
 var factors:Array=attack_detail.factors+defense_detail.factors;if wall>1.0:factors.append("성벽 방어 +%d%%"%int((wall-1.0)*100))
 return {"valid":true,"seed":seed,"attacker_wins":attacker_wins,"initial":{"attacker":attacker.soldiers+attacker_loss,"defender":defender.soldiers+defender_loss},"losses":{"attacker":a_loss,"defender":d_loss},"morale":{"attacker":attacker.morale,"defender":defender.morale},"power":{"attacker":attack_detail.total,"defender":defense_detail.total},"factors":factors,"decisive_factor":_decisive(attack_detail,defense_detail,terrain),"prisoners":int((defender_loss if attacker_wins else attacker_loss)*0.08),"loot":int(province.get("economy",0))*2,"commander_xp":maxi(1,int((attacker_loss+defender_loss)*0.01)),"retreat_province_id":retreat}

func update_supply(state)->Array:
 var logs:Array=[];var sources:Dictionary={}
 for pid in state.provinces:
  var p:Dictionary=state.provinces[pid];if bool(p.get("capital",false)) or int(p.get("fort_level",0))>0 or bool(p.get("port",false)):sources[int(pid)]=str(p.owner_id)
 for army in state.armies.values():
  migrate_army(army);var distance:=_nearest_supply_distance(state,int(army.province_id),str(army.owner_id),sources);var capacity:=maxf(0.0,1.0-float(distance)*0.16);var use:=_supply_use(army);army.supply=clampf(capacity-use/10000.0,0,1)
  if army.supply<0.35:army.morale=clampf(float(army.morale)-0.08,0,1);army.fatigue=clampf(float(army.fatigue)+0.12,0,1);_apply_losses(army,maxi(1,int(army.soldiers*0.01)));logs.append({"type":"supply_shortage","army_id":army.army_id,"distance":distance,"supply":army.supply})
 return logs

func start_siege(state,army_id:String,province_id:int,method:String="encircle")->Dictionary:
 var army:Dictionary=state.armies.get(army_id,{});if army.is_empty():return {"valid":false,"reason":"공성 군단 없음"}
 var sieges:Dictionary=state.metadata.get("sieges",{});var id:="siege_%s_%d"%[army_id,province_id];sieges[id]={"id":id,"army_id":army_id,"province_id":province_id,"attacker_id":army.owner_id,"method":method,"progress":0.0,"wall":100.0,"food":float(state.provinces[province_id].get("food_storage",100)),"active":true,"turns":0};state.metadata.sieges=sieges;return {"valid":true,"siege_id":id}

func process_sieges(state)->Array:
 var logs:Array=[];var sieges:Dictionary=state.metadata.get("sieges",{})
 for id in sieges.keys():
  var siege:Dictionary=sieges[id];if not bool(siege.active):continue
  if not state.armies.has(str(siege.army_id)):siege.active=false;logs.append({"type":"siege_cancelled","reason":"army_missing","siege_id":id});continue
  var army:Dictionary=migrate_army(state.armies[str(siege.army_id)]);var power:float=_siege_power(army)*maxf(0.2,float(army.supply));var method_mod:float=float({"assault":1.8,"breach_gate":1.4,"undermine":1.3,"fire":1.25,"blockade":0.8,"negotiate":0.5}.get(str(siege.method),1.0));siege.progress=clampf(float(siege.progress)+power*float(method_mod)*0.02,0,100);siege.wall=maxf(0,float(siege.wall)-power*float(method_mod)*0.012);siege.food=maxf(0,float(siege.food)-5.0);siege.turns=int(siege.turns)+1
  if siege.progress>=100 or siege.food<=0:state.provinces[int(siege.province_id)].controller_id=siege.attacker_id;siege.active=false;logs.append({"type":"siege_won","siege_id":id,"turns":siege.turns,"method":siege.method})
 return logs

func ai_reason(state,country_id:String)->Dictionary:
 var capital:=-1;for pid in state.provinces:if str(state.provinces[pid].owner_id)==country_id and bool(state.provinces[pid].get("capital",false)):capital=int(pid)
 for army in state.armies.values():if str(army.owner_id)==country_id and float(army.get("supply",1))<0.3:return {"code":"BREAK_ENEMY_SUPPLY","action":"retreat","army_id":army.army_id}
 if capital!=-1:
  for n in state.provinces[capital].neighbors:if str(state.provinces[int(n)].controller_id)!=country_id:return {"code":"DEFEND_CAPITAL","action":"defend","province_id":capital}
 return {"code":"AVOID_MULTI_FRONT_WAR" if state.wars.size()>1 else "TARGET_WEAK_BORDER_CITY","action":"hold" if state.wars.size()>1 else "attack"}

func _power(army:Dictionary,terrain:String,defending:bool,context:Dictionary)->Dictionary:
 var total:=0.0;var factors:Array=[]
 for unit in army.units:
  var data:Dictionary=unit_types.get(str(unit.unit_id),{});var strength:=float(unit.strength);var base:=float(data.get("attack",1))+float(data.get("ranged_attack",0))*0.55 if not defending else float(data.get("defense",1))+float(data.get("armor",0))*0.5;var mod:=float(data.get("terrain_modifiers",{}).get(terrain,1.0));total+=strength*base*mod*(0.65+float(unit.get("training",0.5))*0.7)
  if absf(mod-1.0)>0.05:factors.append("%s 지형 보정 %+.0f%%"%[data.get("name",unit.unit_id),(mod-1.0)*100])
 var commander:Dictionary=army.get("commander",{});var command_mod:=1.0+(float(commander.get("leadership",0))*0.02 if not commander.is_empty() else -0.1);var morale_mod:=0.5+float(army.morale)*0.7;var fatigue_mod:=1.0-float(army.fatigue)*0.45;var supply_mod:=0.55+float(army.supply)*0.45
 if commander.is_empty():factors.append("지휘관 부재 -10%")
 if float(army.supply)<0.5:factors.append("보급 부족")
 if bool(context.get("river_crossing",false)) and not defending:total*=0.72;factors.append("도하 공격 -28%")
 return {"total":total*command_mod*morale_mod*fatigue_mod*supply_mod,"factors":factors}

func _apply_losses(army:Dictionary,loss:int)->Dictionary:
 var remaining:=loss;var result:Dictionary={}
 for unit in army.units:
  if remaining<=0:break
  var take:=mini(int(unit.strength),int(ceil(float(loss)*float(unit.strength)/maxf(1.0,float(army.soldiers)))));unit.strength-=take;remaining-=take;result[str(unit.unit_id)]=take
 _sync_manpower(army);return result
func _sync_manpower(army:Dictionary)->void:
 var total:=0;for unit in army.get("units",[]):total+=maxi(0,int(unit.get("strength",0)));army.soldiers=total;army.manpower=total
func _add_unit(units:Array,id:String,strength:int,training:float)->void:
 for unit in units:if str(unit.unit_id)==id:unit.strength+=strength;unit.training=(float(unit.training)+training)*0.5;return
 units.append({"unit_id":id,"strength":strength,"training":training})
func _supply_use(army:Dictionary)->float:
 var total:=0.0
 for unit in army.units: total+=float(unit.strength)*float(unit_types.get(str(unit.unit_id),{}).get("supply_use",1))
 return total
func _siege_power(army:Dictionary)->float:
 var total:=0.0
 for unit in army.units: total+=float(unit.strength)/100.0*float(unit_types.get(str(unit.unit_id),{}).get("siege_power",0))
 return total
func _nearest_supply_distance(state,start:int,owner:String,sources:Dictionary)->int:
 var key:="%d|%s|%d"%[start,owner,state.turn]
 if path_cache.has(key): return int(path_cache[key])
 var queue:Array=[[start,0]]
 var seen:Dictionary={start:true}
 while not queue.is_empty():
  var current:Array=queue.pop_front()
  if sources.get(int(current[0]),"")==owner: path_cache[key]=int(current[1]);return int(current[1])
  for n in state.provinces[int(current[0])].neighbors:
   if not seen.has(int(n)) and str(state.provinces[int(n)].controller_id)==owner: seen[int(n)]=true;queue.append([int(n),int(current[1])+1])
 path_cache[key]=99
 return 99
func _retreat_target(state,from_id:int,owner:String)->int:
 for n in state.provinces[from_id].neighbors:if str(state.provinces[int(n)].controller_id)==owner:return int(n)
 return -1
func _decisive(a:Dictionary,d:Dictionary,terrain:String)->String:
 if terrain in ["mountain","pass"]:return "지형과 방어선"
 if a.total>d.total*1.5:return "공격군 전투력 우세"
 if d.total>a.total*1.5:return "방어군 전투력 우세"
 return "사기·보급·지휘의 종합 차이"
