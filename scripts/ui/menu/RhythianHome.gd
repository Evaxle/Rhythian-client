extends Control

# Root of the Rhythian page: tab bar between "Overview" (connection,
# account, rank ladder, scores) and "Maps" (ranked map browser).

var tab_buttons:Dictionary = {} # "overview"/"maps" -> Button
var pages:Dictionary = {}       # "overview"/"maps" -> Control
var current:String = "overview"

func _ready():
	var bg = ColorRect.new()
	bg.color = RhythianUI.C_BG
	bg.set_anchors_preset(Control.PRESET_WIDE)
	add_child(bg)
	# The Overview/Maps pages are children of this node (from the scene), so
	# the background must be moved behind them or it hides their content.
	move_child(bg, 0)

	var bar = RhythianUI.hbox(8)
	bar.margin_left = 24
	bar.margin_top = 20
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.anchor_right = 1.0
	add_child(bar)

	var logo = RhythianUI.label("Rhythian", 20, RhythianUI.C_WHITE, 1)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(logo)
	bar.add_child(RhythianUI.spacer())

	var overview_tab = _make_tab("Overview", "overview")
	bar.add_child(overview_tab)
	var maps_tab = _make_tab("Maps", "maps")
	bar.add_child(maps_tab)

	var ws = RhythianUI.dot(RhythianUI.C_MUTED, 8)
	ws.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ws.name = "WS"
	bar.add_child(ws)
	Rhythian.connect("connection_checked", self, "_on_conn", [ws])

	if has_node("Overview") and has_node("Maps"):
		pages["overview"] = get_node("Overview")
		pages["maps"] = get_node("Maps")
	_show_tab("overview")

func _make_tab(text:String, key:String) -> Button:
	var b = Button.new()
	b.text = text
	b.name = key
	b.add_font_override("font", RhythianUI.font(15, 1))
	b.add_color_override("font_color", RhythianUI.C_MUTED)
	b.add_color_override("font_color_hover", RhythianUI.C_WHITE)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.connect("pressed", self, "_on_tab_pressed", [key])
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.0)
	tab_buttons[key] = b
	_apply_tab_style(key, key == current)
	return b

func _on_tab_pressed(key:String):
	_apply_tab_style(current, false)
	current = key
	_apply_tab_style(key, true)
	_show_tab(key)

func _apply_tab_style(key:String, active:bool):
	if not tab_buttons.has(key): return
	var b:Button = tab_buttons[key]
	var sb = StyleBoxFlat.new()
	if active:
		sb.bg_color = Color(RhythianUI.C_ACCENT.r, RhythianUI.C_ACCENT.g, RhythianUI.C_ACCENT.b, 0.14)
		sb.border_color = Color(RhythianUI.C_ACCENT.r, RhythianUI.C_ACCENT.g, RhythianUI.C_ACCENT.b, 0.5)
		b.add_color_override("font_color", RhythianUI.C_WHITE)
	else:
		sb.bg_color = Color(1, 1, 1, 0.03)
		sb.border_color = RhythianUI.C_BORDER
		b.add_color_override("font_color", RhythianUI.C_MUTED)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	b.add_stylebox_override("normal", sb)
	b.add_stylebox_override("hover", sb)
	b.add_stylebox_override("pressed", sb)
	b.add_stylebox_override("focus", sb)

func _show_tab(key:String):
	for k in pages.keys():
		pages[k].visible = k == key
		if k == key:
			pages[k].set_process_input(true)
		else:
			pages[k].set_process_input(false)

func _on_conn(web_ok, _db_ok, dot:Control):
	var c = RhythianUI.C_ACCENT2 if web_ok else Color("ef4444")
	_set_dot(dot, c)

func _set_dot(c:Control, col:Color):
	if c == null: return
	var sb = c.get_stylebox("panel").duplicate()
	sb.bg_color = col
	c.add_stylebox_override("panel", sb)
