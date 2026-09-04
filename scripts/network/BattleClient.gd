extends Node

signal state_changed(data)
signal error(message)
signal connection_changed(connected)

var match_id:String = ""
var lobby_id:String = ""
var match_data:Dictionary = {}
var lobby_data:Dictionary = {}
var running:bool = false
var _poll_accum:float = 0.0
var _heartbeat_accum:float = 0.0
var _last_error:String = ""

func start():
	running = true
	_poll_accum = 0.0
	_heartbeat_accum = 0.0

func stop():
	running = false
	if match_id != "":
		battle_action("disconnect")

func _process(delta:float):
	if not running:
		return
	_poll_accum += delta
	_heartbeat_accum += delta
	if _poll_accum >= 1.0:
		_poll_accum = 0.0
		if match_id != "":
			refresh_match()
		if lobby_id != "":
			refresh_lobby()
	if _heartbeat_accum >= 5.0:
		_heartbeat_accum = 0.0
		if match_id != "":
			battle_action("heartbeat")

func queue_match(mode:String, match_type:String) -> Dictionary:
	var result = yield(Rhythian._api_request(HTTPClient.METHOD_POST,"/api/battles/matches",{"action":"queue","mode":mode,"matchType":match_type,"teamMode":"regular"},true,25.0),"completed")
	return _finish_result(result,"battle matchmaking")

func refresh_match() -> Dictionary:
	if match_id == "":
		return {}
	var result = yield(Rhythian._api_request(HTTPClient.METHOD_GET,"/api/battles/matches?id="+match_id.http_escape(),null,true,15.0),"completed")
	var finished = _finish_result(result,"battle status")
	if finished.get("ok",false):
		match_data = finished
		emit_signal("state_changed",match_data)
	else:
		emit_signal("error",finished.get("message","Battle status failed"))
	return finished

func battle_action(action:String, extra:Dictionary={}) -> Dictionary:
	if match_id == "":
		return {"ok":false,"message":"No active battle."}
	var body = {"action":action,"matchId":match_id}
	for key in extra.keys():
		body[key] = extra[key]
	var result = yield(Rhythian._api_request(HTTPClient.METHOD_POST,"/api/battles/matches",body,true,25.0),"completed")
	var finished = _finish_result(result,"battle action")
	if finished.get("ok",false) and action != "heartbeat":
		refresh_match()
	return finished

func create_lobby(name:String, mode:String, match_type:String, team_mode:String="regular") -> Dictionary:
	var result = yield(Rhythian._api_request(HTTPClient.METHOD_POST,"/api/battles/lobbies",{"name":name,"mode":mode,"matchType":match_type,"teamMode":team_mode},true,25.0),"completed")
	var finished = _finish_result(result,"lobby creation")
	if finished.get("ok",false):
		lobby_id = str(finished.get("lobbyId",""))
		refresh_lobby()
	return finished

func list_lobbies() -> Dictionary:
	var result = yield(Rhythian._api_request(HTTPClient.METHOD_GET,"/api/battles/lobbies",null,true,15.0),"completed")
	return _finish_result(result,"lobby list")

func refresh_lobby() -> Dictionary:
	if lobby_id == "":
		return {}
	var result = yield(Rhythian._api_request(HTTPClient.METHOD_GET,"/api/battles/lobbies/"+lobby_id.http_escape(),null,true,15.0),"completed")
	var finished = _finish_result(result,"lobby status")
	if finished.get("ok",false):
		lobby_data = finished
		emit_signal("state_changed",lobby_data)
	else:
		emit_signal("error",finished.get("message","Lobby status failed"))
	return finished

func lobby_action(action:String, extra:Dictionary={}) -> Dictionary:
	if lobby_id == "":
		return {"ok":false,"message":"No active lobby."}
	var body = {"action":action}
	for key in extra.keys():
		body[key] = extra[key]
	var result = yield(Rhythian._api_request(HTTPClient.METHOD_PATCH,"/api/battles/lobbies/"+lobby_id.http_escape(),body,true,25.0),"completed")
	var finished = _finish_result(result,"lobby action")
	if finished.get("ok",false):
		if finished.has("matchId"):
			match_id = str(finished.get("matchId",""))
		refresh_lobby()
	return finished

func _finish_result(result:Dictionary, what:String) -> Dictionary:
	if result.get("ok",false):
		var body = result.get("json",{})
		if typeof(body) == TYPE_DICTIONARY:
			body["ok"] = true
			return body
		return {"ok":true,"data":body}
	var message = Rhythian._http_error_message(result,what)
	_last_error = message
	emit_signal("error",message)
	if int(result.get("code",0)) == 401:
		emit_signal("connection_changed",false)
	return {"ok":false,"message":message,"code":int(result.get("code",0))}

func _notification(what:int):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST and match_id != "":
		battle_action("disconnect")
