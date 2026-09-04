extends Panel

const BASE_URL = "https://rhythians-evans-projects-edff1a37.vercel.app"
var portal:Control
var account:Button
var nav = [["home","Home"],["maps","Maps"],["daily","Daily"],["path","Path"],["challenge","Challenge"],["online","Online"],["leaderboards","Leaderboards"],["battles","Battles"],["clips","Clips"],["wiki","Wiki"],["rules","Rules"],["community","Community"]]

func _ready():
	set_anchors_and_margins_preset(Control.PRESET_TOP_WIDE)
	anchor_right = 1.0
	rect_min_size.y = 78
	z_index = 100
	for child in get_children(): child.visible = false
	var background = ColorRect.new()
	background.color = Color(0.035,0.045,0.07,0.98)
	background.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var bar = HBoxContainer.new()
	bar.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	bar.margin_left = 18
	bar.margin_right = -18
	bar.margin_top = 9
	bar.margin_bottom = -9
	bar.add_constant_override("separation", 6)
	add_child(bar)
	var brand = Label.new()
	brand.text = "Rhythia · jun15-2026rc"
	brand.add_color_override("font_color",Color(0.72,0.75,0.82))
	brand.add_font_size_override("font_size",13)
	bar.add_child(brand)
	var center = HBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.alignment = BoxContainer.ALIGN_CENTER
	center.add_constant_override("separation",4)
	bar.add_child(center)
	var play = _button("Play",true)
	play.rect_min_size = Vector2(88,52)
	center.add_child(play)
	play.connect("pressed",self,"to_play")
	for item in nav:
		var b = _button(item[1],false)
		b.rect_min_size.x = 64 if item[1].length() <= 7 else 78
		center.add_child(b)
		b.connect("pressed",self,"open_page",[item[0]])
	account = _button(Rhythian.username if Rhythian.logged_in else "Sign in",false)
	account.rect_min_size = Vector2(112,44)
	bar.add_child(account)
	account.connect("pressed",self,"open_account")
	portal = load("res://scripts/ui/menu/RhythiansPortal.gd").new()
	get_parent().add_child(portal)
	portal.z_index = 50

func _button(text:String,primary:bool) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_color_override("font_color",Color(1,1,1,1))
	b.add_color_override("font_color_hover",Color(1,1,1,1))
	b.add_font_size_override("font_size",16 if primary else 12)
	return b

func _process(_delta:float):
	if account != null: account.text = Rhythian.username if Rhythian.logged_in else "Sign in"

func open_page(page:String):
	_hide_game_pages()
	if portal != null and portal.has_method("open_page"): portal.open_page(page)

func open_account(): open_page("account")

func to_play():
	if portal != null and portal.has_method("close_page"): portal.close_page()
	_hide_game_pages()
	var results = get_node_or_null("../Main/Results")
	if results != null: results.visible = true

func _hide_game_pages():
	for path in ["../Main/Results","../Main/Maps","../Main/Settings","../Main/Credits","../Main/Content","../Main/Language","../Main/Rhythian"]:
		var node = get_node_or_null(path)
		if node != null: node.visible = false
