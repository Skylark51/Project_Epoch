extends RefCounted
const Loader=preload("res://src/data/data_loader.gd")
func start()->Dictionary:
 var data:Dictionary=Loader.load_dictionary("res://data/tutorial/silla_gaya.json");return {"tutorial_id":data.get("id",""),"current":0,"steps":data.get("steps",[]).duplicate(true),"completed":false}
func record_action(state:Dictionary,action:String)->Dictionary:
 if bool(state.get("completed",false)):return {"advanced":false,"completed":true}
 var index:=int(state.get("current",0));var steps:Array=state.get("steps",[])
 if index>=steps.size() or str(steps[index].action)!=action:return {"advanced":false,"expected":steps[index].action if index<steps.size() else ""}
 steps[index].completed=true;state.current=index+1;state.completed=state.current>=steps.size();return {"advanced":true,"completed":state.completed,"next":steps[state.current].action if not state.completed else ""}