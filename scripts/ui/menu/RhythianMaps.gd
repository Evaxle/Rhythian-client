extends Control

# In-game browser for the Rhythians ranked/legacy map catalog.
# Mirrors the website /maps page: rank-range filtering, search, sort,
# "show unranked" toggle, and per-map download / play.

var search:LineEdit
var sort_cb:OptionButton
var dir_cb:OptionButton
var show_all_btn:CheckButton
var show_unranked_btn:CheckButton
var range_label:Label
var list_vbox:VBoxContainer
var status_label:Label
var not_signed_in_panel:PanelContainer

var cards:Dictionary = {} # map id -> {"root": PanelContainer, "side": HBoxContainer, "pb": ProgressBar, "status": Label, "map": Dictionary}
var dl_progress:Dictionary = {}

var sort_key:int = 0 # mirrors sort_cb items
var sort_asc:bool = true
var built:bool = false

func _ready():
	var bg = ColorRect.new()
	bg.color = RhythianUI.C_BG
	bg.set_anchors_preset(Control.PRESET_WIDE)
	add_child(bg)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_WIDE)
	scroll.margin_left = 44
	scroll.margin_right = -44
	scroll.margin_top = 24
	scroll.margin_bottom = -32
	add_child(scroll)

	var root = RhythianUI.vbox(16)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_FILL
	root.rect_min_size = Vector2(0, 760)
	scroll.add_child(root)

	var head = RhythianUI.vbox(4)
	root.add_child(head)
	head.add_child(RhythianUI.tracking_label("Rhythians", 13, RhythianUI.C_ACCENT))
	head.add_child(RhythianUI.label("Map browser", 34, RhythianUI.C_WHITE, 1))
	head.add_child(RhythianUI.label("Ranked maps award RHP. Legacy maps award RHP when passed. Unranked maps can be played but do not award RHP.", 14, RhythianUI.C_MUTED))

	_build_controls(root)

	list_vbox = RhythianUI.vbox(10)
	root.add_child(list_vbox)
	status_label = RhythianUI.label("", 14, RhythianUI.C_MUTED)
	root.add_child(status_label)

	Rhythian.connect("maps_updated", self, "_on_maps_updated")
	Rhythian.connect("auth_changed", self, "_on_auth_changed")
	Rhythian.connect("map_downloaded", self, "_on_map_downloaded")
	Rhythian.connect("download_progress", self, "_on_download_progress")

	_on_auth_changed()
	built = true
	rebuild()
	Rhythian.fetch_maps()

func _build_controls(root:VBoxContainer):
	var panel = RhythianUI.make_panel(20, 18)
	var v = RhythianUI.vbox(10)
	panel.add_child(v)
	root.add_child(panel)

	range_label = RhythianUI.label("", 14, RhythianUI.C_MUTED)
	v.add_child(range_label)

	var row1 = RhythianUI.hbox(10)
	search = LineEdit.new()
	search.placeholder_text = "Search maps by title, artist, or mapper..."
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.rect_min_size = Vector2(0, 38)
	RhythianUI.input_style(search)
	search.add_color_override("font_color_placeholder", RhythianUI.C_MUTED)
	search.connect("text_changed", self, "_on_search_changed")
	row1.add_child(search)
	var refresh = RhythianUI.ghost_button("Refresh")
	refresh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	refresh.connect("pressed", self, "_on_refresh")
	row1.add_child(refresh)
	v.add_child(row1)

	var row2 = RhythianUI.hbox(10)
	var sort_label = RhythianUI.label("Sort by", 12, RhythianUI.C_MUTED, 0)
	sort_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row2.add_child(sort_label)
	sort_cb = RhythianUI.option_button(["Rating", "Map name", "Mapper", "Artist", "Length", "Notes", "RHP value"], 0, 130)
	sort_cb.connect("item_selected", self, "_on_sort_changed")
	row2.add_child(sort_cb)
	dir_cb = RhythianUI.option_button(["Ascending", "Descending"], 0, 130)
	dir_cb.connect("item_selected", self, "_on_dir_changed")
	row2.add_child(dir_cb)
	v.add_child(row2)

	var row3 = RhythianUI.hbox(12)
	show_all_btn = RhythianUI.check_button("Show all maps")
	show_all_btn.connect("toggled", self, "_on_show_all_toggled")
	row3.add_child(show_all_btn)
	show_unranked_btn = RhythianUI.check_button("Show unranked")
	show_unranked_btn.connect("toggled", self, "_on_show_unranked_toggled")
	row3.add_child(show_unranked_btn)
	v.add_child(row3)
func _on_search_changed(_text):
	rebuild()

func _on_sort_changed(_idx):
	sort_key = _idx
	rebuild()

func _on_dir_changed(_idx):
	sort_asc = _idx == 0
	rebuild()

func _on_show_all_toggled(_pressed):
	rebuild()

func _on_show_unranked_toggled(_pressed):
	rebuild()

func _on_refresh():
	Rhythian.fetch_maps()

func _on_auth_changed():
	if built:
		rebuild()

func _on_maps_updated(success:bool, message:String):
	if not success:
		status_label.text = message
		return
	status_label.text = ""
	if built:
		rebuild()

func _make_not_signed_in_panel() -> PanelContainer:
	var pc = RhythianUI.make_panel(16, 14)
	var nv = RhythianUI.vbox(6)
	nv.add_child(RhythianUI.label("You're not signed in", 16, RhythianUI.C_WHITE, 1))
	nv.add_child(RhythianUI.label("Sign in from the Overview tab to browse and download ranked maps.", 13, RhythianUI.C_MUTED))
	pc.add_child(nv)
	return pc

func _update_range_label():
	if range_label == null:
		return
	if show_all_btn != null and show_all_btn.pressed:
		range_label.text = "Showing all maps"
	elif Rhythian.profile.size() == 0:
		range_label.text = "Sign in to see maps matched to your rank range."
	else:
		var rhp = int(Rhythian.profile.get("rhp", 0))
		var info = Rhythian.get_rank_info(rhp)
		range_label.text = "Showing maps in your rank range (" + str(info.get("name", "")) + str(info.get("tier", "")) + ")"

func _is_ranked(map:Dictionary) -> bool:
	return bool(map.get("isRanked", false)) or bool(map.get("isLegacy", false))

func _map_sort_value(map:Dictionary):
	match sort_key:
		0:
			return float(map.get("rating", 0.0))
		1:
			return str(map.get("title", "")).to_lower()
		2:
			return str(map.get("mapper", map.get("curatedBy", ""))).to_lower()
		3:
			return str(map.get("artist", "")).to_lower()
		4:
			return float(map.get("length", 0.0))
		5:
			return int(map.get("noteCount", map.get("notes", 0)))
		_:
			return Rhythian.rhp_gain_for_map(float(map.get("rating", 0.0)), null, null, -1, map.get("length", null))

func _sort_maps(a, b):
	var va = _map_sort_value(a)
	var vb = _map_sort_value(b)
	if sort_asc:
		return va < vb
	return va > vb

func _filtered_maps() -> Array:
	if typeof(Rhythian.maps_cache) != TYPE_ARRAY:
		return []
	var term = ""
	if search != null:
		term = search.text.strip_edges().to_lower()
	var list = []
	for map in Rhythian.maps_cache:
		if typeof(map) != TYPE_DICTIONARY:
			continue
		if term != "":
			var hay = (str(map.get("title", "")) + " " + str(map.get("artist", "")) + " " + str(map.get("mapper", "")) + " " + str(map.get("curatedBy", ""))).to_lower()
			if hay.find(term) == -1:
				continue
		var is_ranked = _is_ranked(map)
		if not is_ranked and not show_unranked_btn.pressed:
			continue
		if is_ranked and not show_all_btn.pressed and Rhythian.profile.size() > 0:
			var rhp = int(Rhythian.profile.get("rhp", 0))
			var info = Rhythian.get_rank_info(rhp)
			if not Rhythian.is_map_in_rank_range(float(map.get("rating", 0.0)), int(info.get("index", 0))):
				continue
		list.append(map)
	return list
func rebuild():
	_update_range_label()
	for c in list_vbox.get_children():
		c.free()
	not_signed_in_panel = null
	cards.clear()
	dl_progress.clear()
	if not Rhythian.logged_in:
		not_signed_in_panel = _make_not_signed_in_panel()
		list_vbox.add_child(not_signed_in_panel)
		return
	var maps = _filtered_maps()
	if maps.size() == 0:
		var empty = RhythianUI.label("No maps match your current filters.", 14, RhythianUI.C_MUTED)
		list_vbox.add_child(empty)
		return
	maps.sort_custom(self, "_sort_maps")
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_constant_override("hseparation", 14)
	grid.add_constant_override("vseparation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_child(grid)
	for map in maps:
		var mid = str(map.get("id", ""))
		if mid == "":
			continue
		var card = _make_card(map, mid)
		grid.add_child(card)

func _make_card(map:Dictionary, mid:String) -> PanelContainer:
	var pc = RhythianUI.make_panel(16, 14, Color("0a0f1a"))
	var v = RhythianUI.vbox(10)
	pc.add_child(v)

	v.add_child(_map_header_row(map))
	v.add_child(RhythianUI.label(str(map.get("title", "Untitled")), 17, RhythianUI.C_WHITE, 1))

	var artist = str(map.get("artist", ""))
	var mapper = str(map.get("mapper", map.get("curatedBy", "")))
	var by = artist if artist != "" else "Unknown artist"
	if mapper != "" and mapper != artist:
		by += " by " + mapper
	v.add_child(RhythianUI.label(by, 13, RhythianUI.C_MUTED))

	var pass_txt = _map_stat_label(map)
	if pass_txt != "":
		v.add_child(RhythianUI.label(pass_txt, 12, RhythianUI.C_ACCENT2))

	var meta = RhythianUI.hbox(10)
	var meta_text = ""
	var len = float(map.get("length", 0.0))
	if len > 0.0:
		meta_text = Rhythian.format_length(len)
	var notes = int(map.get("noteCount", map.get("notes", 0)))
	if notes > 0:
		if meta_text != "":
			meta_text += " - "
		meta_text += _comma_int(notes) + " notes"
	if _is_ranked(map):
		if meta_text != "":
			meta_text += " - "
		meta_text += "%.2f bp" % float(map.get("rating", 0.0))
	meta.add_child(RhythianUI.label(meta_text, 12, RhythianUI.C_MUTED))
	meta.add_child(RhythianUI.spacer())
	v.add_child(meta)

	var side = RhythianUI.hbox(8)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(side)

	var entry = {"root": pc, "side": side, "pb": null, "status": null, "map": map}
	cards[mid] = entry
	_render_card_action(entry)
	return pc

func _map_header_row(map:Dictionary) -> HBoxContainer:
	var h = RhythianUI.hbox(8)
	var is_ranked = _is_ranked(map)
	var color = RhythianUI.C_MUTED
	var rank_name = ""
	if is_ranked:
		var raw_name = str(map.get("rankName", ""))
		var raw_color = str(map.get("rankColor", ""))
		if raw_color.begins_with("#") and raw_color.length() == 7:
			color = Color(raw_color)
		var rating = float(map.get("rating", 0.0))
		if raw_name == "" and rating > 0.0:
			var info = Rhythian.get_rank_info(int(floor(rating)))
			rank_name = str(info.get("name", ""))
			if not bool(info.get("isExpert", false)):
				rank_name += str(info.get("tier", ""))
		else:
			rank_name = raw_name
		if rank_name == "":
			rank_name = "Ranked"
	h.add_child(RhythianUI.pill("Unranked" if not is_ranked else rank_name, color, true))
	var scored = bool(map.get("hasScore", false))
	var completion = map.get("completion", {})
	if typeof(completion) == TYPE_DICTIONARY and bool(completion.get("passed", false)):
		scored = true
	if scored:
		h.add_child(RhythianUI.pill("Scored", RhythianUI.C_ACCENT2, true))
	h.add_child(RhythianUI.spacer())
	if is_ranked and map.get("rating", null) != null:
		var pts = Rhythian.rhp_gain_for_map(float(map["rating"]), null, null, -1, map.get("length", null))
		h.add_child(RhythianUI.label("~" + str(pts) + " RHP", 13, RhythianUI.C_ACCENT2, 1))
	return h

func _map_stat_label(map:Dictionary) -> String:
	var completion = map.get("completion", {})
	if typeof(completion) == TYPE_DICTIONARY and bool(completion.get("passed", false)):
		var pts = int(completion.get("points", 0))
		return "You have passed this map" + (" (+%d RHP)" % pts if pts != 0 else "") + "."
	if _is_ranked(map):
		return "Pass this map to earn RHP."
	return ""
func _render_card_action(entry:Dictionary):
	var side = entry.side
	for c in side.get_children():
		c.free()
	entry.pb = null
	entry.status = null
	var map:Dictionary = entry.map
	var mid = str(map.get("id", ""))
	var installed = Rhythian.is_map_downloaded(mid)
	var busy = mid != "" and Rhythian.downloading and Rhythian.dl_map_id == mid

	if installed:
		var play = RhythianUI.accent_button("Play", true)
		play.connect("pressed", self, "_on_play_pressed", [mid])
		side.add_child(play)
		var st = RhythianUI.label("Installed", 12, RhythianUI.C_ACCENT2)
		st.align = Label.ALIGN_CENTER
		side.add_child(st)
		entry.status = st
	elif busy:
		var pb = RhythianUI.progress_bar(RhythianUI.C_ACCENT, 6)
		side.add_child(pb)
		entry.pb = pb
		var st = RhythianUI.label("Starting download...", 12, RhythianUI.C_MUTED)
		st.align = Label.ALIGN_CENTER
		side.add_child(st)
		entry.status = st
	else:
		var dl = RhythianUI.accent_button("Download", true)
		dl.disabled = Rhythian.downloading
		dl.connect("pressed", self, "_on_download_pressed", [mid])
		side.add_child(dl)
		var st = RhythianUI.label("", 12, RhythianUI.C_MUTED)
		st.align = Label.ALIGN_CENTER
		side.add_child(st)
		entry.status = st

func _on_download_pressed(mid:String):
	if not cards.has(mid):
		return
	Rhythian.download_map(cards[mid].map)
	_render_card_action(cards[mid])

func _on_download_progress(mid:String, received:int, total:int):
	dl_progress[mid] = {"received": received, "total": total}
	if not cards.has(mid):
		return
	var entry = cards[mid]
	if entry.pb != null and total > 0:
		entry.pb.value = (float(received) / float(total)) * 100.0
	if entry.status != null:
		entry.status.text = "%.1f MB" % (received / 1048576.0)

func _on_map_downloaded(mid:String, success:bool, message:String):
	if cards.has(mid):
		_render_card_action(cards[mid])
		if not success:
			var st = cards[mid].status
			if st != null:
				st.text = message
				st.add_color_override("font_color", Color("ef4444"))
	if success:
		Globals.notify(Globals.NOTIFY_SUCCEED, "Map installed: " + message, "Rhythian Maps")

func _on_play_pressed(mid:String):
	var song = Rhythian.get_song_for_map_id(mid)
	if song == null:
		if cards.has(mid) and cards[mid].status != null:
			cards[mid].status.text = "Restart the game to find this map in the map list."
		return
	Rhythia.select_song(song)
	var menu = get_viewport().get_node_or_null("Menu")
	if menu != null:
		menu.black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")

func _comma_int(n:int) -> String:
	var s = str(n)
	if s.length() <= 3:
		return s
	var out = ""
	var c = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i != 0:
			out = "," + out
	return out
