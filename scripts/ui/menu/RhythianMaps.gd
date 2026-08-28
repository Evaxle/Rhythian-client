extends Control

var search:LineEdit
var sort_cb:OptionButton
var dir_cb:OptionButton
var show_all_btn:CheckButton
var show_unranked_btn:CheckButton
var show_legacy_btn:CheckButton
var range_label:Label
var list_vbox:VBoxContainer
var status_label:Label
var not_signed_in_panel:PanelContainer
var rank_banner_inner:VBoxContainer
var visible_count:int = 40
var out_of_range_count:int = 0
var band_empty_fallback:bool = false

var cards:Dictionary = {}
var dl_progress:Dictionary = {}

var sort_key:int = 0
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

	var banner = RhythianUI.make_panel()
	rank_banner_inner = RhythianUI.vbox(8)
	banner.add_child(rank_banner_inner)
	root.add_child(banner)
	_refresh_rank_banner()

	_build_controls(root)

	list_vbox = RhythianUI.vbox(10)
	root.add_child(list_vbox)
	status_label = RhythianUI.label("", 14, RhythianUI.C_MUTED)
	root.add_child(status_label)

	Rhythian.connect("maps_updated", self, "_on_maps_updated")
	Rhythian.connect("completions_updated", self, "_on_completions_updated")
	Rhythian.connect("auth_changed", self, "_on_auth_changed")
	Rhythian.connect("profile_updated", self, "_on_profile_updated")
	Rhythian.connect("map_downloaded", self, "_on_map_downloaded")
	Rhythian.connect("download_progress", self, "_on_download_progress")

	_on_auth_changed()
	built = true
	rebuild()
	Rhythian.fetch_maps()
	if Rhythian.logged_in:
		Rhythian.fetch_completions()
		_fetch_profile_if_needed()

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
	show_legacy_btn = RhythianUI.check_button("Show legacy maps")
	show_legacy_btn.connect("toggled", self, "_on_show_legacy_toggled")
	row3.add_child(show_legacy_btn)
	show_unranked_btn = RhythianUI.check_button("Show unranked")
	show_unranked_btn.connect("toggled", self, "_on_show_unranked_toggled")
	row3.add_child(show_unranked_btn)
	v.add_child(row3)
func _on_search_changed(_text):
	visible_count = 40
	rebuild()

func _on_sort_changed(_idx):
	sort_key = _idx
	visible_count = 40
	rebuild()

func _on_dir_changed(_idx):
	sort_asc = _idx == 0
	visible_count = 40
	rebuild()

func _on_show_all_toggled(_pressed):
	visible_count = 40
	rebuild()

func _on_show_unranked_toggled(_pressed):
	visible_count = 40
	rebuild()

func _on_show_legacy_toggled(_pressed):
	visible_count = 40
	rebuild()

func _on_refresh():
	Rhythian.fetch_maps()
	if Rhythian.logged_in:
		Rhythian.fetch_completions()
		_fetch_profile_if_needed()

func _fetch_profile_if_needed():
	if Rhythian.logged_in and Rhythian.profile.size() == 0:
		Rhythian.fetch_profile()

func _on_auth_changed():
	if not built:
		return
	visible_count = 40
	rebuild()
	if Rhythian.logged_in:
		Rhythian.fetch_maps()
		Rhythian.fetch_completions()

func on_shown():
	if built and Rhythian.logged_in:
		visible_count = 40
		if typeof(Rhythian.maps_cache) != TYPE_ARRAY or Rhythian.maps_cache.size() == 0:
			Rhythian.fetch_maps()
		if Rhythian.completions_cache.size() == 0:
			Rhythian.fetch_completions()
		_fetch_profile_if_needed()
	_refresh_rank_banner()

func _on_profile_updated():
	_refresh_rank_banner()
	if built:
		visible_count = 40
		rebuild()

func _refresh_rank_banner():
	if rank_banner_inner == null:
		return
	for c in rank_banner_inner.get_children():
		c.queue_free()
	if not Rhythian.logged_in:
		rank_banner_inner.add_child(RhythianUI.label("Sign in to see your rank and progress.", 14, RhythianUI.C_MUTED))
		return
	if Rhythian.profile.size() == 0:
		rank_banner_inner.add_child(RhythianUI.label("Loading your rank...", 14, RhythianUI.C_MUTED))
		return
	var rhp = int(Rhythian.profile.get("rhp", 0))
	var rank = Rhythian.get_rank_info(rhp)
	var icon_path = Rhythian.get_rank_icon_path(rank.index, rank.tier if not rank.get("isExpert", false) else 1)
	var user_icon = RhythianUI.icon(icon_path, 34)
	if user_icon.texture != null:
		rank_banner_inner.add_child(user_icon)
	var top = RhythianUI.hbox(14)
	top.add_child(RhythianUI.rank_pill(rank, "lg"))
	top.add_child(RhythianUI.spacer())
	var nums = RhythianUI.hbox(14)
	nums.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if rank.has("globalRank") and rank["globalRank"] != null:
		nums.add_child(RhythianUI.label("#" + str(rank["globalRank"]), 14, RhythianUI.C_MUTED))
	nums.add_child(RhythianUI.label(str(rhp) + " RHP", 18, RhythianUI.C_WHITE, 1))
	top.add_child(nums)
	rank_banner_inner.add_child(top)
	if rank.get("isExpert", false):
		var txt = "You are in the Expert rank - the peak of the ladder."
		if rank.has("globalRank") and rank["globalRank"] != null:
			txt += " Your global position: #" + str(rank["globalRank"])
		rank_banner_inner.add_child(RhythianUI.label(txt, 13, RhythianUI.C_MUTED))
	else:
		var bar_row = RhythianUI.hbox(12)
		bar_row.add_child(RhythianUI.label("Tier " + str(rank.tier) + " of 5", 13, RhythianUI.C_MUTED))
		bar_row.add_child(RhythianUI.spacer())
		bar_row.add_child(RhythianUI.label(str(int(round(rank.progressToNextTier * 100))) + "%", 13, RhythianUI.C_MUTED))
		rank_banner_inner.add_child(bar_row)
		var pb = RhythianUI.progress_bar(rank.color, 8)
		pb.value = rank.progressToNextTier * 100.0
		rank_banner_inner.add_child(pb)
		var next_txt = "Next tier at " + str(rank.nextTierStart) + " RHP"
		if rank.get("nextRankStart", null) != null:
			next_txt = "Next rank at " + str(rank.nextRankStart) + " RHP (" + str(max(int(rank.nextRankStart) - rhp, 0)) + " RHP to go)"
		rank_banner_inner.add_child(RhythianUI.label(next_txt, 12, RhythianUI.C_MUTED))

func _on_maps_updated(success:bool, message:String):
	if not success:
		_show_maps_error(message)
		return
	if Rhythian.catalog_loading:
		status_label.text = "Loading map catalog... %d maps loaded so far" % Rhythian.maps_cache.size()
		return
	if built:
		visible_count = 40
		rebuild()
		status_label.text = ""

func _show_maps_error(message:String):
	if not built:
		return
	for c in list_vbox.get_children():
		c.queue_free()
	cards.clear()
	var v = RhythianUI.vbox(10)
	var err = RhythianUI.label(message, 14, Color("ef4444"))
	err.autowrap = true
	v.add_child(err)
	var retry = RhythianUI.ghost_button("Retry")
	retry.connect("pressed", self, "_on_refresh")
	v.add_child(retry)
	list_vbox.add_child(v)
	status_label.text = ""

func _on_completions_updated(success:bool, message:String):
	if not success and message != "":
		status_label.text = message
		return
	if built:
		visible_count = 40
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
		if Rhythian.profile.has("rhp"):
			var infoa = Rhythian.get_rank_info(int(Rhythian.profile.get("rhp", 0)))
			range_label.text = "Showing all loaded maps (every rank). Your rank: %s %d · %d RHP - maps outside %.2f – %.2f do not award RHP." % [str(infoa.get("name","")), int(infoa.get("tier",1)), int(Rhythian.profile.get("rhp", 0)), float(infoa.get("rangeMin",0.0)), float(infoa.get("rangeMax",0.0))]
		else:
			range_label.text = "Showing all loaded maps (every rank)."
	elif Rhythian.profile.size() == 0:
		range_label.text = "Sign in to see maps matched to your rank range."
	elif not Rhythian.profile.has("rhp"):
		range_label.text = "Your rank couldn't be detected from the Rhythians account, so all loaded maps are shown."
	else:
		var rhp = int(Rhythian.profile.get("rhp", 0))
		var info = Rhythian.get_rank_info(rhp)
		range_label.text = "Your rank: %s %d · %d RHP — Allowed rating range: %.2f – %.2f" % [str(info.get("name","")), int(info.get("tier",1)), rhp, float(info.get("rangeMin",0.0)), float(info.get("rangeMax",0.0))]

func _is_ranked(map:Dictionary) -> bool:
	if map.has("isRanked"):
		return bool(map.get("isRanked", false))
	if map.has("rating") or map.has("difficulty") or map.has("stars"):
		return Rhythian.get_map_rating(map) > 0.0
	return true

func _is_unranked(map:Dictionary) -> bool:
	if map.has("isUnranked"):
		return bool(map.get("isUnranked", false))
	if map.has("isRanked") or map.has("isLegacy"):
		return not (bool(map.get("isRanked", false)) or bool(map.get("isLegacy", false)))
	if map.has("rating") or map.has("difficulty") or map.has("stars"):
		return Rhythian.get_map_rating(map) <= 0.0
	return false

func _map_sort_value(map:Dictionary):
	match sort_key:
		0:
			return Rhythian.get_map_rating(map)
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

func _sort_maps_rating_desc(a, b):
	return Rhythian.get_map_rating(a) > Rhythian.get_map_rating(b)

func _filtered_maps() -> Array:
	if typeof(Rhythian.maps_cache) != TYPE_ARRAY:
		return []
	band_empty_fallback = false
	var show_all:bool = show_all_btn != null and show_all_btn.pressed
	var band = _maps_pass(true)
	if not show_all and Rhythian.profile.has("rhp"):
		var ranked_in_band:int = 0
		for m in band:
			if typeof(m) == TYPE_DICTIONARY and _is_ranked(m):
				ranked_in_band += 1
		if ranked_in_band == 0:
			band_empty_fallback = true
			return _maps_pass(false)
	return band

func _maps_pass(use_band:bool) -> Array:
	var term = ""
	if search != null:
		term = search.text.strip_edges().to_lower()
	var out = []
	var rank_known:bool = Rhythian.profile.has("rhp")
	var rank_idx:int = 0
	if rank_known:
		rank_idx = int(Rhythian.get_rank_info(int(Rhythian.profile.get("rhp", 0))).get("index", 0))
	out_of_range_count = 0
	for map in Rhythian.maps_cache:
		if typeof(map) != TYPE_DICTIONARY:
			continue
		if term != "":
			var hay = (str(map.get("title", "")) + " " + str(map.get("artist", "")) + " " + str(map.get("mapper", "")) + " " + str(map.get("curatedBy", ""))).to_lower()
			if hay.find(term) == -1:
				continue
		var rating = Rhythian.get_map_rating(map)
		var is_ranked = _is_ranked(map)
		var is_legacy = bool(map.get("isLegacy", false))
		var in_band:bool = not rank_known or rating <= 0.0 or Rhythian.is_map_in_rank_range(rating, rank_idx)
		if show_all_btn != null and show_all_btn.pressed:
			if is_ranked and rank_known and rating > 0.0 and not Rhythian.is_map_in_rank_range(rating, rank_idx):
				out_of_range_count += 1
			out.append(map)
			continue
		if is_ranked:
			if use_band and not in_band:
				out_of_range_count += 1
				continue
			out.append(map)
		elif is_legacy:
			if show_legacy_btn != null and show_legacy_btn.pressed:
				if not use_band or in_band:
					out.append(map)
		else:
			if show_unranked_btn != null and show_unranked_btn.pressed:
				out.append(map)
	return out
func rebuild():
	_update_range_label()
	for c in list_vbox.get_children():
		c.queue_free()
	not_signed_in_panel = null
	cards.clear()
	dl_progress.clear()
	if not Rhythian.logged_in:
		not_signed_in_panel = _make_not_signed_in_panel()
		list_vbox.add_child(not_signed_in_panel)
		return
	var maps = _filtered_maps()
	if out_of_range_count > 0:
		var warn = RhythianUI.label("Showing %d ranked map%s outside your rank's rating range. Those maps don't award RHP, but you can still download and play them." % [out_of_range_count, "" if out_of_range_count == 1 else "s"], 13, Color("fbbf24"))
		warn.autowrap = true
		list_vbox.add_child(warn)
	if band_empty_fallback:
		var rhp = int(Rhythian.profile.get("rhp", 0))
		var info = Rhythian.get_rank_info(rhp)
		var note = RhythianUI.label("No ranked maps are in your rank range right now (%s %d: %.2f - %.2f). Showing the full catalog - out-of-range ranked maps can still be downloaded and played, they just don't award RHP." % [str(info.get("name","")), int(info.get("tier",1)), float(info.get("rangeMin",0.0)), float(info.get("rangeMax",0.0))], 13, Color("fbbf24"))
		note.autowrap = true
		list_vbox.add_child(note)
	if maps.size() == 0:
		var empty:Label
		if show_all_btn != null and not show_all_btn.pressed and Rhythian.profile.size() > 0:
			empty = RhythianUI.label("No ranked maps are in your rank range right now.\nTurn on \"Show all maps\" to browse the full catalog, or enable \"Show legacy maps\".", 14, RhythianUI.C_MUTED)
		else:
			empty = RhythianUI.label("No maps match your current filters.", 14, RhythianUI.C_MUTED)
		list_vbox.add_child(empty)
		return
	if band_empty_fallback:
		maps.sort_custom(self, "_sort_maps_rating_desc")
	else:
		maps.sort_custom(self, "_sort_maps")
	var show = min(visible_count, maps.size())
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_constant_override("hseparation", 14)
	grid.add_constant_override("vseparation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_child(grid)
	for i in range(show):
		var map = maps[i]
		var mid = str(map.get("id", ""))
		if mid == "":
			continue
		var card = _make_card(map, mid)
		grid.add_child(card)
	if show < maps.size():
		var more = RhythianUI.ghost_button("Show more maps (%d more)" % [maps.size() - show])
		more.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		more.connect("pressed", self, "_on_show_more")
		list_vbox.add_child(more)

func _on_show_more():
	visible_count += 40
	rebuild()

func _make_card(map:Dictionary, mid:String) -> PanelContainer:
	var pc = RhythianUI.make_panel(16, 14, Color("0a0f1a"))
	var v = RhythianUI.vbox(10)
	pc.add_child(v)

	v.add_child(_map_header_row(map, mid))
	v.add_child(RhythianUI.label(str(map.get("title", "Untitled")), 17, RhythianUI.C_WHITE, 1))

	var artist = str(map.get("artist", ""))
	var mapper = str(map.get("mapper", map.get("curatedBy", "")))
	var by = artist if artist != "" else "Unknown artist"
	if mapper != "" and mapper != artist:
		by += " by " + mapper
	v.add_child(RhythianUI.label(by, 13, RhythianUI.C_MUTED))

	var pass_txt = _map_stat_label(map, mid)
	if pass_txt != "":
		v.add_child(RhythianUI.label(pass_txt, 12, RhythianUI.C_ACCENT2))

	var meta = RhythianUI.hbox(10)
	var meta_text = ""
	var length_sec = float(map.get("length", 0.0))
	if length_sec > 0.0:
		meta_text = Rhythian.format_length(length_sec)
	var notes = int(map.get("noteCount", map.get("notes", 0)))
	if notes > 0:
		if meta_text != "":
			meta_text += " - "
		meta_text += _comma_int(notes) + " notes"
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

func _map_header_row(map:Dictionary, mid:String) -> HBoxContainer:
	var h = RhythianUI.hbox(8)
	var is_ranked = _is_ranked(map)
	var is_legacy = bool(map.get("isLegacy", false))
	var color = RhythianUI.C_MUTED
	var rank_name = ""
	var rating = Rhythian.get_map_rating(map)
	var meta = _map_rank_meta(rating)
	if is_ranked:
		var raw_name = str(map.get("rankName", ""))
		var raw_color = str(map.get("rankColor", ""))
		if raw_color.begins_with("#") and raw_color.length() == 7:
			color = Color(raw_color)
		if meta.has("name"):
			color = meta["color"]
		if raw_name == "" and meta.has("name"):
			raw_name = str(meta.get("name", ""))
		rank_name = _rank_name_without_tier(raw_name)
		if rank_name == "":
			rank_name = "Ranked"
	elif is_legacy:
		var raw_color = str(map.get("rankColor", ""))
		if raw_color.begins_with("#") and raw_color.length() == 7:
			color = Color(raw_color)
		rank_name = "Legacy"
	if is_ranked:
		var icon_path:String = Rhythian.get_rank_icon_path(int(meta.get("index", 0)), int(meta.get("tier", 1)))
		var ic = RhythianUI.icon(icon_path, 24)
		if ic.texture != null:
			h.add_child(ic)
	var pill_label = rank_name
	if not is_ranked:
		pill_label = "Legacy" if is_legacy else "Unranked"
	h.add_child(RhythianUI.pill(pill_label, color, true))
	if rating > 0.0:
		h.add_child(RhythianUI.pill("%.2f" % rating, color, true))
	if is_ranked and rating > 0.0 and Rhythian.profile.has("rhp") and not Rhythian.is_map_in_rank_range(rating, int(Rhythian.get_rank_info(int(Rhythian.profile.get("rhp", 0))).get("index", 0))):
		h.add_child(RhythianUI.pill("Out of range", Color("fbbf24"), true))
	var completion = Rhythian.get_completion_for_map(mid)
	var scored = bool(map.get("hasScore", false)) or bool(completion.get("passed", false)) or bool(completion.get("hasScore", false))
	if scored:
		h.add_child(RhythianUI.pill("Score found", RhythianUI.C_ACCENT2, true))
	h.add_child(RhythianUI.spacer())
	if (is_ranked or is_legacy) and rating > 0.0:
		var pts = Rhythian.rhp_gain_for_map(rating, 100.0, null, -1, map.get("length", null))
		if is_legacy:
			pts = min(pts, 25)
		h.add_child(RhythianUI.label("%d RHP at 100%% accuracy" % pts, 13, color, 1))
	return h

func _map_rank_meta(rating:float) -> Dictionary:
	if rating <= 0.0:
		return {}
	var idx:int = Rhythian.rank_index_for_rating(rating)
	var rank:Dictionary = Rhythian.RANKS[clamp(idx, 0, Rhythian.RANKS.size() - 1)]
	var span:float = max(0.01, float(rank.rangeMax) - float(rank.rangeMin))
	var factor:float = clamp((rating - float(rank.rangeMin)) / span, 0.0, 0.999)
	var tier:int = int(floor(factor * 5.0)) + 1
	return {"index": idx, "tier": tier, "name": str(rank.name), "color": Color(str(rank.color))}

func _rank_name_without_tier(name:String) -> String:
	var n = name.strip_edges()
	while n.length() > 0 and (n[n.length() - 1] >= "0" and n[n.length() - 1] <= "9" or n[n.length() - 1] == " "):
		n = n.substr(0, n.length() - 1).strip_edges()
	return n

func _map_stat_label(map:Dictionary, mid:String) -> String:
	var completion = Rhythian.get_completion_for_map(mid)
	var is_legacy = bool(map.get("isLegacy", false))
	if typeof(completion) == TYPE_DICTIONARY and bool(completion.get("passed", false)):
		var pts = Rhythian._completion_points(completion)
		return "You have passed this map" + (" (+%d RHP)" % pts if pts != 0 else "") + "."
	if is_legacy:
		var rating = Rhythian.get_map_rating(map)
		var meta = _map_rank_meta(rating)
		var rn = str(meta.get("name", "")) if meta.has("name") else ""
		return "Legacy ranked map - RHP awarded when passed%s." % ((" (%s)" % rn) if rn != "" else "")
	if _is_ranked(map):
		return "Pass this map to earn RHP."
	return ""
func _render_card_action(entry:Dictionary):
	var side = entry.side
	for c in side.get_children():
		c.queue_free()
	entry.pb = null
	entry.status = null
	var map:Dictionary = entry.map
	var mid = str(map.get("id", ""))
	var installed = Rhythian.is_map_playable(mid)
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
		var rating = Rhythian.get_map_rating(map)
		if _is_ranked(map) and rating > 0.0 and Rhythian.profile.has("rhp") and not Rhythian.is_map_in_rank_range(rating, int(Rhythian.get_rank_info(int(Rhythian.profile.get("rhp", 0))).get("index", 0))):
			st.text = "Outside your rank range - no RHP from this map."
			st.add_color_override("font_color", Color("fbbf24"))

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
		if cards.has(mid):
			_render_card_action(cards[mid])
			if cards[mid].status != null:
				cards[mid].status.text = "Map file is missing or corrupted - download it again."
				cards[mid].status.add_color_override("font_color", Color("ef4444"))
		return
	Rhythia.select_song(song)
	var sidebar = _menu_sidebar()
	if sidebar != null and sidebar.has_method("press"):
		sidebar.press(0)
		return
	var menu = get_viewport().get_node_or_null("Menu")
	if menu != null:
		menu.black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")

func _menu_sidebar():
	var menu = get_viewport().get_node_or_null("Menu")
	if menu == null:
		return null
	return menu.get_node_or_null("Sidebar")

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
