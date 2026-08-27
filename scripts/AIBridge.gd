extends Node

const PORT := 8765
const HOST := "127.0.0.1"

var _server: TCPServer
var _client: StreamPeerTCP
var _in_buf := ""
var _vel: Vector2 = Vector2.ZERO
var _prev_rpos: Vector2 = Vector2.ZERO
var _prev_time: float = 0.0

func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	_server = TCPServer.new()
	var err := _server.listen(PORT, HOST)
	if err != OK:
		print("[AIBridge] Failed to listen on %s:%d (err %d)" % [HOST, PORT, err])
		return
	print("[AIBridge] Listening on %s:%d" % [HOST, PORT])

func _process(_delta: float) -> void:
	if get_parent().get_node_or_null("Spawn") == null:
		return
	if _client == null and _server.is_connection_available():
		_client = _server.take_connection()
		print("[AIBridge] Client connected.")
		_ai_control(true)
	if _client == null:
		return
	_update_vel()
	var line := _build_state() + "\n"
	_client.put_data(line.to_utf8())
	while _client.get_available_bytes() > 0:
		var data := _client.get_data(_client.get_available_bytes())
		if data[0] == OK:
			_in_buf += data[1].get_string_from_utf8()
	var text := _in_buf
	var idx := text.find("\n")
	while idx >= 0:
		var action_line := text.substr(0, idx).strip_edges()
		text = text.substr(idx + 1)
		if action_line.length() > 0:
			_apply_action(action_line)
		idx = text.find("\n")
	_in_buf = text

func _exit_tree() -> void:
	_ai_control(false)
	if _client:
		_client.disconnect_from_host()
	if _server:
		_server.stop()

func _ai_control(on: bool) -> void:
	var parent = get_parent()
	if parent == null:
		return
	var cursor = parent.get_node_or_null("Spawn/Cursor")
	if cursor:
		cursor.ai_control = on

func _spawn():
	return get_parent().get_node("Spawn")

func _cursor():
	return get_parent().get_node("Spawn/Cursor")

func _update_vel() -> void:
	var cursor = get_parent().get_node_or_null("Spawn/Cursor")
	if cursor == null:
		return
	var now: float = OS.get_ticks_msec() / 1000.0
	var dt: float = now - _prev_time
	if dt > 0.0:
		_vel = (cursor.rpos - _prev_rpos) / dt
	_prev_rpos = cursor.rpos
	_prev_time = now

func _build_state() -> String:
	var state := {
		"t": _get_song_time(),
		"cursor": _get_cursor_cell(),
		"cursor_vel": _get_cursor_vel(),
		"moving": _get_moving(),
		"notes": _get_notes(),
	}
	return JSON.print(state)

func _get_song_time() -> float:
	return _spawn().ms / 1000.0

func _get_cursor_cell() -> int:
	var rpos: Vector2 = _cursor().rpos
	var col: int = int(floor(rpos.x))
	var row: int = int(floor(rpos.y))
	return int(clamp(col + 3 * row, 0, 8))

func _get_cursor_vel() -> Array:
	return [_vel.x, _vel.y]

func _get_moving() -> bool:
	return _vel.length() > 0.01

func _get_notes() -> Array:
	var out := []
	var t: float = _get_song_time()
	var colors: Array = []
	if Rhythia.selected_colorset:
		colors = Rhythia.selected_colorset.colors
	var notes: Array = _spawn().notes
	for i in range(notes.size()):
		var n: Array = notes[i]
		var notems: float = n[1]
		if notems < t * 1000.0:
			continue
		var pos: Vector2 = n[0]
		var col: int = int(floor(pos.x))
		var row: int = int(floor(-pos.y))
		var cell: int = int(clamp(col + 3 * row, 0, 8))
		var color: int = colors.find(n[3])
		if color < 0:
			color = 0
		out.append({
			"cell": cell,
			"time": notems / 1000.0,
			"type": 0,
			"color": color,
			"size": 1.0,
		})
		if out.size() >= 64:
			break
	return out

func _move_cursor(cell: int) -> void:
	var col: int = cell % 3
	var row: int = int(cell / 3)
	_cursor().move_cursor_abs(Vector2(col + 0.5, row + 0.5))

func _click() -> void:
	pass

func _apply_action(action_line: String) -> void:
	var res := JSON.parse(action_line)
	if res.error != OK:
		print("[AIBridge] Bad action JSON: ", action_line)
		return
	var action: Dictionary = res.result
	if action.has("cell"):
		_move_cursor(int(action["cell"]))
	if action.has("click") and action["click"]:
		_click()