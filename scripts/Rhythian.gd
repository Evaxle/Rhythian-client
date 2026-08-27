extends Node

# Rhythian - connection between the Rhythia client and the Rhythians website.
# Handles: connection status, device login, profile/rank info, map downloads
# and score submission for maps downloaded through the Rhythians browser.

signal connection_checked(website_ok, database_ok)
signal auth_changed
signal login_started(user_code, verification_url)
signal login_finished(success, message)
signal profile_updated
signal maps_updated(success, message)
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
var maps_error:String = ""
var scores_error:String = ""

var registry:Dictionary = {} # sspm file name -> {id,title,rating,downloadedAt}

var device_code:String = ""
var device_expiry:int = 0

var dl_req:HTTPRequest = null
var dl_map_id:String = ""
var downloading:bool = false

# Rank ladder, ported from the Rhythians website (lib/ranks.ts)
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

# ---- persistence ----

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
	logged_in = token != ""

func _save_auth():
	var f = File.new()
	if f.open(Globals.p(AUTH_FILE), File.WRITE) != OK: return
	f.store_string(JSON.print({
		"token": token, "installationId": installation_id,
		"userId": user_id, "username": username
	}))
	f.close()

func logout():
	token = ""
	installation_id = ""
	user_id = ""
	username = ""
	logged_in = false
	profile = {}
	scores_cache = []
	var f = File.new()
	if f.file_exists(Globals.p(AUTH_FILE)):
		var dir = Directory.new()
		dir.remove(Globals.p(AUTH_FILE))
	emit_signal("auth_changed")


# ---- HTTP helper ----

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

# ---- connection status ----

func check_connection():
	var res = yield(_api_request(HTTPClient.METHOD_GET, "/api/health", null, false), "completed")
	var web_ok = res.get("result", 1) == HTTPRequest.RESULT_SUCCESS
	var db_ok = false
	if web_ok and typeof(res.get("json")) == TYPE_DICTIONARY:
		db_ok = str(res["json"].get("database","")).to_lower() == "connected"
	website_ok = web_ok
	database_ok = db_ok
	emit_signal("connection_checked", website_ok, database_ok)

# ---- device login ----

func start_login():
	if device_code != "" and OS.get_unix_time() < device_expiry:
		return
	var res = yield(_api_request(HTTPClient.METHOD_POST, "/api/rhythkit/device/start", {}, false), "completed")
	if not res.get("ok", false) or typeof(res.get("json")) != TYPE_DICTIONARY or not res["json"].get("ok", false):
		var msg = "Could not contact Rhythians"
		if typeof(res.get("json")) == TYPE_DICTIONARY:
			msg = str(res["json"].get("error", msg))
		emit_signal("login_finished", false, msg)
		return
	device_code = str(res["json"].get("deviceCode",""))
	device_expiry = OS.get_unix_time() + int(res["json"].get("expiresIn", 300))
	emit_signal("login_started", str(res["json"].get("userCode","")), str(res["json"].get("verificationUrl","")))

func poll_login():
	if device_code == "": return
	if OS.get_unix_time() >= device_expiry:
		device_code = ""
		emit_signal("login_finished", false, "Login code expired - try again")
		return
	var res = yield(_api_request(HTTPClient.METHOD_POST, "/api/rhythkit/device/poll", {"deviceCode": device_code}, false), "completed")
	if not res.get("ok", false) or typeof(res.get("json")) != TYPE_DICTIONARY:
		return # transient failure, keep polling
	var j = res["json"]
	if j.get("pending", false):
		return
	device_code = ""
	if j.get("ok", false) and j.get("authorized", false):
		token = str(j.get("token",""))
		installation_id = str(j.get("installationId",""))
		user_id = str(j.get("userId",""))
		username = str(j.get("username",""))
		logged_in = token != ""
		_save_auth()
		emit_signal("login_finished", true, "")
		emit_signal("auth_changed")
		fetch_profile()
		fetch_scores()
		_flush_score_queue()
	else:
		emit_signal("login_finished", false, str(j.get("error", "Login failed")))

func cancel_login():
	device_code = ""

# ---- account data ----

func refresh_status():
	if not logged_in: return
	var res = yield(_api_request(HTTPClient.METHOD_GET, "/api/rhythkit/status", null, true), "completed")
	if res.get("code", 0) == 401:
		logout()
		return
	if res.get("ok", false) and typeof(res.get("json")) == TYPE_DICTIONARY and res["json"].get("ok", false):
		username = str(res["json"].get("username", username))
		user_id = str(res["json"].get("userId", user_id))
		installation_id = str(res["json"].get("installationId", installation_id))
		_save_auth()
		emit_signal("auth_changed")

func fetch_profile():
	if not logged_in:
		emit_signal("profile_updated")
		return
	var res = yield(_api_request(HTTPClient.METHOD_GET, "/api/rhythkit/profile", null, true), "completed")
	if res.get("code", 0) == 401:
		logout()
		return
	if res.get("ok", false) and typeof(res.get("json")) == TYPE_DICTIONARY and res["json"].get("ok", false):
		var user = res["json"].get("user", {})
		if typeof(user) == TYPE_DICTIONARY:
			profile = user
			if profile.has("username"): username = str(profile["username"])
	emit_signal("profile_updated")

func fetch_scores():
	if not logged_in:
		scores_error = "Not signed in"
		emit_signal("scores_updated", false, scores_error)
		return
	var res = yield(_api_request(HTTPClient.METHOD_GET, "/api/rhythkit/scores?limit=25", null, true), "completed")
	if res.get("code", 0) == 401:
		logout()
		return
	if res.get("ok", false) and typeof(res.get("json")) == TYPE_DICTIONARY and res["json"].get("ok", false):
		var list = res["json"].get("scores", [])
		scores_cache = list if typeof(list) == TYPE_ARRAY else []
		scores_error = ""
		emit_signal("scores_updated", true, "")
	else:
		scores_error = "Could not load scores"
		if res.get("code", 0) == 404:
			scores_error = "The score list is not available on the Rhythians website yet"
		emit_signal("scores_updated", false, scores_error)
# ---- maps browsing ----

func fetch_maps():
	if not logged_in:
		maps_error = "Not signed in"
		emit_signal("maps_updated", false, maps_error)
		return
	var res = yield(_api_request(HTTPClient.METHOD_GET, "/api/rhythkit/maps", null, true, 45.0), "completed")
	if res.get("code", 0) == 401:
		logout()
		return
	if res.get("ok", false) and typeof(res.get("json")) == TYPE_DICTIONARY and res["json"].get("ok", false):
		var list = res["json"].get("maps", [])
		maps_cache = list if typeof(list) == TYPE_ARRAY else []
		maps_error = ""
		emit_signal("maps_updated", true, "")
	else:
		maps_error = "Could not load the map list"
		if res.get("code", 0) == 404:
			maps_error = "The map list is not available on the Rhythians website yet"
		emit_signal("maps_updated", false, maps_error)

# ---- map downloading ----

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
	var tmp_path = final_path + ".part"
	dl_req = HTTPRequest.new()
	add_child(dl_req)
	dl_req.use_threads = true
	dl_req.timeout = 120.0
	dl_req.download_file = tmp_path
	var headers = PoolStringArray(["User-Agent: RhythianClient/" + str(ProjectSettings.get_setting("application/config/version"))])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var err = dl_req.request(base_url + "/api/rhythkit/maps/" + id + "/download", headers, true, HTTPClient.METHOD_GET)
	if err != OK:
		downloading = false
		dl_req.queue_free()
		dl_req = null
		emit_signal("map_downloaded", id, false, "Could not start download")
		return
	var res = yield(dl_req, "request_completed")
	var result:int = res[0]
	var code:int = res[1]
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		dir.remove(final_path)
		dir.rename(tmp_path, final_path)
		_registry_add(file_name, map)
		if Rhythia.registry_song and Rhythia.registry_song.has_method("add_sspm_map"):
			Rhythia.registry_song.add_sspm_map(Globals.p(MAP_DIR).trim_suffix("/") + "/" + file_name)
		emit_signal("map_downloaded", id, true, file_name)
	else:
		dir.remove(tmp_path)
		var msg = "Download failed"
		if result == HTTPRequest.RESULT_SUCCESS:
			msg = "Download failed (HTTP " + str(code) + ")"
		emit_signal("map_downloaded", id, false, msg)
	_dl_cleanup()

func _dl_cleanup():
	if dl_req != null:
		dl_req.queue_free()
	dl_req = null
	dl_map_id = ""
	downloading = false

# ---- score submission ----

func on_song_ended(end_type:int):
	if end_type != Globals.END_PASS: return
	if not logged_in: return
	if Rhythia.replaying: return
	if Rhythia.replay != null and Rhythia.replay.autoplayer: return
	var song = Rhythia.selected_song
	if song == null: return
	var fp = str(song.filePath)
	if not fp.begins_with(Globals.p(MAP_DIR)): return
	var entry = registry.get(fp.get_file(), null)
	if entry == null: return
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
	if res.get("code", 0) == 401:
		logout()
		_queue_score(payload)
		emit_signal("score_submitted", false, "Session expired - score queued")
		return
	if res.get("ok", false) and typeof(res.get("json")) == TYPE_DICTIONARY and res["json"].get("ok", false):
		var pts = res["json"].get("points", 0)
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

# ---- downloaded map registry ----

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
		"downloadedAt": _iso_now()
	}
	_save_registry()

func is_map_downloaded(id:String) -> bool:
	for key in registry.keys():
		if str(registry[key].get("id","")) == id:
			return true
	return false

func get_maps_dir() -> String:
	return Globals.p(MAP_DIR)

func get_song_for_map_id(id:String):
	if Rhythia.registry_song == null: return null
	for fname in registry.keys():
		if str(registry[fname].get("id","")) != str(id): continue
		var target = Globals.p(MAP_DIR).trim_suffix("/") + "/" + str(fname)
		for song in Rhythia.registry_song.items:
			if song.filePath == target:
				return song
	return null

# ---- rank ladder (ported from website lib/ranks.ts) ----

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
		return "res://assets/images/ranks/EXPERT.png"
	var letter = RANK_LETTERS[clamp(rank_index, 0, RANK_LETTERS.size() - 1)]
	return "res://assets/images/ranks/" + letter + str(clamp(tier, 1, RANK_TIERS)) + ".png"

# ---- misc helpers ----

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
				s += "4" # version nibble (3rd group: xxxxxxxx-xxxx-4xxx-...)
			elif group == 3 and i == 0:
				s += chars[8 + rng.randi_range(0, 3)] # variant nibble 8..b (4th group)
			else:
				s += chars[rng.randi_range(0, chars.length() - 1)]
	return s

func format_length(seconds) -> String:
	var secs = max(int(seconds), 0)
	var m = int(floor(secs / 60.0))
	var s = secs % 60
	return "%d:%02d" % [m, s]
