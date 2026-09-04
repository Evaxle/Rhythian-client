extends Control

const BASE_URL = "https://rhythians-evans-projects-edff1a37.vercel.app"
const SETTINGS_FILE = "user://rhythian/client-settings.json"

var title_label:Label
var content:VBoxContainer
var status:Label
var selected_page = "home"
var spin_enabled = false
var battle_mode = "1v1"
var battle_type = "ranked"
var battle:Node
var clips:Node
var clip_file_dialog:FileDialog
var clip_title:LineEdit
var clip_song:LineEdit
var clip_description:TextEdit
var clip_mode:String = ""

func _ready():
	Rhythian.base_url = BASE_URL
	_load_settings()
	set_anchors_preset(Control.PRESET_WIDE)
	anchor_right = 1.0
	anchor_bottom = 1.0
	visible = false
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_WIDE)
	margin.margin_left = 40
	margin.margin_right = -40
	margin.margin_top = 86
	margin.margin_bottom = -24
	add_child(margin)
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var root = VBoxContainer.new()
	root.add_constant_override("separation",14)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)
	title_label = RhythianUI.label("Home",34,RhythianUI.C_WHITE,1)
	root.add_child(title_label)
	root.add_child(RhythianUI.label("Rhythians inside Rhythia",14,RhythianUI.C_MUTED))
	content = RhythianUI.vbox(12)
	root.add_child(content)
	status = RhythianUI.label("",13,RhythianUI.C_MUTED)
	root.add_child(status)
	battle = load("res://scripts/network/BattleClient.gd").new()
	add_child(battle)
	battle.start()
	battle.connect("state_changed",self,"_battle_state_changed")
	battle.connect("error",self,"_network_error")
	clips = load("res://scripts/network/ClipClient.gd").new()
	add_child(clips)
	clips.connect("upload_finished",self,"_clip_upload_finished")
	Rhythian.connect("auth_changed",self,"_refresh_page")
	Rhythian.connect("profile_updated",self,"_refresh_page")
	Rhythian.connect("maps_updated",self,"_refresh_page")
	Rhythian.connect("connection_checked",self,"_connection_checked")
	show_page("home")
	Rhythian.check_connection()

func open_page(page:String):
	visible = true
	show_page(page)

func close_page():
	visible = false

func _refresh_page(_a=null,_b=null):
	show_page(selected_page)

func _battle_state_changed(_data):
	if selected_page == "battles":
		show_page("battles")

func _network_error(message:String):
	status.text=message
	if selected_page == "battles":
		show_page("battles")

func _connection_checked(web_ok:bool,db_ok:bool):
	if selected_page == "home":
		status.text="Internet: %s · Rhythians API: %s · Database: %s" % ["connected" if web_ok else "offline","online" if web_ok else "unavailable","connected" if db_ok else "unavailable"]

func _load_settings():
	var file = File.new()
	if not file.file_exists(Globals.p(SETTINGS_FILE)): return
	if file.open(Globals.p(SETTINGS_FILE),File.READ)!=OK: return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error==OK and typeof(parsed.result)==TYPE_DICTIONARY: spin_enabled=bool(parsed.result.get("spinEnabled",false))

func _save_settings():
	var file = File.new()
	if file.open(Globals.p(SETTINGS_FILE),File.WRITE)!=OK: return
	file.store_string(JSON.print({"spinEnabled":spin_enabled}))
	file.close()

func _clear():
	for child in content.get_children(): child.queue_free()
	status.text=""

func _panel(name:String,text:String="") -> VBoxContainer:
	var panel=RhythianUI.make_panel(20,20)
	var box=RhythianUI.vbox(8)
	panel.add_child(box)
	box.add_child(RhythianUI.label(name,19,RhythianUI.C_WHITE,1))
	if text!="":
		var body=RhythianUI.label(text,13,RhythianUI.C_MUTED)
		body.autowrap=true
		box.add_child(body)
	content.add_child(panel)
	return box

func _button(parent:Container,text:String,primary:bool=false) -> Button:
	var button=RhythianUI.accent_button(text) if primary else RhythianUI.ghost_button(text)
	parent.add_child(button)
	return button

func _line(parent:Container,placeholder:String,initial:String="") -> LineEdit:
	var field=LineEdit.new()
	field.placeholder_text=placeholder
	field.text=initial
	field.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field

func show_page(page:String):
	selected_page=page
	_clear()
	match page:
		"home": _home()
		"maps": _maps()
		"daily": _external("Daily","Daily map, streaks and history.","/daily")
		"path": _external("Path","Seasonal Path progression and rewards.","/path")
		"challenge": _external("Challenge","Challenge progression and maps.","/challenge")
		"online": _external("Online","Live community presence.","/online")
		"leaderboards": _external("Leaderboards","Global, rank, mode and battle leaderboards.","/leaderboards")
		"battles": _battles()
		"clips": _clips()
		"wiki": _external("Wiki","Knowledge base and guides.","/wiki")
		"rules": _external("Rules","Community rules.","/rules")
		"community": _community()
		"account": _account()
		_: _home()

func _home():
	title_label.text="Home"
	var account=_panel("Account",Rhythian.logged_in ? "%s · %d RHP" % [Rhythian.username,int(Rhythian.profile.get("rhp",0))] : "Not signed in")
	var row=RhythianUI.hbox(10)
	account.add_child(row)
	if Rhythian.logged_in:
		var refresh=_button(row,"Refresh account")
		refresh.connect("pressed",Rhythian,"fetch_profile")
		var logout=_button(row,"Log out")
		logout.connect("pressed",Rhythian,"logout")
	else:
		var login=_button(row,"Sign in with Rhythians",true)
		login.connect("pressed",self,"_login")
	var score=_panel("Score pools","The client supports RPL and RPS only. RPL is used when Spin is disabled. RPS is used when Spin is enabled. RPV is unsupported. RBP is battle-only.")
	var totals=_mode_totals()
	var points=RhythianUI.hbox(22)
	score.add_child(points)
	points.add_child(RhythianUI.label("RPL %d" % totals["rpl"],18,RhythianUI.C_WHITE,1))
	points.add_child(RhythianUI.label("RPS %d" % totals["rps"],18,RhythianUI.C_WHITE,1))
	points.add_child(RhythianUI.label("RHP %d" % int(Rhythian.profile.get("rhp",0)),18,RhythianUI.C_WHITE,1))
	var actions=_panel("Quick actions")
	var ar=RhythianUI.hbox(10)
	actions.add_child(ar)
	var maps=_button(ar,"Maps",true)
	maps.connect("pressed",self,"show_page",["maps"])
	var battles=_button(ar,"Battles")
	battles.connect("pressed",self,"show_page",["battles"])
	var clips_button=_button(ar,"Clips")
	clips_button.connect("pressed",self,"show_page",["clips"])
	var check=_button(ar,"Check all scores")
	check.connect("pressed",self,"_check_all_scores")
	Rhythian.check_connection()

func _maps():
	title_label.text="Maps"
	if not Rhythian.logged_in:
		var need=_panel("Sign in required","Sign in to synchronize rank and map data.")
		var login=_button(need,"Sign in",true)
		login.connect("pressed",self,"_login")
		return
	var rhp=int(Rhythian.profile.get("rhp",0))
	var rank=Rhythian.get_rank_info(rhp)
	var banner=_panel("Current rank","%s · %d RHP · ranked maps outside your current rank range are not eligible for RHP." % [str(rank.name),rhp])
	var refresh=_button(banner,"Refresh maps",true)
	refresh.connect("pressed",Rhythian,"fetch_maps")
	if Rhythian.maps_cache.empty():
		_panel("Map catalog",Rhythian.maps_error if Rhythian.maps_error!="" else "No maps loaded yet.")
		return
	var shown=min(30,Rhythian.maps_cache.size())
	for i in range(shown):
		var map=Rhythian.maps_cache[i]
		_panel(str(map.get("title","Unknown map")),"%.2f rating" % Rhythian.get_map_rating(map))
	_panel("Catalog","Showing %d of %d loaded maps. The established native map browser remains available for full sorting and map actions." % [shown,Rhythian.maps_cache.size()])

func _external(name:String,description:String,path:String):
	title_label.text=name
	var box=_panel(name,description)
	var open=_button(box,"Open full %s page" % name,true)
	open.connect("pressed",RhythianUI,"open_url",[BASE_URL+path])
	_panel("Native client","This page is connected to the Rhythians account, while the full server-rendered page remains the authoritative web UI until an equivalent native dataset is exposed.")

func _community():
	title_label.text="Community Settings"
	var mode=_panel("Score mode","RPL is used when Spin is not selected. RPS is used when Spin is selected. RPV is not supported by this client.")
	var spin=RhythianUI.check_button("Spin mode",spin_enabled)
	spin.connect("toggled",self,"_spin_toggled")
	mode.add_child(spin)
	var web=_panel("Website settings","Privacy and other web-only community settings remain on Rhythians.")
	var open=_button(web,"Open Community Settings",true)
	open.connect("pressed",RhythianUI,"open_url",[BASE_URL+"/community-settings"])

func _account():
	title_label.text="Account"
	if not Rhythian.logged_in:
		var p=_panel("Not signed in","Use the same Rhythians account as the website.")
		var login=_button(p,"Sign in",true)
		login.connect("pressed",self,"_login")
		return
	var p=_panel(Rhythian.username,"%d RHP" % int(Rhythian.profile.get("rhp",0)))
	var refresh=_button(p,"Refresh profile",true)
	refresh.connect("pressed",Rhythian,"fetch_profile")
	var open=_button(p,"Open profile")
	open.connect("pressed",RhythianUI,"open_url",[BASE_URL+"/profile/"+Rhythian.username])
	var logout=_button(p,"Log out")
	logout.connect("pressed",Rhythian,"logout")

func _battles():
	title_label.text="Battles"
	if not Rhythian.logged_in:
		var need=_panel("Sign in required","Battles use the same Rhythians account and database as the website.")
		var login=_button(need,"Sign in",true)
		login.connect("pressed",self,"_login")
		return
	var connection=_panel("Connection","Battles use HTTPS through the user's normal internet connection. The client does not connect directly to PostgreSQL or Supabase credentials. Server/database errors are surfaced below.")
	var check=_button(connection,"Check connection")
	check.connect("pressed",self,"_check_connection")
	if battle.match_id != "":
		_battle_match_view()
	else:
		var queue=_panel("Find a battle","Ranked battles award RBP only. Casual battles do not modify RBP.")
		var row=RhythianUI.hbox(10)
		queue.add_child(row)
		var modes=RhythianUI.option_button(["1v1","2v2","3v3","15v15"],0,100)
		row.add_child(modes)
		modes.connect("item_selected",self,"_battle_mode")
		var kinds=RhythianUI.option_button(["Ranked","Casual"],0,100)
		row.add_child(kinds)
		kinds.connect("item_selected",self,"_battle_type")
		var find=_button(row,"Find opponent",true)
		find.connect("pressed",self,"_queue_battle")
		var lobby=_panel("Lobbies","Create or join a live lobby. Lobby state, ready state, map votes, chat and match creation stay synchronized with the website database.")
		var create_row=RhythianUI.hbox(10)
		lobby.add_child(create_row)
		var name=_line(create_row,"Lobby name")
		var create=_button(create_row,"Create lobby",true)
		create.connect("pressed",self,"_create_lobby",[name])
		var refresh=_button(lobby,"Refresh lobbies")
		refresh.connect("pressed",self,"_refresh_lobbies")
		if battle.lobby_data.size()>0:
			_render_lobby(lobby)
		elif not status.text.begins_with("Could"):
			_refresh_lobbies()
	if status.text=="":
		status.text="Ready"

func _battle_match_view():
	var data=battle.match_data
	var match=data.get("match",{})
	var mode=str(match.get("mode","1v1")).split(":")[0]
	var panel=_panel("Battle %s" % mode,"Status: %s · %s" % [str(match.get("status","unknown")),str(match.get("matchType","casual"))])
	var actions=RhythianUI.hbox(10)
	panel.add_child(actions)
	if str(match.get("status",""))=="map_vote":
		var options=data.get("options",[])
		for option in options:
			var map_id=str(option.get("mapId",""))
			var label="%s" % str(option.get("title","Map"))
			var vote=_button(actions,label)
			vote.connect("pressed",self,"_vote_map",[map_id])
	else:
		var check=_button(actions,"Check score",true)
		check.connect("pressed",self,"_check_battle_score")
		var reconnect=_button(actions,"Reconnect")
		reconnect.connect("pressed",self,"_reconnect_battle")
	var leave=_button(actions,"Forfeit")
		leave.connect("pressed",self,"_forfeit_battle")
	var players=data.get("players",[])
	for player in players:
		var accuracy=player.get("accuracy",null)
		_panel(str(player.get("displayName",player.get("username","Player"))),"Team %d · %s" % [int(player.get("team",0)),accuracy == null ? "No score yet" : "%.2f%%" % float(accuracy)])
	if data.get("map",null)!=null:
		var map=data["map"]
		_panel("Battle map",str(map.get("title","Unknown map")))
	var scores=data.get("teamScores",{})
	if scores.size()>0:
		_panel("Team scores","Team 1: %s · Team 2: %s" % [str(scores.get("one","—")),str(scores.get("two","—"))])
	if str(match.get("status",""))=="finished":
		var end=_button(panel,"Return to battle finder",true)
		end.connect("pressed",self,"_clear_battle")

func _render_lobby(parent:VBoxContainer):
	var lobby=battle.lobby_data.get("lobby",{})
	parent.add_child(RhythianUI.label("Lobby %s" % str(lobby.get("name","Lobby")),16,RhythianUI.C_WHITE,1))
	var members=battle.lobby_data.get("members",[])
	parent.add_child(RhythianUI.label("%d/%d players" % [members.size(),int(lobby.get("maxPlayers",0))],13,RhythianUI.C_MUTED))
	for member in members:
		var row=RhythianUI.hbox(8)
		parent.add_child(row)
		row.add_child(RhythianUI.label(str(member.get("displayName",member.get("username","Player"))),13,RhythianUI.C_WHITE))
		row.add_child(RhythianUI.label("Ready" if bool(member.get("isReady",false)) else "Not ready",12,RhythianUI.C_MUTED))
	var actions=RhythianUI.hbox(8)
	parent.add_child(actions)
	var ready=_button(actions,"Ready")
	ready.connect("pressed",self,"_lobby_action",["ready",{}])
	var vote=_button(actions,"Vote random map")
	vote.connect("pressed",self,"_lobby_action",["vote",{"mapId":"random"}])
	var start=_button(actions,"Start match",true)
	start.connect("pressed",self,"_lobby_action",["start",{}])
	var leave=_button(actions,"Leave lobby")
	leave.connect("pressed",self,"_leave_lobby")
	var messages=battle.lobby_data.get("messages",[])
	for message in messages:
		parent.add_child(RhythianUI.label("%s: %s" % [str(message.get("username","Player")),str(message.get("content",""))],12,RhythianUI.C_MUTED))
	var message_row=RhythianUI.hbox(8)
	parent.add_child(message_row)
	var field=_line(message_row,"Lobby message")
	var send=_button(message_row,"Send")
	send.connect("pressed",self,"_send_lobby_message",[field])

func _clips():
	title_label.text="Clips"
	if not Rhythian.logged_in:
		var need=_panel("Sign in required","Sign in with the same Rhythians account used on the website to browse and submit clips.")
		var login=_button(need,"Sign in",true)
		login.connect("pressed",self,"_login")
		return
	var feed=_panel("Community clips","Approved clips are loaded from the Rhythians database. Video URLs are signed storage URLs and expire automatically.")
	var refresh=_button(feed,"Refresh clips",true)
	refresh.connect("pressed",self,"_refresh_clips")
	var submit=_panel("Submit a clip","Upload a local MP4, WebM, or MOV. The upload and moderation submission happen through the authenticated Rhythians API.")
	clip_title=_line(submit,"Title")
	clip_song=_line(submit,"Song / map name")
	clip_description=TextEdit.new()
	clip_description.placeholder_text="Description"
	clip_description.rect_min_size.y=100
	submit.add_child(clip_description)
	var mode_row=RhythianUI.hbox(8)
	submit.add_child(mode_row)
	for mode in ["lock","spin","vr"]:
		var mode_button=_button(mode_row,mode.capitalize())
		mode_button.connect("pressed",self,"_set_clip_mode",[mode])
	var choose=_button(submit,"Choose video")
	choose.connect("pressed",self,"_choose_clip_file")
	if clips.get("last_error","")!="":
		status.text=clips.get("last_error")
	var list_result=yield(clips.list_clips(24),"completed")
	if not list_result.get("ok",false):
		_panel("Clip feed unavailable",list_result.get("message","Could not load clips."))
		return
	var items=list_result.get("clips",[])
	if items.empty():
		_panel("No approved clips","There are no approved clips to show right now.")
		return
	for item in items:
		var box=_panel(str(item.get("title","Untitled")),"%s · %s" % [str(item.get("uploader",{}).get("username","Unknown")),str(item.get("songName",""))])
		box.add_child(RhythianUI.label("Mode: %s" % str(item.get("cameraMode","unknown")),12,RhythianUI.C_MUTED))
		var watch=_button(box,"Watch clip",true)
		watch.connect("pressed",self,"_watch_clip",[str(item.get("videoUrl",""))])

func _watch_clip(url:String):
	if url=="":
		status.text="This clip does not currently have a playable storage URL."
		return
	OS.shell_open(url)
	status.text="Opened the clip in the system media/browser handler. Native MP4/MOV playback is not provided by this Godot build."

func _choose_clip_file():
	if clip_file_dialog==null:
		clip_file_dialog=FileDialog.new()
		clip_file_dialog.mode=FileDialog.MODE_OPEN_FILE
		clip_file_dialog.access=FileDialog.ACCESS_FILESYSTEM
		clip_file_dialog.filters=PoolStringArray(["*.mp4 ; MP4 video","*.webm ; WebM video","*.mov ; MOV video"])
		add_child(clip_file_dialog)
		clip_file_dialog.connect("file_selected",self,"_submit_clip_file")
	clip_file_dialog.popup_centered_ratio()

func _submit_clip_file(path:String):
	if clip_title==null or clip_title.text.strip_edges()=="":
		status.text="Enter a clip title first."
		return
	status.text="Uploading clip..."
	var result=yield(clips.submit(path,clip_title.text,clip_song.text,clip_description.text,clip_mode),"completed")
	if not result.get("ok",false):
		status.text=result.get("message","Clip upload failed.")
		return
	status.text="Clip submitted for moderation."
	clip_title.text=""
	clip_song.text=""
	clip_description.text=""
	clip_mode=""
	show_page("clips")

func _clip_upload_finished(success:bool,message:String):
	if success: status.text=message

func _set_clip_mode(mode:String):
	clip_mode=mode
	status.text="Camera mode selected: %s" % mode.capitalize()

func _login():
	title_label.text="Sign in"
	_clear()
	var p=_panel("Waiting for authorization","The existing Rhythians device authorization flow opens the verification page and waits for approval.")
	var cancel=_button(p,"Cancel")
	cancel.connect("pressed",Rhythian,"cancel_login")
	Rhythian.start_login()

func _check_all_scores():
	if not Rhythian.logged_in:
		status.text="Sign in before checking scores."
		return
	status.text="Checking all eligible scores..."
	var result=yield(Rhythian._api_request(HTTPClient.METHOD_POST,"/api/maps/check-all",{},true,60.0),"completed")
	if not result.get("ok",false):
		status.text=Rhythian._http_error_message(result,"score check")
		return
	var body=result.get("json",{})
	status.text="Synced %d scores · RPL %d · RPS %d · RHP %d" % [int(body.get("foundScores",0)),int(body.get("rpl",0)),int(body.get("rps",0)),int(body.get("rhp",0))]
	Rhythian.fetch_profile()
	Rhythian.fetch_scores()

func _mode_totals():
	var totals={"rpl":0,"rps":0}
	for score in Rhythian.scores_cache:
		if typeof(score)!=TYPE_DICTIONARY or not bool(score.get("passed",false)): continue
		var explicit=str(score.get("cameraMode",score.get("gameMode",score.get("mode","")))).to_lower()
		if explicit=="vr" or bool(score.get("vr",false)) or bool(score.get("isVr",false)): continue
		var spin=explicit=="spin" or bool(score.get("spin",false)) or (typeof(score.get("mods",""))==TYPE_STRING and String(score.get("mods","")).findn("spin")>=0)
		var accuracy=clamp(float(score.get("accuracy",100.0))/100.0,0.0,1.0)
		if spin: totals["rps"]+=max(1,int(round(30.0*accuracy)))
		else: totals["rpl"]+=max(1,int(round(25.0*accuracy)))
	return totals

func _check_connection():
	status.text="Checking internet, Rhythians API, and database health..."
	Rhythian.check_connection()

func _queue_battle():
	status.text="Finding opponent..."
	var result=yield(battle.queue_match(battle_mode,battle_type),"completed")
	if not result.get("ok",false):
		return
	battle.match_id=str(result.get("matchId",battle.match_id))
	status.text="Battle queued. Waiting for the other players..."
	battle.refresh_match()

func _battle_mode(index:int):
	battle_mode=["1v1","2v2","3v3","15v15"][index]

func _battle_type(index:int):
	battle_type="ranked" if index==0 else "casual"

func _check_battle_score():
	status.text="Checking battle score..."
	var result=yield(battle.battle_action("check-score"),"completed")
	if not result.get("ok",false): return
	status.text="Battle score submitted."
	battle.refresh_match()

func _vote_map(map_id:String):
	status.text="Submitting map vote..."
	var result=yield(battle.battle_action("vote-map",{"mapId":map_id}),"completed")
	if result.get("ok",false):
		status.text="Map vote submitted."

func _reconnect_battle():
	status.text="Reconnecting to battle..."
	var result=yield(battle.battle_action("reconnect"),"completed")
	if result.get("ok",false): status.text="Battle connection restored."

func _forfeit_battle():
	var result=yield(battle.battle_action("forfeit"),"completed")
	if result.get("ok",false):
		status.text="Battle forfeited."
		battle.match_id=""
		battle.match_data={}
		show_page("battles")

func _clear_battle():
	battle.match_id=""
	battle.match_data={}
	status.text="Battle finder ready."
	show_page("battles")

func _create_lobby(name:LineEdit):
	if name.text.strip_edges()=="":
		status.text="Enter a lobby name."
		return
	var result=yield(battle.create_lobby(name.text,battle_mode,battle_type),"completed")
	if not result.get("ok",false): return
	status.text="Lobby created."
	show_page("battles")

func _refresh_lobbies():
	var result=yield(battle.list_lobbies(),"completed")
	if not result.get("ok",false): return
	status.text="Loaded %d open lobbies." % result.get("lobbies",[]).size()
	for lobby in result.get("lobbies",[]):
		var row=_panel(str(lobby.get("name","Lobby")),"%s · %s · %d/%d" % [str(lobby.get("mode","1v1")),str(lobby.get("matchType","casual")),int(lobby.get("playerCount",0)),int(lobby.get("maxPlayers",0))])
		var join=_button(row,"Join lobby",true)
		join.connect("pressed",self,"_join_lobby",[str(lobby.get("id",""))])

func _join_lobby(id:String):
	battle.lobby_id=id
	var result=yield(battle.lobby_action("join"),"completed")
	if not result.get("ok",false): return
	status.text="Joined lobby."
	show_page("battles")

func _lobby_action(action:String,extra:Dictionary):
	var result=yield(battle.lobby_action(action,extra),"completed")
	if result.get("ok",false):
		status.text="Lobby updated."

func _leave_lobby():
	var result=yield(battle.lobby_action("leave"),"completed")
	if result.get("ok",false):
		battle.lobby_id=""
		battle.lobby_data={}
		status.text="Left lobby."
		show_page("battles")

func _send_lobby_message(field:LineEdit):
	if field.text.strip_edges()=="": return
	var result=yield(battle.lobby_action("message",{"content":field.text}),"completed")
	if result.get("ok",false):
		field.text=""
		status.text="Message sent."

func _spin_toggled(value:bool):
	spin_enabled=value
	_save_settings()
	show_page(selected_page)
