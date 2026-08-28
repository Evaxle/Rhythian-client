extends Control

var root_vbox:VBoxContainer

var website_dot:Control
var database_dot:Control
var website_label:Label
var database_label:Label

var account_panel:VBoxContainer
var account_inner:VBoxContainer

var rank_cells:Dictionary = {}

var scores_list:VBoxContainer
var scores_status:Label

var login_timer:Timer
var login_code:String = ""
var login_url:String = ""
var checking_all:bool = false
var check_maps_button:Button
var ladder_current:Label
var ladder_bar:ProgressBar
var ladder_next:Label

func _ready():
	var bg = ColorRect.new()
	bg.color = RhythianUI.C_BG
	bg.set_anchors_preset(Control.PRESET_WIDE)
	add_child(bg)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_WIDE)
	scroll.margin_left = 44
	scroll.margin_right = -44
	scroll.margin_top = 32
	scroll.margin_bottom = -32
	add_child(scroll)

	root_vbox = RhythianUI.vbox(16)
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_FILL
	root_vbox.rect_min_size = Vector2(0, 720)
	scroll.add_child(root_vbox)

	_build_header()
	_build_status()
	_build_account()
	_build_rank_ladder()
	_build_scores()

	Rhythian.connect("connection_checked", self, "_on_connection_checked")
	Rhythian.connect("auth_changed", self, "_rebuild_account")
	Rhythian.connect("login_started", self, "_on_login_started")
	Rhythian.connect("login_finished", self, "_on_login_finished")
	Rhythian.connect("profile_updated", self, "_on_profile_updated")
	Rhythian.connect("scores_updated", self, "_on_scores_updated")

	Rhythian.check_connection()
	_rebuild_account()
	if Rhythian.logged_in:
		Rhythian.refresh_status()
		Rhythian.fetch_profile()
		Rhythian.fetch_scores()

func _build_header():
	var v = RhythianUI.vbox(6)
	root_vbox.add_child(v)
	v.add_child(RhythianUI.tracking_label("Rhythians", 13, RhythianUI.C_ACCENT))
	v.add_child(RhythianUI.label("Rhythian", 40, RhythianUI.C_WHITE, 1))
	v.add_child(RhythianUI.label("Connect your Rhythians account, browse maps and track your rank from inside Rhythia.", 15, RhythianUI.C_MUTED))

func _build_status():
	var panel = RhythianUI.make_panel()
	var v = RhythianUI.vbox(10)
	panel.add_child(v)
	root_vbox.add_child(panel)
	v.add_child(RhythianUI.label("Connection", 18, RhythianUI.C_WHITE, 1))

	website_dot = RhythianUI.dot(RhythianUI.C_MUTED)
	website_label = RhythianUI.label("Website · checking...", 15)
	var ws_row = RhythianUI.hbox(10)
	ws_row.add_child(website_dot)
	ws_row.add_child(website_label)
	v.add_child(ws_row)

	database_dot = RhythianUI.dot(RhythianUI.C_MUTED)
	database_label = RhythianUI.label("Database · checking...", 15)
	var db_row = RhythianUI.hbox(10)
	db_row.add_child(database_dot)
	db_row.add_child(database_label)
	v.add_child(db_row)

	var recheck = RhythianUI.ghost_button("Recheck")
	recheck.connect("pressed", self, "_on_recheck")
	v.add_child(recheck)

func _build_account():
	var panel = RhythianUI.make_panel()
	account_panel = RhythianUI.vbox(10)
	panel.add_child(account_panel)
	root_vbox.add_child(panel)
	account_panel.add_child(RhythianUI.label("Account", 18, RhythianUI.C_WHITE, 1))
	account_inner = RhythianUI.vbox(11)
	account_panel.add_child(account_inner)

func _build_rank_ladder():
	var panel = RhythianUI.make_panel()
	var v = RhythianUI.vbox(12)
	panel.add_child(v)
	root_vbox.add_child(panel)
	v.add_child(RhythianUI.label("Rank ladder", 18, RhythianUI.C_WHITE, 1))
	var grid = GridContainer.new()
	grid.columns = Rhythian.RANKS.size()
	grid.add_constant_override("hseparation", 8)
	grid.add_constant_override("vseparation", 8)
	for tier in range(1, Rhythian.RANK_TIERS + 1):
		for idx in range(Rhythian.RANKS.size()):
			if idx == Rhythian.RANKS.size() - 1 and tier != 3:
				continue
			var cell = _rank_cell(idx, tier)
			grid.add_child(cell)
			rank_cells["%d-%d" % [idx, tier]] = cell
	v.add_child(grid)
	var row = RhythianUI.hbox(12)
	ladder_current = RhythianUI.label("", 15, RhythianUI.C_WHITE, 1)
	row.add_child(ladder_current)
	ladder_bar = RhythianUI.progress_bar(RhythianUI.C_ACCENT, 8)
	ladder_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ladder_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ladder_bar)
	ladder_next = RhythianUI.label("", 13, RhythianUI.C_MUTED)
	ladder_next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ladder_next)
	v.add_child(row)
	refresh_rank_ladder()

func _rank_cell(idx:int, tier:int) -> PanelContainer:
	var min_rhp = int(Rhythian.RANKS[idx].minRhp)
	var info = Rhythian.get_rank_info(min_rhp)
	var color:Color = info.color
	var is_expert = idx == Rhythian.RANKS.size() - 1
	var txt = "Expert" if is_expert else (str(Rhythian.RANKS[idx].name) + " " + str(tier))
	var pc = RhythianUI.pill_box(color, 10, 3, 10)
	var h = RhythianUI.hbox(6)
	var icon_path = Rhythian.get_rank_icon_path(idx, tier)
	if not ResourceLoader.exists(icon_path):
		icon_path = "res://assets/images/branding/icon.png"
	var tex = RhythianUI.load_texture(icon_path)
	if tex != null:
		var tr = TextureRect.new()
		tr.texture = tex
		tr.rect_min_size = Vector2(20, 20)
		tr.expand = true
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(tr)
	h.add_child(RhythianUI.label(txt, 12, color, 1))
	pc.add_child(h)
	return pc

func _build_scores():
	var panel = RhythianUI.make_panel()
	var v = RhythianUI.vbox(8)
	panel.add_child(v)
	root_vbox.add_child(panel)
	var head = RhythianUI.hbox()
	var left = RhythianUI.vbox(2)
	left.add_child(RhythianUI.tracking_label("RhythKit", 11))
	left.add_child(RhythianUI.label("Recent scores", 20, RhythianUI.C_WHITE, 1))
	head.add_child(left)
	head.add_child(RhythianUI.spacer())
	var refresh = RhythianUI.ghost_button("Refresh")
	refresh.connect("pressed", self, "_refresh_scores")
	head.add_child(refresh)
	var open_site = RhythianUI.ghost_button("Open Rhythians")
	open_site.connect("pressed", self, "_open_rhythians")
	head.add_child(open_site)
	v.add_child(head)
	v.add_child(RhythianUI.label("Mod scores only", 12, RhythianUI.C_MUTED))
	scores_list = RhythianUI.vbox(8)
	v.add_child(scores_list)
	scores_status = RhythianUI.label("Loading...", 14, RhythianUI.C_MUTED)
	v.add_child(scores_status)

func _rebuild_account():
	if account_inner == null: return
	for c in account_inner.get_children():
		c.queue_free()
	if login_code != "":
		_show_auth_state()
		return
	if Rhythian.logged_in:
		var row = RhythianUI.hbox(16)
		var left = RhythianUI.vbox(4)
		var uname = RhythianUI.label(Rhythian.username if Rhythian.username != "" else "Rhythians Account", 24, RhythianUI.C_WHITE, 1)
		left.add_child(uname)
		left.add_child(RhythianUI.label("Signed in with Rhythians", 13, RhythianUI.C_MUTED))
		row.add_child(left)
		row.add_child(RhythianUI.spacer())
		var logout = RhythianUI.ghost_button("Log out")
		logout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		logout.connect("pressed", self, "_on_logout")
		row.add_child(logout)
		account_inner.add_child(row)
		account_inner.add_child(RhythianUI.hline())
		_render_rank_block(account_inner)
		account_inner.add_child(RhythianUI.hline())
		_add_check_maps_button()
	else:
		account_inner.add_child(RhythianUI.label("Sign in to connect your Rhythians account.", 15, RhythianUI.C_MUTED))
		account_inner.add_child(RhythianUI.label("Once signed in, your scores on downloaded Rhythian maps upload to the site, and you can see your rank progress here.", 14, RhythianUI.C_MUTED))
		var login = RhythianUI.accent_button("Login with Rhythians")
		login.connect("pressed", self, "_on_login_pressed")
		account_inner.add_child(login)
		account_inner.add_child(RhythianUI.hline())
		_add_check_maps_button()

func _add_check_maps_button():
	var b = RhythianUI.ghost_button("Check all maps")
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.connect("pressed", self, "_on_check_all_maps")
	account_inner.add_child(b)
	check_maps_button = b

func _on_check_all_maps():
	if not Rhythian.logged_in:
		Globals.notify(Globals.NOTIFY_WARN, "Sign in to check your Rhythian maps", "Rhythians")
		return
	if checking_all:
		return
	checking_all = true
	if check_maps_button != null:
		check_maps_button.text = "Checking..."
		check_maps_button.disabled = true
	var result = yield(Rhythian.check_all_maps(), "completed")
	checking_all = false
	if check_maps_button != null and is_instance_valid(check_maps_button):
		check_maps_button.text = "Check all maps"
		check_maps_button.disabled = false
	if typeof(result) == TYPE_DICTIONARY and result.has("error"):
		Globals.notify(Globals.NOTIFY_WARN, str(result["error"]), "Rhythians")
		return
	if typeof(result) == TYPE_DICTIONARY and result.has("newlyCompleted"):
		var newly = int(result.get("newlyCompleted", 0))
		var already = int(result.get("alreadyCompleted", 0))
		var pts = int(result.get("totalPoints", 0))
		if newly > 0:
			Globals.notify(Globals.NOTIFY_SUCCEED, "Checked your maps - %d newly completed, %d already earned. +%d RHP awarded!" % [newly, already, pts], "Rhythians")
		else:
			Globals.notify(Globals.NOTIFY_INFO, "Checked your maps - %d already completed. No new RHP to award." % already, "Rhythians")
		return
	Rhythian.fetch_maps()
	Rhythian.fetch_scores()
	Rhythian.fetch_profile()
	var s = Rhythian.rhythian_stats
	var total = int(s.get("total", 0))
	if total > 0:
		Globals.notify(Globals.NOTIFY_SUCCEED, "Checked %d ranked maps - %d completed for %d RHP." % [total, int(s.get("completed", 0)), int(s.get("rhp", 0))], "Rhythians")
	else:
		Globals.notify(Globals.NOTIFY_WARN, "The Rhythians server doesn't support map checking yet (HTTP 404). Refreshed your progress instead.", "Rhythians")

func _render_rank_block(parent:VBoxContainer):
	var rhp = int(Rhythian.profile.get("rhp", 0))
	if Rhythian.profile.size() == 0:
		parent.add_child(RhythianUI.label("Loading rank info...", 14, RhythianUI.C_MUTED))
		return
	var rank = Rhythian.get_rank_info(rhp)
	rank["globalRank"] = Rhythian.profile.get("globalRank", null)
	var icon_path = Rhythian.get_rank_icon_path(rank.index, rank.tier if not rank.get("isExpert", false) else 1)
	var user_icon = RhythianUI.icon(icon_path, 34)
	if user_icon.texture != null:
		parent.add_child(user_icon)
	var top = RhythianUI.hbox(16)
	top.add_child(RhythianUI.rank_pill(rank, "lg"))
	top.add_child(RhythianUI.spacer())
	var nums = RhythianUI.hbox(14)
	nums.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if rank.has("globalRank") and rank["globalRank"] != null:
		nums.add_child(RhythianUI.label("#" + str(rank["globalRank"]), 14, RhythianUI.C_MUTED))
	nums.add_child(RhythianUI.label(str(rhp) + " RHP", 18, RhythianUI.C_WHITE, 1))
	top.add_child(nums)
	parent.add_child(top)
	if rank.get("isExpert", false):
		var txt = "You are in the Expert rank - the peak of the ladder."
		if rank.has("globalRank") and rank["globalRank"] != null:
			txt += " Your global position: #" + str(rank["globalRank"])
		parent.add_child(RhythianUI.label(txt, 14, RhythianUI.C_MUTED))
	else:
		var bar_row = RhythianUI.hbox(12)
		bar_row.add_child(RhythianUI.label("Tier " + str(rank.tier) + " of 5", 13, RhythianUI.C_MUTED))
		bar_row.add_child(RhythianUI.spacer())
		bar_row.add_child(RhythianUI.label(str(int(round(rank.progressToNextTier * 100))) + "%", 13, RhythianUI.C_MUTED))
		parent.add_child(bar_row)
		var pb = RhythianUI.progress_bar(rank.color, 8)
		pb.value = rank.progressToNextTier * 100.0
		parent.add_child(pb)
		var next_txt = "Next tier at " + str(rank.nextTierStart) + " RHP"
		if rank.get("nextRankStart", null) != null:
			next_txt = "Next rank at " + str(rank.nextRankStart) + " RHP (" + str(max(int(rank.nextRankStart) - rhp, 0)) + " RHP to go)"
		parent.add_child(RhythianUI.label(next_txt, 12, RhythianUI.C_MUTED))

func refresh_rank_ladder():
	if rank_cells.size() == 0:
		return
	var rhp = int(Rhythian.profile.get("rhp", 0))
	if Rhythian.profile.size() == 0: rhp = 0
	var info = Rhythian.get_rank_info(rhp)
	var current_key = "%d-%d" % [info.index, (3 if info.get("isExpert", false) else info.tier)]
	for key in rank_cells.keys():
		var cell = rank_cells[key]
		var sb = cell.get_stylebox("panel").duplicate()
		sb.border_color = RhythianUI.C_BORDER
		sb.set_border_width_all(1)
		cell.add_stylebox_override("panel", sb)
	if rank_cells.has(current_key):
		var cell = rank_cells[current_key]
		var sb = cell.get_stylebox("panel").duplicate()
		sb.border_color = info.color
		sb.set_border_width_all(2)
		cell.add_stylebox_override("panel", sb)
	if ladder_current == null or ladder_bar == null or ladder_next == null:
		return
	var cur_label = "%s %d" % [str(info.get("name","")), int(info.get("tier",1))]
	if info.get("isExpert", false):
		cur_label = "Expert"
	ladder_current.text = cur_label
	var fg = StyleBoxFlat.new()
	fg.bg_color = info.get("color", RhythianUI.C_ACCENT)
	fg.set_corner_radius_all(8)
	ladder_bar.add_stylebox_override("fg", fg)
	if info.get("isExpert", false):
		ladder_bar.value = 100.0
		ladder_next.text = "Max rank reached"
	else:
		ladder_bar.value = float(info.get("progressToNextTier", 0.0)) * 100.0
		var remain = max(int(info.get("nextTierStart", 0)) - rhp, 0)
		var next_name = ""
		if int(info.get("tier", 1)) >= Rhythian.RANK_TIERS:
			var ni = min(int(info.get("index", 0)) + 1, Rhythian.RANKS.size() - 1)
			next_name = "%s 1" % str(Rhythian.RANKS[ni].name)
		else:
			next_name = "%s %d" % [str(info.get("name","")), int(info.get("tier",1)) + 1]
		ladder_next.text = "%s in %d RHP" % [next_name, remain]

func _on_login_pressed():
	Rhythian.start_login()

func _on_login_started(user_code, verification_url):
	login_code = str(user_code)
	login_url = str(verification_url)
	_rebuild_account()
	_open_url(login_url)
	if login_timer == null:
		login_timer = Timer.new()
		add_child(login_timer)
		login_timer.wait_time = 2.5
		login_timer.connect("timeout", self, "_on_poll_tick")
	login_timer.start()

func _show_auth_state():
	for c in account_inner.get_children():
		c.queue_free()
	account_inner.add_child(RhythianUI.label("Authorize this game on the Rhythians website:", 15, RhythianUI.C_MUTED))
	var code_label = RhythianUI.label(login_code, 32, RhythianUI.C_ACCENT2, 1)
	account_inner.add_child(code_label)
	var open = RhythianUI.accent_button("Open login page")
	open.connect("pressed", self, "_on_open_login_url")
	account_inner.add_child(open)
	var wait = RhythianUI.label("Waiting for authorization - sign in (or create an account) in the browser to continue...", 14, RhythianUI.C_MUTED)
	account_inner.add_child(wait)
	var cancel = RhythianUI.ghost_button("Cancel")
	cancel.connect("pressed", self, "_on_cancel_login")
	account_inner.add_child(cancel)

func _on_poll_tick():
	Rhythian.poll_login()

func _on_login_finished(success, message):
	if login_timer != null:
		login_timer.stop()
	login_code = ""
	login_url = ""
	if success:
		Globals.notify(Globals.NOTIFY_SUCCEED, "Signed in to Rhythians!", "Rhythians")
	else:
		Globals.notify(Globals.NOTIFY_WARN, message, "Rhythians")
	_rebuild_account()

func _on_open_login_url():
	_open_url(login_url)

func _on_cancel_login():
	Rhythian.cancel_login()
	if login_timer != null:
		login_timer.stop()
	login_code = ""
	login_url = ""
	_rebuild_account()

func _on_logout():
	Rhythian.logout()

func _open_url(url:String):
	if url != "":
		OS.shell_open(url)

func _on_connection_checked(web_ok, db_ok):
	_set_dot(website_dot, RhythianUI.C_ACCENT2 if web_ok else Color("ef4444"))
	website_label.text = "Website · Connected" if web_ok else "Website · Unreachable"
	_set_dot(database_dot, RhythianUI.C_ACCENT2 if db_ok else Color("ef4444"))
	database_label.text = "Database · Connected" if db_ok else ("Database · Unavailable" if web_ok else "Database · Unknown")

func _on_recheck():
	Rhythian.check_connection()

func _on_profile_updated():
	_rebuild_account()
	refresh_rank_ladder()

func _refresh_scores():
	if Rhythian.logged_in:
		Rhythian.fetch_scores()

func _open_rhythians():
	_open_url(Rhythian.base_url)

func _on_scores_updated(success, message):
	for c in scores_list.get_children():
		c.queue_free()
	if not Rhythian.logged_in:
		scores_status.text = "Sign in to see your recent scores."
		return
	if success and Rhythian.scores_cache.size() > 0:
		for s in Rhythian.scores_cache:
			if typeof(s) == TYPE_DICTIONARY:
				scores_list.add_child(_score_row(s))
		scores_status.text = ""
	elif success:
		scores_status.text = "No RhythKit scores recorded yet. Pass a Rhythian map to earn your first points!"
	else:
		scores_status.text = message

func _score_row(s:Dictionary) -> PanelContainer:
	var pc = RhythianUI.make_panel(16, 14, Color("070a12"))
	var h = RhythianUI.hbox(10)
	var left = RhythianUI.vbox(3)
	var title = str(s.get("title", "Unknown map"))
	left.add_child(RhythianUI.label(title, 15, RhythianUI.C_WHITE, 1))
	var sub = "%.2f RHP map" % float(s.get("rating", 0.0))
	if s.has("accuracy") and s["accuracy"] != null:
		sub += " · " + "%.2f%%" % float(s["accuracy"])
	if s.has("misses") and s["misses"] != null:
		sub += " · " + str(int(s["misses"])) + " miss" + ("es" if int(s["misses"]) != 1 else "")
	var date = str(s.get("submittedAt", ""))
	if date != "":
		sub += " · " + date.replace("T", " ").replace("Z", "").left(16)
	left.add_child(RhythianUI.label(sub, 12, RhythianUI.C_MUTED))
	h.add_child(left)
	h.add_child(RhythianUI.spacer())
	var pts = RhythianUI.label("+" + str(int(s.get("points", 0))) + " RHP", 16, RhythianUI.C_ACCENT2, 1)
	pts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pts)
	pc.add_child(h)
	return pc

func _set_dot(c:Control, col:Color):
	if c == null: return
	var sb = c.get_stylebox("panel").duplicate()
	sb.bg_color = col
	c.add_stylebox_override("panel", sb)
