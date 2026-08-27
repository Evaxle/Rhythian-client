extends Reference
class_name RhythianUI

# Static helpers that recreate the Rhythians website look
# (tailwind.config.ts colors) inside the Godot client.

const C_BG = Color("070a12")
const C_SURFACE = Color("101629")
const C_MUTED = Color("8d99b5")
const C_BORDER = Color(0.58, 0.639, 0.722, 0.13)
const C_ACCENT = Color("7c8ff0")
const C_ACCENT2 = Color("55d6a0")
const C_WHITE = Color(1, 1, 1)

const FONT_REG = preload("res://assets/font/Lato/Lato-Regular.ttf")
const FONT_BOLD = preload("res://assets/font/Lato/Lato-Bold.ttf")
const FONT_BLACK = preload("res://assets/font/Lato/Lato-Black.ttf")

static func font(size:int = 15, weight:int = 0, spacing:int = 0) -> DynamicFont:
	var f = DynamicFont.new()
	match weight:
		1: f.font_data = FONT_BLACK
		2: f.font_data = FONT_BOLD
		_: f.font_data = FONT_REG
	f.size = size
	f.extra_spacing_char = spacing
	return f

static func label(text:String, size:int = 16, color:Color = C_WHITE, weight:int = 0, align:int = Label.ALIGN_LEFT) -> Label:
	var l = Label.new()
	l.text = text
	l.add_color_override("font_color", color)
	l.add_font_override("font", font(size, weight))
	l.align = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func tracking_label(text:String, size:int = 13, color:Color = C_ACCENT, weight:int = 0) -> Label:
	var l = label(text.to_upper(), size, color, weight, Label.ALIGN_LEFT)
	l.add_font_override("font", font(size, weight, 3))
	return l

static func make_panel(pad:int = 24, corner:int = 20, bg:Color = C_SURFACE) -> PanelContainer:
	var pc = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = C_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	pc.add_stylebox_override("panel", sb)
	return pc

static func accent_button(text:String, small:bool = false) -> Button:
	var b = Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pad = Vector2(14, 7) if small else Vector2(22, 10)
	b.rect_min_size = Vector2(0, 34 if small else 42)
	var normal = StyleBoxFlat.new()
	normal.bg_color = C_ACCENT
	normal.set_corner_radius_all(21)
	normal.content_margin_left = pad.x
	normal.content_margin_right = pad.x
	normal.content_margin_top = pad.y
	normal.content_margin_bottom = pad.y
	var hover = normal.duplicate()
	hover.bg_color = C_ACCENT.lightened(0.12)
	var pressed = normal.duplicate()
	pressed.bg_color = C_ACCENT.darkened(0.15)
	b.add_stylebox_override("normal", normal)
	b.add_stylebox_override("hover", hover)
	b.add_stylebox_override("pressed", pressed)
	b.add_stylebox_override("focus", normal)
	b.add_font_override("font", font(15, 1))
	b.add_color_override("font_color", C_WHITE)
	b.add_color_override("font_color_hover", C_WHITE)
	b.add_color_override("font_color_pressed", C_WHITE)
	return b

static func ghost_button(text:String) -> Button:
	var b = Button.new()
	b.text = text
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.05)
	normal.border_color = C_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(21)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover = normal.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.09)
	var pressed = normal.duplicate()
	pressed.bg_color = Color(1, 1, 1, 0.02)
	b.add_stylebox_override("normal", normal)
	b.add_stylebox_override("hover", hover)
	b.add_stylebox_override("pressed", pressed)
	b.add_stylebox_override("focus", normal)
	b.add_font_override("font", font(14, 1))
	b.add_color_override("font_color", C_WHITE)
	b.add_color_override("font_color_hover", C_WHITE)
	b.add_color_override("font_color_pressed", C_WHITE)
	return b

static func dot(color:Color, size:int = 10) -> Control:
	var p = Panel.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(size / 2)
	p.add_stylebox_override("panel", sb)
	p.rect_min_size = Vector2(size, size)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func status_row(dot_color:Color, text:String) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 10)
	var d = dot(dot_color)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(d)
	h.add_child(label(text, 15))
	return h
static func pill(text:String, color:Color, small:bool = false) -> PanelContainer:
	var pc = pill_box(color, 12 if small else 16, 4 if small else 6, 12)
	pc.add_child(label(text, 13 if small else 14, color, 1))
	return pc

static func pill_box(color:Color, pad_l:int = 12, pad_v:int = 4, radius:int = 18) -> PanelContainer:
	var pc = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.10)
	sb.border_color = Color(color.r, color.g, color.b, 0.33)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_l
	sb.content_margin_right = pad_l
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	pc.add_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pc

static func rank_pill(rank:Dictionary, size:String = "md") -> PanelContainer:
	var color:Color = rank.get("color", C_ACCENT)
	var pc = pill_box(color, 12 if size == "sm" else 14, 3 if size == "sm" else (6 if size == "lg" else 4), 18)
	var name = str(rank.get("name",""))
	if not rank.get("isExpert", false):
		name += " " + str(rank.get("tier", 1))
	if rank.get("isExpert", false) and rank.has("globalRank") and rank["globalRank"] != null and rank["globalRank"] != "":
		name += " #" + str(rank["globalRank"])
	var l = label(name, 12 if size == "sm" else (16 if size == "lg" else 14), color, 1)
	pc.add_child(l)
	return pc

static func progress_bar(fg:Color, height:int = 8) -> ProgressBar:
	var pb = ProgressBar.new()
	pb.rect_min_size = Vector2(0, height)
	pb.min_value = 0.0
	pb.max_value = 100.0
	pb.value = 0.0
	pb.show_percentage = false
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.06)
	bg.set_corner_radius_all(height)
	var fill = StyleBoxFlat.new()
	fill.bg_color = fg
	fill.set_corner_radius_all(height)
	pb.add_stylebox_override("bg", bg)
	pb.add_stylebox_override("fg", fill)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pb

static func hbox(sep:int = 12) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_constant_override("separation", sep)
	return h

static func vbox(sep:int = 10) -> VBoxContainer:
	var v = VBoxContainer.new()
	v.add_constant_override("separation", sep)
	return v

static func spacer(v:float = 0.0) -> Control:
	var c = Control.new()
	if v > 0.0:
		c.rect_min_size = Vector2(0, v)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func hline() -> HSeparator:
	var s = HSeparator.new()
	s.add_color_override("separator", C_BORDER)
	return s

static func open_url(url:String):
	if url != "":
		OS.shell_open(url)

static func check_button(text:String, active:bool = false) -> CheckButton:
	var b = CheckButton.new()
	b.text = text
	b.pressed = active
	b.add_font_override("font", font(14, 1))
	b.add_color_override("font_color", C_WHITE)
	b.add_color_override("font_color_hover", C_WHITE)
	b.add_constant_override("check_vadjust", 0)
	return b

static func option_button(items:Array, selected:int = 0, width:int = 170) -> OptionButton:
	var ob = OptionButton.new()
	for item in items:
		ob.add_item(item)
	ob.selected = selected
	ob.rect_min_size = Vector2(width, 38)
	ob.add_font_override("font", font(14))
	ob.add_color_override("font_color", C_WHITE)
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.027, 0.039, 0.071, 0.9)
	normal.border_color = C_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(12)
	ob.add_stylebox_override("normal", normal)
	ob.add_stylebox_override("hover", normal)
	ob.add_stylebox_override("pressed", normal)
	ob.add_stylebox_override("focus", normal)
	var arrow = normal.duplicate()
	arrow.content_margin_left = 10
	arrow.content_margin_right = 10
	ob.add_stylebox_override("arrow", arrow)
	return ob

static func input_style(control:Control):
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.027, 0.039, 0.071, 0.9)
	sb.border_color = C_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	control.add_stylebox_override("normal", sb)
	var focus = sb.duplicate()
	focus.border_color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.5)
	control.add_stylebox_override("focus", focus)
	var hover = sb.duplicate()
	hover.border_color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.35)
	control.add_stylebox_override("hover", hover)
	control.add_font_override("font", font(14))
	control.add_color_override("font_color", C_WHITE)
