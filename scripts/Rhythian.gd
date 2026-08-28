extends Node

signal connection_checked(website_ok, database_ok)
signal auth_changed
signal login_started(user_code, verification_url)
signal login_finished(success, message)
signal profile_updated
signal maps_updated(success, message)
signal completions_updated(success, message)
signal scores_updated(success, message)
signal download_progress(map_id, received, total)
signal map_downloaded(map_id, success, message)
signal score_submitted(success, message)

const DEFAULT_BASE_URL = "https://rhythians.vercel.app"
const MAP_DIR = "user://maps/rhythian maps"
const REGISTRY_FILE = "user://maps/rhythian maps/rhythian_maps.json"
const AUTH_FILE = "user://rhythian/auth.json"
const QUEUE_FILE = "user://rhythian/score_queue.json"
const INTEGRATION_VERSION = "rhythian-client-1"

var base_url:String = DEFAULT_BASE_URL

var token:String = ""
var installation_id:String = ""
var user_id:String = ""
var username:String = ""
var logged_in:bool = false

var website_ok:bool = false
var database_ok:bool = false

var profile:Dictionary = {}
var maps_cache:Array = []
var scores_cache:Array = []
var completions_cache:Dictionary = {}
var rhythian_stats:Dictionary = {"completed": 0, "total": 0, "rhp": 0}
var maps_error:String = ""
var scores_error:String = ""
var completions_error:String = ""
var completions_embedded:bool = false
var catalog_loading:bool = false
var profile_limited:bool = false

var registry:Dictionary = {}

var device_code:String = ""
var device_expiry:int = 0

var dl_req:HTTPRequest = null
var dl_map_id:String = ""
var downloading:bool = false

const RANKS = [
	{"name":"Copper","minRhp":0,"color":"#b87333","rangeMin":0.0,"rangeMax":1.09},
	{"name":"Bronze","minRhp":500,"color":"#cd7f32","rangeMin":1.1,"rangeMax":1.49},
	{"name":"Silver","minRhp":1000,"color":"#c0c0c0","rangeMin":1.5,"rangeMax":1.89},
	{"name":"Gold","minRhp":1500,"color":"#ffd700","rangeMin":1.9,"rangeMax":2.29},
	{"name":"Platinum","minRhp":2000,"color":"#7fd4ff","rangeMin":2.3,"rangeMax":2.69},
	{"name":"Emerald","minRhp":2500,"color":"#50c878","rangeMin":2.7,"rangeMax":2.99},
	{"name":"Diamond","minRhp":3000,"color":"#b9f2ff","rangeMin":3.0,"rangeMax":3.29},
	{"name":"Master","minRhp":3500,"color":"#a855f7","rangeMin":3.3,"rangeMax":3.69},
	{"name":"Expert","minRhp":4000,"color":"#f43f5e","rangeMin":3.7,"rangeMax":9.99},
]
const RANK_SPAN = 500
const RANK_TIERS = 5
const TIER_SPAN = 100
const MAP_RHP_FLOOR = 18.0
const MAP_RHP_CEILING = 25.0
const MAP_LENGTH_REFERENCE_SECONDS = 180.0
const RANK_LETTERS = ["C","B","S","G","P","E","D","M"]

func _ready():
	if ProjectSettings.has_setting("application/networking/rhythians_url"):
		var custom = str(ProjectSettings.get_setting("application/networking/rhythians_url")).strip_edges()
		if custom != "":
			while custom.ends_with("/"): custom = custom.left(custom.length() - 1)
			base_url = custom
	_ensure_dirs()
	_load_auth()
	_load_registry()
	if logged_in:
		refresh_status()
		_flush_score_queue()

func _process(_delta):
	if dl_req != null and is_instance_valid(dl_req):
		emit_signal("download_progress", dl_map_id, dl_req.get_downloaded_bytes(), dl_req.get_body_size())

func _ensure_dirs():
	var dir = Directory.new()
	dir.make_dir_recursive(Globals.p("user://rhythian"))
	dir.make_dir_recursive(Globals.p(MAP_DIR))

var last_rhp:int = -1

func _load_auth():
	var f = File.new()
	if not f.file_exists(Globals.p(AUTH_FILE)): return
	if f.open(Globals.p(AUTH_FILE), File.READ) != OK: return
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY: return
	token = str(parsed.result.get("token",""))
	installation_id = str(parsed.result.get("installationId",""))
	user_id = str(parsed.result.get("userId",""))
	username = str(parsed.result.get("username",""))
	last_rhp = int(parsed.result.get("rhp", -1))
	logged_in = token != ""
	if last_rhp >= 0:
		profile = {"rhp": last_rhp}
		if username != "": profile["username"] = username

func _save_auth():
	var f = File.new()
	if f.open(Globals.p(AUTH_FILE), File.WRITE) != OK: return
	f.store_string(JSON.print({
		"token": token, "installationId": installation_id,
		"userId": user_id, "username": username, "rhp": last_rhp
	}))
	f.close()

func logout():
	token = ""
	installation_id = ""
	user_id = ""
	username = ""
	logged_in = false
	profile = {}
	last_rhp = -1
	scores_cache = []
	var f = File.new()
	if f.file_exists(Globals.p(AUTH_FILE)):
		var dir = Directory.new()
		dir.remove(Globals.p(AUTH_FILE))
	emit_signal("auth_changed")

func _api_request(method:int, path:String, body=null, use_auth:bool=true, timeout:float=25.0) -> Dictionary:
	var hr = HTTPRequest.new()
	add_child(hr)
	hr.use_threads = true
	hr.timeout = timeout
	var headers = PoolStringArray([
		"Content-Type: application/json",
		"User-Agent: RhythianClient/" + str(ProjectSettings.get_setting("application/config/version"))
	])
	if use_auth and token != "":
		headers.append("Authorization: Bearer " + token)
	var data = ""
	if body != null:
		data = JSON.print(body)
	var err = hr.request(base_url + path, headers, true, method, data)
	if err != OK:
		hr.queue_free()
		return {"ok": false, "result": HTTPRequest.RESULT_CANT_CONNECT, "code": 0, "json": null, "text": ""}
	var res = yield(hr, "request_completed")
	hr.queue_free()
	var result:int = res[0]
	var code:int = res[1]
	var text:String = res[3].get_string_from_utf8()
	var parsed = JSON.parse(text)
	var json = null
	if parsed.error == OK:
		json = parsed.result
	return {
		"ok": result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300,
		"result": result, "code": code, "json": json, "text": text
	}

func _extract_array(j, preferred:Array) -> Array:
	if typeof(j) == TYPE_ARRAY:
		return j
	if typeof(j) != TYPE_DICTIONARY:
		return []
	for key in preferred:
		if not j.has(key):
			continue
		var v = j[key]
		if typeof(v) == TYPE_ARRAY:
			return v
		if typeof(v) == TYPE_DICTIONARY:
			for k2 in preferred:
				if v.has(k2) and typeof(v[k2]) == TYPE_ARRAY:
					return v[k2]
	for key in j.keys():
		var v = j[key]
		if typeof(v) == TYPE_ARRAY and v.size() > 0 and typeof(v[0]) == TYPE_DICTIONARY:
			var e = v[0]
			if e.has("id") or e.has("title") or e.has("name") or e.has("challengeMapId") or e.has("mapId"):
				return v
	return []

func _http_error_message(res:Dictionary, what:String) -> String:
	var code:int = int(res.get("code", 0))
	var result:int = int(res.get("result", -1))
	var j = res.get("json", null)
	var server_error = ""
	if typeof(j) == TYPE_DICTIONARY:
		for key in ["error", "message", "detail"]:
			if j.has(key) and str(j[key]) != "":
				server_error = str(j[key])
				break
	if result != HTTPRequest.RESULT_SUCCESS:
		match result:
			HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE:
				return "Could not reach the Rhythians website (check your internet connection)"
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, HTTPRequest.RESULT_SSL_HANDSHAKE_ERROR:
				return "Secure connection to the Rhythians website failed"
			HTTPRequest.RESULT_REQUEST_FAILED:
				return "The request to the Rhythians website failed (connection lost)"
			HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
				return "Could not save the response from the Rhythians website"
			HTTPRequest.RESULT_TIMEOUT:
				return "The Rhythians website took too long to respond (timeout)"
			_:
				return "Could not reach the Rhythians website (error %d)" % result
	match code:
		401:
			return "Your Rhythians session expired - sign in again."
		403:
			if server_error != "":
				return server_error
			return "The Rhythians server refused this request (HTTP 403)."
		404:
			return "%s is not available on the Rhythians website yet (HTTP 404)." % what.capitalize()
		422:
			if server_error != "":
				return server_error
			return "The Rhythians server rejected the request (HTTP 422)."
		429:
			return "The Rhythians server is rate limiting requests - try again in a moment (HTTP 429)."
		_:
			if code >= 500:
				return "The Rhythians server had an internal error (HTTP %d)." % code
			if server_error != "":
				return server_error
			return "The Rhythians server returned HTTP %d for %s." % [code, what]

func _handle_auth_failure(res:Dictionary) -> bool:
	if int(res.get("code", 0)) != 401:
		return false
	if not logged_in:
		return false
	logout()
	return true

func check_connection():
	var res = yield(_api_request(HTTPClient.METHOD_GET, "/api/health", null, false), "completed")
	var web_ok = res.get("ok", false)
	var db_ok = false
	var j = res.get("json", null)
	if web_ok and typeof(j) == TYPE_DICTIONARY:
		var dbv = str(j.get("database", "")).to_lower()
		db_ok = dbv == "connected" or dbv == "ok" or dbv == "up" or dbv == "true"
		if j.has("ok") and not bool(j.get("ok", false)):
			web_ok = false
			db_ok = false
	website_ok = web_ok
	database_ok = db_ok
	emit_signal("connection_checked", website_ok, database_ok)

func start_login():
	if device_code != "" and OS.get_unix_time() < device_expiry:
		return
	var res = yield(_api_request(HTTPClient.METHOD_POST, "/api/rhythkit/device/start", {}, false), "completed")
	var j = res.get("json", null)
	if not res.get("ok", false) or typeof(j) != TYPE_DICTIONARY:
		var msg = "Could not contact Rhythians"
		if typeof(j) == TYPE_DICTIONARY:
			msg = str(j.get("error", msg))
		emit_signal("login_finished", false, msg)
		return
	device_code = str(j.get("deviceCode", j.get("device_code", "")))
	device_expiry = OS.get_unix_time() + int(j.get("expiresIn", j.get("expires_in", 300)))
	var user_code = str(j.get("userCode", j.get("user_code", "")))
	var verify_url = str(j.get("verificationUrl", j.get("verification_uri", j.get("verificationUrlComplete", ""))))
	if device_code == "" or user_code == "":
		device_code = ""
		emit_signal("login_finished", false, "The Rhythians server returned an invalid login response")
		return
	emit_signal("login_started", user_code, verify_url)

func poll_login():
	if device_code == "": return
	if OS.get_unix_time() >= device_expiry:
		device_code = ""
		emit_signal("login_finished", false, "Login code expired - try again")
		return
	var res = yield(_api_request(HTTPClient.METHOD_POST, "/api/rhythkit/device/poll", {"deviceCode": device_code}, false), "completed")
	if not res.get("ok", false) or typeof(res.get("json")) != TYPE_DICTIONARY:
		return
	var j = res["json"]
	if bool(j.get("pending", false)):
		return
	var err = str(j.get("error", ""))
	if err == "authorization_pending" or err == "slow_down":
		return
	device_code = ""
	var authorized = bool(j.get("authorized", false))
	var new_token = str(j.get("token", j.get("access_token", "")))
	if authorized and new_token != "":
		token = new_token
		installation_id = str(j.get("installationId", j.get("installation_id", "")))
		user_id = str(j.get("userId", j.get("user_id", "")))
		username = str(j.get("username", ""))
		logged_in = token != ""
		_save_auth()
		emit_signal("login_finished", true, "")
		emit_signal("auth_changed")
		fetch_profile()
		fetch_maps()
		fetch_scores()
		_flush_score_queue()
	else:
		emit_signal("login_finished", false, str(j.get("error", j.get("message", "Login failed"))))

func cancel_login():
	device_code = ""

func refresh_status():
	if not logged_in: return
	var res = yield(_api_request(HTTPClient.METHOD_GET, "/api/rhythkit/status", null, true), "completed")
	if res.get("code", 0) == 401:
		logout()
		return
	if res.get("ok", false) and typeof(res.get("json")) == TYPE_DICTIONARY:
		if res["json"].has("ok") and not bool(res["json"].get("ok", false)):
			return
		username = str(res["json"].get("username", username))
		user_id = str(res["json"].get("userId", res["json"].get("user_id", user_id)))
		installation_id = str(res["json"].get("installationId", res["json"].get("installation_id", installation_id)))
		_save_auth()
		emit_signal("auth_changed")

func fetch_profile():
	if not logged_in:
		profile = {}
		profile_limited = false
		emit_signal("profile_updated")
		return
	var res = yield(_api_request(HTTPClient.METHOD_GET, "/api/rhythkit/profile", null, true), "completed")
	if res.get("code", 0) == 401:
		logout()
		emit_signal("profile_updated")
		return
	if res.get("ok", false) and typeof(res.get("json")) == TYPE_DICTIONARY:
		var j = res["json"]
		if j.has("ok") and not bool(j.get("ok", false)):
			emit_signal("profile_updated")
			return
		profile_limited = false
		var user = null
		for key in ["user", "profile", "data", "account", "me", "player"]:
			if user == null and j.has(key):
				var v = j[key]
				if typeof(v) == TYPE_DICTIONARY:
					user = v
		if user == null and (j.has("rhp") or j.has("RHP") or j.has("username") or j.has("rank") or j.has("rankName")):
			user = j
		if typeof(user) != TYPE_DICTIONARY:
			user = {}
		var norm = {}
		for k in user.keys():
			norm[str(k)] = user[k]
		var rhp_keys = ["rhp", "RHP", "totalRhp", "rankPoints", "rankpoints",
			"points", "score", "totalScore", "rhpPoints"]
		var found_rhp = null
		for rk in rhp_keys:
			if norm.has(rk) and str(norm[rk]) != "" and norm[rk] != null:
				var val = int(norm[rk])
				if val <= 1000000:
					found_rhp = val
					break
		if found_rhp != null:
			norm["rhp"] = found_rhp
		if norm.has("rank") and typeof(norm["rank"]) == TYPE_DICTIONARY:
			var rk = norm["rank"]
			for rkey in ["rhp", "RHP", "points", "rankPoints", "totalRhp"]:
				if rk.has(rkey) and str(rk[rkey]) != "":
					var val = int(rk[rkey])
					if val <= 1000000:
						norm["rhp"] = val
						break
		if norm.has("RHP") and not norm.has("rhp"):
			norm["rhp"] = norm["RHP"]
		if norm.has("global_rank") and not norm.has("globalRank"):
			norm["globalRank"] = norm["global_rank"]
		if norm.has("globalrank") and not norm.has("globalRank"):
			norm["globalRank"] = norm["globalrank"]
		profile = norm
		if profile.has("username"): username = str(profile["username"])
		if profile.has("rhp") and int(profile["rhp"]) >= 0:
			last_rhp = int(profile["rhp"])
		profile_limited = not profile.has("rhp")
		_save_auth()
		emit_signal("profile_updated")
	else:
		if int(res.get("code", 0)) == 404:
			var sres = yield(_api_request(HTTPClient.METHOD_GET, "/api/rhythkit/status", null, true), "completed")
			profile_limited = not profile.has("rhp")
			if sres.get("ok", false) and typeof(sres.get("json")) == TYPE_DICTIONARY and not (sres["json"].has("ok") and not bool(sres["json"].get("ok", false))):
				var sj = sres["json"]
				var norm = {}
				if profile.size() > 0:
					norm = profile.duplicate()
				norm["username"] = str(sj.get("username", username))
				profile = norm
				username = norm["username"]
			emit_signal("profile_updated")
			return
		emit_signal("profile_updated")

func fetch_scores():
	if not logged_in:
		scores_error = "Not signed in"
		emit_signal("scores_updated", false, scores_error)
		return
	var res = yield(_api_request(HTTPClient.METHOD_GET, "/api/rhythkit/scores?limit=25", null, true), "completed")
	var auth_dead = _handle_auth_failure(res)
	if auth_dead:
		scores_error = "Your Rhythians session expired - sign in again."
		emit_signal("scores_updated", false, scores_error)
		return
	if res.get("ok", false) and typeof(res.get("json")) == TYPE_DICTIONARY:
		var j = res["json"]
		if j.has("ok") and not bool(j.get("ok", false)):
			scores_error = str(j.get("error", "Could not load scores"))
			emit_signal("scores_updated", false, scores_error)
			return
		scores_cache = _extract_array(j, ["scores", "data", "items", "results", "recentScores", "userScores", "activity"])
		scores_error = ""
		emit_signal("scores_updated", true, "")
	else:
		scores_error = _http_error_message(res, "the score list")
		emit_signal("scores_updated", false, scores_error)

func fetch_maps():
	if not logged_in:
		maps_error = "Not signed in"
		emit_signal("maps_updated", false, maps_error)
		return
	var collected:Array = []
	var seen:Dictionary = {}
	var offset:int = 0
	var safety:int = 0
	catalog_loading = true
	while safety < 20:
		safety += 1
		var res = yield(_api_request(HTTPClient.METHOD_GET, "/api/rhythkit/maps?limit=1000&offset=" + str(offset), null, true, 60.0), "completed")
		var maps_auth_dead = _handle_auth_failure(res)
		if maps_auth_dead:
			catalog_loading = false
			maps_error = "Your Rhythians session expired - sign in again."
			emit_signal("maps_updated", false, maps_error)
			return
		if not res.get("ok", false):
			if collected.size() == 0:
				maps_error = _http_error_message(res, "the map list")
				emit_signal("maps_updated", false, maps_error)
			break
		var j = res["json"]
		if typeof(j) == TYPE_DICTIONARY and j.has("ok") and not bool(j.get("ok", false)):
			if collected.size() == 0:
				maps_error = str(j.get("error", "Could not load the map list"))
				emit_signal("maps_updated", false, maps_error)
			break
		var arr:Array = _extract_array(j, ["maps", "data", "items", "results", "challengeMaps", "challenges"])
		if arr.size() == 0 and typeof(j) == TYPE_DICTIONARY and j.has("maps") and typeof(j["maps"]) == TYPE_DICTIONARY:
			arr = _extract_array(j["maps"], ["data", "items", "results", "maps"])
		var fresh:int = 0
		for m in arr:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var mid = str(m.get("id", ""))
			if mid == "" or seen.has(mid):
				continue
			seen[mid] = true
			collected.append(m)
			fresh += 1
		maps_cache = collected
		completions_embedded = _maps_have_embedded_completions(collected)
		maps_error = ""
		recompute_rhythian_progress()
		if safety == 1 or arr.size() < 1000 or fresh == 0:
			emit_signal("maps_updated", true, "")
		if arr.size() < 1000 or fresh == 0:
			break
		offset += 1000
	catalog_loading = false

func _maps_have_embedded_completions(maps:Array) -> bool:
	for m in maps:
		if typeof(m) == TYPE_DICTIONARY and m.has("completion"):
			return true
	return false

func fetch_completions():
	if not logged_in:
		completions_error = "Not signed in"
		emit_signal("completions_updated", false, completions_error)
		return
	if completions_embedded:
		completions_error = ""
		emit_signal("completions_updated", true, "")
		return
	var collected:Array = []
	var page:int = 1
	var cursor:String = ""
	var safety:int = 0
	while true:
		safety += 1
		var q:String = ""
		if cursor != "":
			q = "?cursor=" + cursor
		elif page > 1:
			q = "?page=" + str(page) + "&limit=1000"
		else:
			q = "?limit=1000"
		var res = yield(_api_request(HTTPClient.METHOD_GET, "/api/rhythkit/maps/completions" + q, null, true, 45.0), "completed")
		var comp_auth_dead = _handle_auth_failure(res)
		if comp_auth_dead:
			completions_error = "Your Rhythians session expired - sign in again."
			emit_signal("completions_updated", false, completions_error)
			return
		if not res.get("ok", false):
			if collected.size() == 0:
				if int(res.get("code", 0)) == 404:
					completions_embedded = _maps_have_embedded_completions(maps_cache)
					if completions_embedded:
						completions_error = ""
						emit_signal("completions_updated", true, "")
						return
					completions_error = "The completion list is not available on the Rhythians website yet."
				else:
					completions_error = _http_error_message(res, "the completion list")
				emit_signal("completions_updated", false, completions_error)
			break
		var j = res["json"]
		if typeof(j) == TYPE_DICTIONARY and j.has("ok") and not bool(j.get("ok", false)):
			if collected.size() == 0:
				completions_error = str(j.get("error", "Could not load completions"))
				emit_signal("completions_updated", false, completions_error)
			break
		var arr:Array = _extract_array(j, ["completions", "data", "items", "results", "maps", "scores"])
		collected.append_array(arr)
		var more:bool = false
		var next_cursor:String = ""
		if typeof(j) == TYPE_DICTIONARY:
			if j.has("hasMore"):
				more = bool(j["hasMore"])
			elif j.has("nextCursor"):
				next_cursor = str(j["nextCursor"])
				more = next_cursor != ""
			elif j.has("continuationToken"):
				next_cursor = str(j["continuationToken"])
				more = next_cursor != ""
			elif j.has("page") and j.has("totalPages"):
				more = int(j["page"]) < int(j["totalPages"])
			elif j.has("total") and j.has("limit"):
				var total = int(j["total"])
				var off = int(j.get("offset", 0))
				more = (off + arr.size()) < total
		if not more:
			break
		if next_cursor != "":
			cursor = next_cursor
		else:
			page += 1
		if safety > 200 or collected.size() > 200000:
			break
	completions_cache = {}
	for c in collected:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var mid = str(c.get("challengeMapId", c.get("mapId", c.get("id", ""))))
		if mid == "":
			continue
		completions_cache[mid] = c
	completions_error = ""
	recompute_rhythian_progress()
	emit_signal("completions_updated", true, "")

func get_completion_for_map(id:String) -> Dictionary:
	var mid = str(id)
	for m in maps_cache:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("id", "")) == mid:
			var emb = m.get("completion", null)
			if typeof(emb) == TYPE_DICTIONARY and emb.size() > 0:
				return emb
			break
	if completions_cache.has(mid):
		var c = completions_cache[mid]
		if typeof(c) == TYPE_DICTIONARY:
			return c
	return {}

func check_all_maps() -> Dictionary:
	if not logged_in:
		return {}
	var paths = ["/api/rhythkit/maps/check-all", "/api/rhythkit/check-all"]
	for path in paths:
		var res = yield(_api_request(HTTPClient.METHOD_POST, path, {}, true, 60.0), "completed")
		var check_auth_dead = _handle_auth_failure(res)
		if check_auth_dead:
			return {"error": "Your Rhythians session expired - sign in again."}
		if not res.get("ok", false):
			var code = int(res.get("code", 0))
			if code == 404 or code == 405:
				continue
			return {"error": _http_error_message(res, "the map check")}
		var j = res.get("json", null)
		if typeof(j) != TYPE_DICTIONARY:
			continue
		if j.has("ok") and not bool(j.get("ok", false)):
			return {"error": str(j.get("error", "Could not check your maps"))}
		var result = {}
		for pair in [["checked", "checked"], ["foundScores", "foundScores"],
				["alreadyCompleted", "alreadyCompleted"], ["newlyCompleted", "newlyCompleted"],
				["newly_completed", "newlyCompleted"], ["totalPoints", "totalPoints"],
				["total_points", "totalPoints"], ["awarded", "totalPoints"],
				["rankIndex", "rankIndex"]]:
			if j.has(pair[0]):
				result[pair[1]] = int(j[pair[0]])
		if result.has("newlyCompleted") or result.has("totalPoints"):
			fetch_profile()
			fetch_maps()
			fetch_scores()
			return result
	return {}

func recompute_rhythian_progress():
	var completed:int = 0
	var rhp:int = 0
	for mid in completions_cache.keys():
		var c = completions_cache[mid]
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var done = bool(c.get("passed", false)) or bool(c.get("hasScore", false)) or bool(c.get("completed", false)) or bool(c.get("cleared", false))
		if not done:
			continue
		completed += 1
		rhp += _completion_points(c)
	for m in maps_cache:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var mid = str(m.get("id", ""))
		if completions_cache.has(mid):
			continue
		var emb = m.get("completion", null)
		if typeof(emb) == TYPE_DICTIONARY and (bool(emb.get("passed", false)) or bool(emb.get("hasScore", false)) or bool(emb.get("completed", false))):
			completed += 1
			rhp += _completion_points(emb)
	rhythian_stats = {"completed": completed, "total": maps_cache.size(), "rhp": rhp}

func _completion_points(c:Dictionary) -> int:
	for key in ["points", "rhp", "rhpAwarded", "pointsEarned", "reward", "pointsAwarded", "earned"]:
		if c.has(key) and c[key] != null and str(c[key]) != "":
			return int(c[key])
	return 0

func is_rhythian_song(song) -> bool:
	if song == null:
		return false
	return is_rhythian_map_path(str(song.filePath))

func is_rhythian_map_path(fp:String) -> bool:
	if fp == "":
		return false
	var base = MAP_DIR.trim_suffix("/")
	var pbase = Globals.p(base)
	var candidates = [base, pbase]
	var gbase = ""
	var gp:String = ProjectSettings.globalize_path(pbase)
	if gp != "":
		gbase = gp.simplify_path().trim_suffix("/")
		if gbase != "": candidates.append(gbase)
	for c in candidates:
		if fp == c or fp.begins_with(c + "/"):
			return true
	var fname = fp.get_file()
	return fname.begins_with("rhythians-") and fname.ends_with(".sspm") and file_exists_in_maps_dir(fname)

func file_exists_in_maps_dir(fname:String) -> bool:
	var f = File.new()
	return f.file_exists(Globals.p(MAP_DIR).trim_suffix("/") + "/" + fname)

func _safe_filename(text:String) -> String:
	var clean = ""
	for c in text.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			clean += c
		elif c == " ":
			clean += "_"
	return clean.substr(0, 60)

func download_map(map:Dictionary):
	if downloading:
		emit_signal("map_downloaded", str(map.get("id","")), false, "A download is already in progress")
		return
	var id = str(map.get("id",""))
	if id == "":
		emit_signal("map_downloaded", "", false, "Invalid map id")
		return
	downloading = true
	dl_map_id = id
	var dir = Directory.new()
	dir.make_dir_recursive(Globals.p(MAP_DIR))
	var file_name = "rhythians-" + id + "-" + _safe_filename(str(map.get("title","map"))) + ".sspm"
	var final_path = Globals.p(MAP_DIR).trim_suffix("/") + "/" + file_name
	var candidates:Array = []
	for key in ["downloadUrl", "sspmUrl", "fileUrl", "cdnUrl", "download_url"]:
		if map.has(key) and str(map[key]) != "":
			var u = str(map[key])
			if not u.begins_with("http"):
				u = base_url + ("/" if not u.begins_with("/") else "") + u
			candidates.append(u)
	candidates.append(base_url + "/api/rhythkit/maps/" + id + "/download")
	var headers = PoolStringArray(["User-Agent: RhythianClient/" + str(ProjectSettings.get_setting("application/config/version"))])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var watchdog = get_tree().create_timer(180.0)
	watchdog.connect("timeout", self, "_dl_watchdog", [id])
	var ok:bool = false
	var load_error:String = ""
	var last_code:int = 0
	var last_result:int = -1
	var saw_403:bool = false
	var saw_bad_200:bool = false
	var saw_401:bool = false
	var rank_block_msg:String = ""
	var server_error_msg:String = ""
	var hop:int = 0
	var idx:int = 0
	while idx < candidates.size() and hop < 6 and not ok:
		hop += 1
		var dl_url:String = candidates[idx]
		idx += 1
		dl_req = HTTPRequest.new()
		add_child(dl_req)
		dl_req.use_threads = true
		dl_req.timeout = 120.0
		var err = dl_req.request(dl_url, headers, true, HTTPClient.METHOD_GET)
		if err != OK:
			print("Rhythian download: could not start request for ", dl_url)
			dl_req.queue_free()
			dl_req = null
			continue
		var res = yield(dl_req, "request_completed")
		last_result = int(res[0])
		last_code = int(res[1])
		print("Rhythian download: ", dl_url, " -> HTTP ", last_code)
		dl_req.queue_free()
		dl_req = null
		if last_result != HTTPRequest.RESULT_SUCCESS or last_code < 200 or last_code >= 300:
			var body_text:String = ""
			if res.size() > 3:
				body_text = res[3].get_string_from_utf8()
			if last_code == 403:
				saw_403 = true
				var errj = JSON.parse(body_text)
				if errj.error == OK and typeof(errj.result) == TYPE_DICTIONARY and str(errj.result.get("error","")) != "":
					var em = str(errj.result.get("error"))
					if em.findn("rank") != -1:
						rank_block_msg = em
					elif server_error_msg == "":
						server_error_msg = em
			elif last_code == 401:
				saw_401 = true
			elif last_code >= 400:
				var ej = JSON.parse(body_text)
				if ej.error == OK and typeof(ej.result) == TYPE_DICTIONARY and str(ej.result.get("error","")) != "" and server_error_msg == "":
					server_error_msg = str(ej.result.get("error"))
			continue
		var body:PoolByteArray = res[3]
		if body.size() < 4:
			continue
		if body[0] == 0x53 and body[1] == 0x53 and body[2] == 0x2b and body[3] == 0x6d:
			var f = File.new()
			if f.open(final_path, File.WRITE) == OK:
				f.store_buffer(body)
				f.close()
				var song = null
				if Rhythia.registry_song != null and Rhythia.registry_song.has_method("add_sspm_map"):
					song = Rhythia.registry_song.add_sspm_map(get_map_file_path(file_name))
				if song == null:
					song = _registered_song_by_file(file_name)
				if song == null:
					load_error = "Map downloaded, but this client can't load the file (it may need a newer game version or required mods)"
				else:
					_registry_add(file_name, map)
					ok = true
			continue
		var sample:PoolByteArray = body
		if body.size() > 65536:
			sample = body.subarray(0, 65535)
		var trimmed:String = sample.get_string_from_utf8().strip_edges()
		if trimmed.begins_with("{") or trimmed.begins_with("["):
			var parsed = JSON.parse(trimmed)
			if parsed.error == OK:
				var follow = _find_download_url(parsed.result)
				if follow != "":
					if not follow.begins_with("http"):
						follow = base_url + ("/" if not follow.begins_with("/") else "") + follow
					print("Rhythian download: following file URL from JSON response")
					candidates.insert(idx, follow)
					continue
		print("Rhythian download: response was not a valid .sspm, trying next source")
		saw_bad_200 = true
	if ok:
		emit_signal("map_downloaded", id, true, file_name)
	else:
		var msg = "Download failed"
		if load_error != "":
			msg = load_error
		elif saw_401:
			msg = "Your Rhythians session expired - sign in again to download maps."
		elif rank_block_msg != "":
			msg = rank_block_msg
		elif saw_403:
			msg = server_error_msg if server_error_msg != "" else "Download blocked by the Rhythians server (HTTP 403) - this map may not be downloadable for your account"
		elif server_error_msg != "":
			msg = server_error_msg + " (HTTP " + str(last_code) + ")"
		elif saw_bad_200:
			msg = "The Rhythians server did not return a downloadable map file - the download may be locked or unavailable for this map"
		elif last_result == HTTPRequest.RESULT_SUCCESS:
			msg = "Download failed (HTTP " + str(last_code) + ")"
		emit_signal("map_downloaded", id, false, msg)
	_dl_cleanup()

func _dl_cleanup():
	if dl_req != null:
		dl_req.queue_free()
	dl_req = null
	dl_map_id = ""
	downloading = false

func _dl_watchdog(map_id:String):
	if not downloading or dl_map_id != map_id:
		return
	print("Rhythian download: watchdog timeout for ", map_id)
	if dl_req != null and is_instance_valid(dl_req):
		dl_req.cancel_request()
		dl_req.queue_free()
	dl_req = null
	dl_map_id = ""
	downloading = false
	emit_signal("map_downloaded", map_id, false, "Download timed out - try again")

func _find_download_url(node) -> String:
	if typeof(node) == TYPE_DICTIONARY:
		for key in ["downloadUrl", "sspmUrl", "fileUrl", "cdnUrl", "signedUrl", "signed_url", "url", "link", "download"]:
			if node.has(key) and typeof(node[key]) == TYPE_STRING and str(node[key]).begins_with("http"):
				return str(node[key])
		for k in node.keys():
			var v = _find_download_url(node[k])
			if v != "":
				return v
	elif typeof(node) == TYPE_ARRAY:
		for item in node:
			var v = _find_download_url(item)
			if v != "":
				return v
	elif typeof(node) == TYPE_STRING:
		if str(node).begins_with("http"):
			return str(node)
	return ""

func on_song_ended(end_type:int):
	if end_type != Globals.END_PASS: return
	if not logged_in: return
	if Rhythia.replaying: return
	if Rhythia.replay != null and Rhythia.replay.autoplayer: return
	var song = Rhythia.selected_song
	if song == null: return
	if not is_rhythian_map_path(str(song.filePath)): return
	var entry = registry.get(str(song.filePath).get_file(), null)
	if entry == null: return
	if entry.has("isRanked") or entry.has("isLegacy"):
		if not (bool(entry.get("isRanked", false)) or bool(entry.get("isLegacy", false))):
			return
	var total = max(Rhythia.song_end_total_notes, 1)
	var accuracy = (float(Rhythia.song_end_hits) / float(total)) * 100.0
	var payload = {
		"challengeMapId": str(entry.get("id","")),
		"accuracy": accuracy,
		"misses": int(Rhythia.song_end_misses),
		"speed": float(Globals.speed_multi[Rhythia.mod_speed_level]),
		"clientScoreId": _uuid(),
		"resultQualified": true,
		"completedAt": _iso_now(),
		"gameVersion": str(ProjectSettings.get_setting("application/config/version")),
		"integrationVersion": INTEGRATION_VERSION
	}
	_submit_score(payload)

func _submit_score(payload:Dictionary):
	var res = yield(_api_request(HTTPClient.METHOD_POST, "/api/rhythkit/scores", payload, true, 45.0), "completed")
	if int(res.get("code", 0)) == 401:
		_handle_auth_failure(res)
		_queue_score(payload)
		emit_signal("score_submitted", false, "Session expired - score queued")
		return
	var j = res.get("json", null)
	var rejected = typeof(j) == TYPE_DICTIONARY and j.has("ok") and not bool(j.get("ok", false))
	if res.get("ok", false) and not rejected and typeof(j) == TYPE_DICTIONARY:
		var pts = _completion_points(j)
		if pts == 0 and typeof(j) == TYPE_DICTIONARY and j.has("score"):
			pts = _completion_points(j["score"])
		var mid = str(payload.get("challengeMapId", payload.get("mapId", "")))
		if mid != "":
			var rec = completions_cache.get(mid, {})
			rec["passed"] = true
			rec["hasScore"] = true
			rec["points"] = int(pts)
			if not rec.has("accuracy") and payload.has("accuracy"):
				rec["accuracy"] = payload["accuracy"]
			if not rec.has("misses") and payload.has("misses"):
				rec["misses"] = payload["misses"]
			completions_cache[mid] = rec
			recompute_rhythian_progress()
			emit_signal("completions_updated", true, "")
		if j.has("rhp"):
			var new_rhp = int(j["rhp"])
			if new_rhp > 0 and new_rhp <= 1000000:
				profile["rhp"] = new_rhp
				last_rhp = new_rhp
				profile_limited = false
				if profile.has("username"): username = str(profile["username"])
				_save_auth()
				emit_signal("profile_updated")
		emit_signal("score_submitted", true, str(pts))
		return
	if res.get("code", 0) == 409:
		emit_signal("score_submitted", true, "already")
		return
	_queue_score(payload)
	emit_signal("score_submitted", false, "queued")

func _queue_score(payload:Dictionary):
	var queue = []
	var f = File.new()
	if f.file_exists(Globals.p(QUEUE_FILE)) and f.open(Globals.p(QUEUE_FILE), File.READ) == OK:
		var parsed = JSON.parse(f.get_as_text())
		f.close()
		if parsed.error == OK and typeof(parsed.result) == TYPE_ARRAY:
			queue = parsed.result
	queue.append(payload)
	var wf = File.new()
	if wf.open(Globals.p(QUEUE_FILE), File.WRITE) == OK:
		wf.store_string(JSON.print(queue))
		wf.close()

func _flush_score_queue():
	if not logged_in: return
	var f = File.new()
	if not f.file_exists(Globals.p(QUEUE_FILE)): return
	if f.open(Globals.p(QUEUE_FILE), File.READ) != OK: return
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_ARRAY or parsed.result.size() == 0:
		return
	var queue = parsed.result
	var wf = File.new()
	if wf.open(Globals.p(QUEUE_FILE), File.WRITE) == OK:
		wf.store_string("[]")
		wf.close()
	for payload in queue:
		if typeof(payload) != TYPE_DICTIONARY: continue
		yield(_submit_score(payload), "completed")

func _save_registry():
	var f = File.new()
	if f.open(Globals.p(REGISTRY_FILE), File.WRITE) != OK: return
	f.store_string(JSON.print(registry))
	f.close()

func _load_registry():
	var f = File.new()
	if not f.file_exists(Globals.p(REGISTRY_FILE)): return
	if f.open(Globals.p(REGISTRY_FILE), File.READ) != OK: return
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY:
		registry = parsed.result

func _registry_add(file_name:String, map:Dictionary):
	registry[file_name] = {
		"id": str(map.get("id","")),
		"title": str(map.get("title","")),
		"rating": float(map.get("rating", 0.0)),
		"isRanked": bool(map.get("isRanked", false)),
		"isLegacy": bool(map.get("isLegacy", false)),
		"downloadedAt": _iso_now()
	}
	_save_registry()

func is_map_downloaded(id:String) -> bool:
	for key in registry.keys():
		if str(registry[key].get("id","")) == id:
			return true
	return false

func is_map_playable(id:String) -> bool:
	if not is_map_downloaded(id): return false
	for fname in registry.keys():
		if str(registry[fname].get("id","")) != str(id): continue
		var path = get_map_file_path(str(fname))
		var f = File.new()
		if not f.file_exists(path):
			forget_downloaded_map(id)
			return false
		if not is_valid_sspm_file(path):
			print("Rhythian: removing corrupt downloaded map ", path)
			var dir = Directory.new()
			dir.remove(path)
			forget_downloaded_map(id)
			return false
		return true
	return false

func get_maps_dir() -> String:
	return Globals.p(MAP_DIR)

func get_map_file_path(fname:String) -> String:
	return Globals.p(MAP_DIR).trim_suffix("/") + "/" + fname

func forget_downloaded_map(id:String):
	var victim = ""
	for key in registry.keys():
		if str(registry[key].get("id","")) == id:
			victim = key
			break
	if victim != "":
		registry.erase(victim)
		_save_registry()

func _registered_song_by_file(fname:String):
	if Rhythia.registry_song == null: return null
	for song in Rhythia.registry_song.get_items():
		if song is Song and song.filePath != null:
			if str(song.filePath).get_file() == fname:
				return song
	return null

func get_song_for_map_id(id:String):
	if Rhythia.registry_song == null: return null
	for fname in registry.keys():
		if str(registry[fname].get("id","")) != str(id): continue
		var found = _registered_song_by_file(str(fname))
		if found != null:
			return found
		var path = get_map_file_path(str(fname))
		var f = File.new()
		if f.file_exists(path):
			if not is_valid_sspm_file(path):
				print("Rhythian: removing corrupt downloaded map ", path)
				var dir = Directory.new()
				dir.remove(path)
				forget_downloaded_map(id)
			else:
				return Rhythia.registry_song.add_sspm_map(path)
		return null
	return null

func is_valid_sspm_file(path:String) -> bool:
	var f = File.new()
	if f.open(path, File.READ) != OK: return false
	var head = f.get_buffer(4)
	f.close()
	return head.size() == 4 and head[0] == 0x53 and head[1] == 0x53 and head[2] == 0x2b and head[3] == 0x6d

func get_rank_info(rhp:int) -> Dictionary:
	var safe = max(int(floor(rhp)), 0)
	var index = min(RANKS.size() - 1, int(floor(safe / float(RANK_SPAN))))
	var rank = RANKS[index]
	var within = safe - int(rank.minRhp)
	var tier = min(RANK_TIERS, int(floor(within / float(TIER_SPAN))) + 1)
	var tier_start = int(rank.minRhp) + (tier - 1) * TIER_SPAN
	var tier_end = min(tier_start + TIER_SPAN, int(rank.minRhp) + RANK_SPAN)
	var next_tier_start = min(int(rank.minRhp) + tier * TIER_SPAN, int(rank.minRhp) + RANK_SPAN)
	var progress = clamp((safe - tier_start) / float(TIER_SPAN), 0.0, 1.0)
	var next_rank_start = null
	var max_rhp = null
	if index < RANKS.size() - 1:
		next_rank_start = int(RANKS[index + 1].minRhp)
		max_rhp = int(rank.minRhp) + RANK_SPAN
	return {
		"index": index,
		"name": str(rank.name),
		"tier": tier,
		"isExpert": index == RANKS.size() - 1,
		"minRhp": int(rank.minRhp),
		"maxRhp": max_rhp,
		"tierStart": tier_start,
		"tierEnd": tier_end,
		"nextTierStart": next_tier_start,
		"nextRankStart": next_rank_start,
		"color": Color(str(rank.color)),
		"progressToNextTier": progress,
		"rangeMin": float(rank.rangeMin),
		"rangeMax": float(rank.rangeMax)
	}

func is_map_in_rank_range(rating:float, rank_index:int) -> bool:
	var idx = int(clamp(rank_index, 0, RANKS.size() - 1))
	var rank = RANKS[idx]
	return rating >= float(rank.rangeMin) and rating <= float(rank.rangeMax)

func rank_index_for_rating(rating:float) -> int:
	for i in range(RANKS.size()):
		if rating >= float(RANKS[i].rangeMin) and rating <= float(RANKS[i].rangeMax):
			return i
	return RANKS.size() - 1

func round_rating(value) -> float:
	return stepify(float(value), 0.01)

func _length_multiplier(length_seconds) -> float:
	var l = float(length_seconds)
	if l <= 0.0:
		return 1.0
	var ratio = sqrt(l / MAP_LENGTH_REFERENCE_SECONDS)
	return clamp(0.75 + 0.25 * ratio, 0.7, 1.35)

func _accuracy_multiplier(acc:float) -> float:
	if acc >= 100.0: return 1.0
	if acc >= 99.0: return 0.9
	if acc >= 98.0: return 0.75
	if acc >= 95.0: return 0.6
	if acc >= 90.0: return 0.5
	return 0.4

func _speed_multiplier(speed) -> float:
	var s = float(speed)
	if s <= 1.001: return 1.0
	return min(1.5, 1.0 + (s - 1.0) * 0.25)

func rhp_gain_for_map(rating:float, accuracy=null, speed=null, rank_index:int = -1, length_seconds=null) -> int:
	var idx = rank_index if rank_index >= 0 else rank_index_for_rating(rating)
	var base = rhp_base_for_rating(rating, idx) * _length_multiplier(length_seconds)
	var mult = 1.0 if accuracy == null else _accuracy_multiplier(float(accuracy))
	if speed != null:
		mult *= _speed_multiplier(speed)
	return int(max(5, int(round(base * mult))))

func rhp_base_for_rating(rating:float, rank_index:int = -1) -> float:
	var idx = rank_index if rank_index >= 0 else rank_index_for_rating(rating)
	idx = int(clamp(idx, 0, RANKS.size() - 1))
	var rank = RANKS[idx]
	var safe = clamp(rating, float(rank.rangeMin), float(rank.rangeMax))
	var span = max(0.01, float(rank.rangeMax) - float(rank.rangeMin))
	var factor = clamp((safe - float(rank.rangeMin)) / span, 0.0, 1.0)
	return MAP_RHP_FLOOR + (MAP_RHP_CEILING - MAP_RHP_FLOOR) * factor

func get_rank_color(rhp:int) -> Color:
	return get_rank_info(rhp).get("color", Color("#b87333"))

func get_rank_icon_path(rank_index:int, tier:int) -> String:
	if rank_index >= RANKS.size() - 1:
		return "res://assets/images/rank-icons/EXPERT.png"
	var letter = RANK_LETTERS[clamp(rank_index, 0, RANK_LETTERS.size() - 1)]
	return "res://assets/images/rank-icons/" + letter + str(clamp(tier, 1, RANK_TIERS)) + ".png"

func is_rhythian_map_ranked(map_id:String) -> bool:
	for m in maps_cache:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("id", "")) == str(map_id):
			if m.has("isRanked") or m.has("isLegacy"):
				return bool(m.get("isRanked", false)) or bool(m.get("isLegacy", false))
			return get_map_rating(m) > 0.0
	return false

func get_map_rating(map:Dictionary) -> float:
	for key in ["rating", "difficulty", "difficultyRating", "stars", "starRating", "level", "sr", "bp"]:
		if map.has(key) and map[key] != null and str(map[key]) != "":
			var v = float(map[key])
			if v > 0.0:
				return v
	return 0.0

func is_rhythian_ranked_song(song) -> bool:
	if not is_rhythian_song(song):
		return false
	if maps_cache.size() == 0:
		return true
	return is_rhythian_map_ranked(str(song.id))

func _iso_now() -> String:
	var d = OS.get_datetime(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [d.year, d.month, d.day, d.hour, d.minute, d.second]

func _uuid() -> String:
	var chars = "0123456789abcdef"
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var s = ""
	var pattern = [8, 4, 4, 4, 12]
	for group in range(pattern.size()):
		if group != 0: s += "-"
		for i in range(pattern[group]):
			if group == 2 and i == 0:
				s += "4"
			elif group == 3 and i == 0:
				s += chars[8 + rng.randi_range(0, 3)]
			else:
				s += chars[rng.randi_range(0, chars.length() - 1)]
	return s

func format_length(seconds) -> String:
	var secs = max(int(seconds), 0)
	var m = int(floor(secs / 60.0))
	var s = secs % 60
	return "%d:%02d" % [m, s]
