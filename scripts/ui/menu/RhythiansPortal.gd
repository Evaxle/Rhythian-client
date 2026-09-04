extends Control

const BASE_URL = "https://rhythians-evans-projects-edff1a37.vercel.app"
const SETTINGS_FILE = "user://rhythian/client-settings.json"

var title_label:Label
var content:VBoxContainer
var status:Label
var selected_page="home"
var spin_enabled=false
var battle_mode="1v1"
var battle_type="ranked"
var battle:Node
var clips:Node
var search_query=""
var chat_handle=""
var global_refresh_accum=0.0
var direct_refresh_accum=0.0

func _ready():
	Rhythian.base_url=BASE_URL
	_load_settings()
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	anchor_right=1.0
	anchor_bottom=1.0
	visible=false
	var margin=MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_WIDE)
	margin.margin_left=40
	margin.margin_right=-40
	margin.margin_top=86
	margin.margin_bottom=-24
	add_child(margin)
	var scroll=ScrollContainer.new()
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var root=VBoxContainer.new()
	root.add_constant_override("separation",14)
	root.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(root)
	title_label=RhythianUI.label("Home",34,RhythianUI.C_WHITE,1)
	root.add_child(title_label)
	root.add_child(RhythianUI.label("Rhythians inside Rhythia",14,RhythianUI.C_MUTED))
	content=RhythianUI.vbox(12)
	root.add_child(content)
	status=RhythianUI.label("",13,RhythianUI.C_MUTED)
	root.add_child(status)
	battle=load("res://scripts/network/BattleClient.gd").new()
	add_child(battle)
	battle.start()
	battle.connect("state_changed",self,"_battle_state_changed")
	battle.connect("error",self,"_network_error")
	clips=load("res://scripts/network/ClipClient.gd").new()
	add_child(clips)
	clips.connect("upload_finished",self,"_clip_upload_finished")
	Rhythian.connect("auth_changed",self,"_refresh_page")
	Rhythian.connect("profile_updated",self,"_refresh_page")
	Rhythian.connect("maps_updated",self,"_refresh_page")
	Rhythian.connect("connection_checked",self,"_connection_checked")
	show_page("home")
	Rhythian.check_connection()

func _process(delta:float):
	if not visible: return
	global_refresh_accum+=delta
	direct_refresh_accum+=delta
	if selected_page=="global-chat" and global_refresh_accum>=3.0:
		global_refresh_accum=0.0
		if get_focus_owner()==null or not (get_focus_owner() is LineEdit): _refresh_global_chat_silent()
	if selected_page=="messages" and chat_handle!="" and direct_refresh_accum>=3.0:
		direct_refresh_accum=0.0
		if get_focus_owner()==null or not (get_focus_owner() is LineEdit): _refresh_direct_silent()

func open_page(page:String):
	visible=true
	show_page(page)

func close_page():
	visible=false

func _refresh_page(_a=null,_b=null):
	show_page(selected_page)

func _battle_state_changed(_data):
	if selected_page=="battles": show_page("battles")

func _network_error(message:String):
	status.text=message
	if selected_page=="battles": show_page("battles")

func _connection_checked(web_ok:bool,db_ok:bool):
	if selected_page=="home": status.text="Internet: %s · Rhythians API: %s · Database: %s" % ["connected" if web_ok else "offline","online" if web_ok else "unavailable","connected" if db_ok else "unavailable"]

func _load_settings():
	var file=File.new()
	if not file.file_exists(Globals.p(SETTINGS_FILE)): return
	if file.open(Globals.p(SETTINGS_FILE),File.READ)!=OK: return
	var parsed=JSON.parse(file.get_as_text())
	file.close()
	if parsed.error==OK and typeof(parsed.result)==TYPE_DICTIONARY: spin_enabled=bool(parsed.result.get("spinEnabled",false))

func _save_settings():
	var file=File.new()
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
	RhythianUI.input_style(field)
	parent.add_child(field)
	return field

func show_page(page:String):
	selected_page=page
	global_refresh_accum=0.0
	direct_refresh_accum=0.0
	_clear()
	match page:
		"home": _home()
		"maps": _maps()
		"daily": _daily()
		"path": _path()
		"challenge": _challenge()
		"online": _online()
		"leaderboards": _leaderboards()
		"battles": _battles()
		"clips": _clips()
		"search": _search()
		"messages": _messages()
		"global-chat": _global_chat()
		"wiki": _wiki()
		"rules": _rules()
		"community": _community()
		"account": _account()
		"profile": _profile(Rhythian.username)
		_: _home()

func _api_page(page:String,extra:Dictionary={}) -> Dictionary:
	var query="page="+page
	for k in extra.keys(): query += "&"+str(k).http_escape()+"="+str(extra[k]).http_escape()
	var result=yield(Rhythian._api_request(HTTPClient.METHOD_GET,"/api/rhythkit/portal?"+query,null,true,35.0),"completed")
	if not result.get("ok",false): return {"ok":false,"message":Rhythian._http_error_message(result,page)}
	var json=result.get("json",{})
	if typeof(json)!=TYPE_DICTIONARY: return {"ok":false,"message":"The Rhythians API returned an invalid response."}
	json["ok"]=true
	return json

func _home():
	title_label.text="Home"
	var account=_panel("Account",Rhythian.logged_in ? "%s · %d RHP" % [Rhythian.username,int(Rhythian.profile.get("rhp",0))] : "Not signed in")
	var row=RhythianUI.hbox(10)
	account.add_child(row)
	if Rhythian.logged_in:
		var refresh=_button(row,"Refresh account")
		refresh.connect("pressed",Rhythian,"fetch_profile")
		var profile=_button(row,"Open profile")
		profile.connect("pressed",self,"open_page",["profile"])
		var logout=_button(row,"Log out")
		logout.connect("pressed",Rhythian,"logout")
	else:
		var login=_button(row,"Sign in with Rhythians",true)
		login.connect("pressed",self,"_login")
	var score=_panel("Score pools","RPL is used when Spin is disabled. RPS is used when Spin is enabled. RPV is not supported in this client. RBP remains battle-only.")
	var totals=_mode_totals()
	var points=RhythianUI.hbox(22)
	score.add_child(points)
	points.add_child(RhythianUI.label("RPL %d" % totals["rpl"],18,RhythianUI.C_WHITE,1))
	points.add_child(RhythianUI.label("RPS %d" % totals["rps"],18,RhythianUI.C_WHITE,1))
	points.add_child(RhythianUI.label("RHP %d" % int(Rhythian.profile.get("rhp",0)),18,RhythianUI.C_WHITE,1))
	var actions=_panel("Quick actions")
	var ar=RhythianUI.hbox(10)
	actions.add_child(ar)
	for pair in [["Maps","maps"],["Daily","daily"],["Path","path"],["Challenge","challenge"],["Battles","battles"],["Clips","clips"],["Global Chat","global-chat"],["Search","search"]]:
		var b=_button(ar,pair[0],pair[1]=="battles")
		b.connect("pressed",self,"open_page",[pair[1]])
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
	var banner=_panel("Current rank","%s · %d RHP · ranked maps outside your current range are not eligible for RHP." % [str(rank.name),rhp])
	var refresh=_button(banner,"Refresh maps",true)
	refresh.connect("pressed",Rhythian,"fetch_maps")
	if Rhythian.maps_cache.empty():
		_panel("Map catalog",Rhythian.maps_error if Rhythian.maps_error!="" else "No maps loaded yet.")
		return
	for i in range(min(40,Rhythian.maps_cache.size())):
		var map=Rhythian.maps_cache[i]
		var row=_panel(str(map.get("title","Unknown map")),"%.2f rating" % Rhythian.get_map_rating(map))
		if str(map.get("mapFileUrl",""))!="":
			var play=_button(row,"Download / Play")
			play.connect("pressed",RhythianUI,"open_url",[str(map.get("mapFileUrl"))])

func _daily():
	title_label.text="Daily"
	var data=yield(_api_page("daily"),"completed")
	if not data.get("ok",false):
		_panel("Daily unavailable",data.get("message","Could not load daily."))
		return
	var daily=data.get("daily",{})
	var card=_panel("Today's map","%s · %s · %.2f rating" % [str(daily.get("title","Daily map")),str(data.get("formattedDate","")),float(daily.get("starRating",0))])
	card.add_child(RhythianUI.label("%s · %s" % [str(daily.get("artist","")),str(daily.get("mapperName",""))],14))
	card.add_child(RhythianUI.label("Reward: %d RHP at 100%% · streak %d" % [int(daily.get("reward",0)),int(data.get("streak",0))],14,RhythianUI.C_ACCENT2,1))
	var beat=data.get("beat",null)
	if beat!=null: card.add_child(RhythianUI.label("Completed · %s%% · %d points · %d misses" % [str(beat.get("accuracy",0)),int(beat.get("points",0)),int(beat.get("misses",0))],14))
	else: card.add_child(RhythianUI.label("Not completed yet",14))
	if str(daily.get("downloadUrl",""))!="":
		var play=_button(card,"Download / Play daily map",true)
		play.connect("pressed",RhythianUI,"open_url",[str(daily.get("downloadUrl"))])

func _path():
	title_label.text="Path"
	var data=yield(_api_page("path"),"completed")
	if not data.get("ok",false): _panel("Path unavailable",data.get("message","Could not load path.")); return
	var path=data.get("path",{})
	_panel("Seasonal Rhythian Path","Season %s · ends %s" % [str(path.get("season",{}).get("seasonNumber","")),str(path.get("season",{}).get("endsAt",""))])
	for rank in path.get("ranks",[]):
		var box=_panel(str(rank.get("name","Rank")),"Rank %d" % int(rank.get("index",0)+1))
		var map=rank.get("map",null)
		if map!=null:
			box.add_child(RhythianUI.label("%s · %.2f rating" % [str(map.get("title","Map")),float(map.get("rating",0))],14))
			box.add_child(RhythianUI.label("%s" % ("Completed" if bool(map.get("completed",false)) else "Not completed"),14,RhythianUI.C_ACCENT2 if bool(map.get("completed",false)) else RhythianUI.C_MUTED,1))

func _challenge():
	title_label.text="Challenge"
	var data=yield(_api_page("challenge"),"completed")
	if not data.get("ok",false): _panel("Challenge unavailable",data.get("message","Could not load challenge.")); return
	_panel("Challenge progression","Current level %d" % int(data.get("level",0)))
	for map in data.get("maps",[]):
		var box=_panel(str(map.get("title","Challenge map")),"Level %s · %s" % [str(map.get("level",map.get("rank",0))),"Passed" if bool(map.get("completed",false)) else "Available"])
		var url=str(map.get("mapFileUrl",map.get("downloadUrl","")))
		if url!="":
			var play=_button(box,"Download / Play map")
			play.connect("pressed",RhythianUI,"open_url",[url])

func _online():
	title_label.text="Online"
	var data=yield(_api_page("online"),"completed")
	if not data.get("ok",false): _panel("Online unavailable",data.get("message","Could not load online users.")); return
	var users=data.get("users",[])
	_panel("Who's online","%d users currently online" % users.size())
	for user in users:
		var row=_panel(str(user.get("displayName",user.get("username","User"))),"%d RHP · #%s global · Level %s" % [int(user.get("rhp",0)),str(user.get("globalPosition","-")),str(user.get("challengeLevel",0))])
		var open=_button(row,"View profile")
		open.connect("pressed",self,"open_profile_handle",[str(user.get("profileHandle",""))])
		var message=_button(row,"Message")
		message.connect("pressed",self,"open_message_handle",[str(user.get("profileHandle",""))])

func _leaderboards():
	title_label.text="Leaderboards"
	var data=yield(_api_page("leaderboards"),"completed")
	if not data.get("ok",false): _panel("Leaderboards unavailable",data.get("message","Could not load leaderboards.")); return
	var rhp=data.get("rhp",[])
	var board=_panel("RHP global","Top Rhythians")
	for i in range(min(50,rhp.size())):
		var user=rhp[i]
		var row=_panel("#%d · %s · %d RHP" % [int(user.get("position",i+1)),str(user.get("displayName",user.get("username",""))),int(user.get("rhp",0))])
		var open=_button(row,"Profile")
		open.connect("pressed",self,"open_profile_handle",[str(user.get("profileHandle",""))])
	var modes=data.get("modes",{})
	for mode_name in ["lock","spin"]:
		var mode_box=_panel(mode_name.to_upper(),"Mode leaderboard")
		for i in range(min(20,modes.get(mode_name,[]).size())): mode_box.add_child(RhythianUI.label("#%d %s" % [i+1,str(modes[mode_name][i].get("username",modes[mode_name][i].get("displayName","Player")))],13))

func _battles():
	title_label.text="Battles"
	if not Rhythian.logged_in:
		var need=_panel("Sign in required","Battles use your Rhythians installation account.")
		var login=_button(need,"Sign in",true)
		login.connect("pressed",self,"_login")
		return
	var connection=_panel("Connection","HTTPS API + live database state. Connection failures are shown here.")
	var check=_button(connection,"Check connection")
	check.connect("pressed",self,"_check_connection")
	if battle.match_id!="": _battle_match_view(); return
	if battle.lobby_id!="": _render_lobby(_panel("Active lobby")); return
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
	var lobby=_panel("Lobbies","Live lobby list, ready state, map votes and chat.")
	var create_row=RhythianUI.hbox(10)
	lobby.add_child(create_row)
	var name=_line(create_row,"Lobby name")
	var create=_button(create_row,"Create lobby",true)
	create.connect("pressed",self,"_create_lobby",[name])
	var refresh=_button(lobby,"Refresh")
	refresh.connect("pressed",self,"_refresh_lobbies")
	_refresh_lobbies()

func _battle_match_view():
	var data=battle.match_data
	var match=data.get("match",{})
	var mode=str(match.get("mode","1v1")).split(":")[0]
	var panel=_panel("Battle %s" % mode,"Status: %s · %s" % [str(match.get("status","unknown")),str(match.get("matchType","casual"))])
	for player in data.get("players",[]): panel.add_child(RhythianUI.label("Team %d · %s · %s" % [int(player.get("team",0)),str(player.get("displayName",player.get("username","Player"))),player.get("accuracy",null)==null ? "—" : "%.2f%%" % float(player.get("accuracy"))],14))
	var map=data.get("map",null)
	if map!=null: panel.add_child(RhythianUI.label("Map: %s" % str(map.get("title","Unknown")),16,RhythianUI.C_ACCENT,1))
	var actions=RhythianUI.hbox(10)
	panel.add_child(actions)
	if str(match.get("status",""))=="map_vote":
		for option in data.get("options",[]):
			var vote=_button(actions,str(option.get("title","Map")))
			vote.connect("pressed",self,"_vote_map",[str(option.get("mapId",""))])
	else:
		var score=_button(actions,"Check score",true)
		score.connect("pressed",self,"_check_battle_score")
		var reconnect=_button(actions,"Reconnect")
		reconnect.connect("pressed",self,"_reconnect_battle")
	var leave=_button(actions,"Forfeit")
	leave.connect("pressed",self,"_forfeit_battle")
	if str(match.get("status",""))=="finished":
		var back=_button(actions,"Return")
		back.connect("pressed",self,"_return_battles")

func _render_lobby(parent:VBoxContainer):
	var lobby=battle.lobby_data.get("lobby",battle.lobby_data)
	parent.add_child(RhythianUI.label("%s · %s · %s" % [str(lobby.get("name","Lobby")),str(lobby.get("mode","1v1")),str(lobby.get("matchType","casual"))],16))
	for member in battle.lobby_data.get("members",[]): parent.add_child(RhythianUI.label("%s · %s" % [str(member.get("displayName",member.get("username","User"))),"Ready" if bool(member.get("isReady",false)) else "Not ready"],14))
	var actions=RhythianUI.hbox(8)
	parent.add_child(actions)
	var ready=_button(actions,"Ready")
	ready.connect("pressed",self,"_lobby_action",["ready",{}])
	var leave=_button(actions,"Leave")
	leave.connect("pressed",self,"_leave_lobby")
	var start=_button(actions,"Start match",true)
	start.connect("pressed",self,"_lobby_action",["start",{}])
	var maps=_button(actions,"Vote random map")
	maps.connect("pressed",self,"_lobby_action",["vote",{"mapId":"random"}])
	var msg=_line(parent,"Lobby chat message")
	var send=_button(parent,"Send lobby message")
	send.connect("pressed",self,"_lobby_action",["message",{"content":""},msg])
	for entry in battle.lobby_data.get("messages",[]): parent.add_child(RhythianUI.label("%s: %s" % [str(entry.get("username","User")),str(entry.get("content",""))],13))

func _clips():
	title_label.text="Clips"
	var head=_panel("Community clips","Watch approved clips, search by song, and submit your own.")
	var row=RhythianUI.hbox(10)
	head.add_child(row)
	var search=_line(row,"Search by song",search_query)
	var go=_button(row,"Search",true)
	go.connect("pressed",self,"_search_clips",[search])
	var upload=_button(row,"Submit clip")
	upload.connect("pressed",self,"_open_clip_submit")
	var data=yield(_api_page("clips",{"song":search_query}),"completed")
	if not data.get("ok",false): _panel("Clips unavailable",data.get("message","Could not load clips.")); return
	for clip in data.get("clips",[]):
		var panel=_panel(str(clip.get("title","Clip")),"%s · %s · %s" % [str(clip.get("uploader",{}).get("displayName",clip.get("uploader",{}).get("username",""))),str(clip.get("songName","")),str(clip.get("cameraMode",""))])
		var watch=_button(panel,"Watch clip",true)
		watch.connect("pressed",self,"_watch_clip",[clip])
		var open_profile=_button(panel,"Creator profile")
		open_profile.connect("pressed",self,"open_profile_handle",[str(clip.get("uploader",{}).get("profileHandle",""))])

func _watch_clip(clip:Dictionary):
	var url=str(clip.get("videoUrl",""))
	if url=="":
		status.text="This clip has no playable video URL."
		return
	OS.shell_open(url)
	status.text="Opening clip video. The current Godot 3 client does not provide an embedded MP4/WebM/MOV browser codec, so the signed video is opened by the system player."

func _open_clip_submit():
	var panel=_panel("Submit a clip","Choose a local MP4, WebM or MOV and submit it for review.")
	var row=RhythianUI.hbox(8)
	panel.add_child(row)
	var title=_line(row,"Title")
	var song=_line(row,"Song / map")
	var path=_line(row,"Absolute path to video")
	var mode=RhythianUI.option_button(["lock","spin","vr"],0,100)
	row.add_child(mode)
	var submit=_button(panel,"Upload and submit",true)
	submit.connect("pressed",self,"_submit_clip_fields",[title,song,path,mode])

func _search_clips(field:LineEdit):
	search_query=field.text.strip_edges()
	show_page("clips")

func _submit_clip_fields(title:LineEdit,song:LineEdit,path:LineEdit,mode:OptionButton):
	status.text="Uploading clip..."
	var result=yield(clips.submit(path.text,title.text,song.text,"",mode.get_item_text(mode.selected)),"completed")
	status.text=str(result.get("message","Clip submission finished."))
	if result.get("ok",false): show_page("clips")

func _clip_upload_finished(_success:bool,message:String): status.text=message

func _search():
	title_label.text="Search users"
	var panel=_panel("User search","Search usernames, display names, or profile handles.")
	var row=RhythianUI.hbox(8)
	panel.add_child(row)
	var field=_line(row,"Search users",search_query)
	var go=_button(row,"Search",true)
	go.connect("pressed",self,"_run_user_search",[field])
	if search_query!="": _render_user_search(search_query)

func _run_user_search(field:LineEdit):
	search_query=field.text.strip_edges()
	show_page("search")

func _render_user_search(query:String):
	var data=yield(_api_page("search",{"q":query}),"completed")
	if not data.get("ok",false): _panel("Search failed",data.get("message","Could not search users.")); return
	for user in data.get("users",[]):
		var row=_panel(str(user.get("displayName",user.get("username","User"))),"@%s · %d RHP · %s" % [str(user.get("profileHandle","")),int(user.get("rhp",0)),"Online" if bool(user.get("online",false)) else "Offline"])
		var profile=_button(row,"Profile")
		profile.connect("pressed",self,"open_profile_handle",[str(user.get("profileHandle",""))])
		var msg=_button(row,"Message")
		msg.connect("pressed",self,"open_message_handle",[str(user.get("profileHandle",""))])

func _profile(handle:String):
	title_label.text="Profile"
	var data=yield(_api_page("profile",{"handle":handle}),"completed")
	if not data.get("ok",false): _panel("Profile unavailable",data.get("message","Could not load profile.")); return
	var p=data.get("profile",{})
	var main=_panel(str(p.get("displayName",p.get("username","User"))),"@%s · %s · %d RHP" % [str(p.get("profileHandle","")),str(p.get("title","Rhythian")),int(p.get("rhp",0))])
	main.add_child(RhythianUI.label("Rank: %s %s · Global #%s · Challenge Level %s · %s" % [str(p.get("rank",{}).get("name","")),str(p.get("rank",{}).get("tier","")),str(p.get("globalRank","-")),str(p.get("challengeLevel",0)),"Online" if bool(p.get("online",false)) else "Offline"],14))
	main.add_child(RhythianUI.label("RPL %d · RPS %d" % [int(p.get("modes",{}).get("rpl",0)),int(p.get("modes",{}).get("rps",0))],14))
	if str(p.get("bio",""))!="": main.add_child(RhythianUI.label(str(p.get("bio","")),14))
	var actions=RhythianUI.hbox(8)
	main.add_child(actions)
	if not bool(p.get("isOwnProfile",false)):
		var msg=_button(actions,"Message",true)
		msg.connect("pressed",self,"open_message_handle",[str(p.get("profileHandle",""))])
		var battle_btn=_button(actions,"Battle")
		battle_btn.connect("pressed",self,"open_page",["battles"])
	var clips_panel=_panel("Approved clips","%d clips" % p.get("clips",[]).size())
	for clip in p.get("clips",[]):
		var b=_button(clips_panel,str(clip.get("title","Clip")))
		b.connect("pressed",self,"_watch_clip",[clip])

func open_profile_handle(handle:String):
	selected_page="profile"
	_clear()
	_profile(handle)

func open_message_handle(handle:String):
	chat_handle=handle
	show_page("messages")

func _messages():
	title_label.text="Messages"
	if chat_handle==":": chat_handle=""
	if chat_handle=="":
		var panel=_panel("Direct messages","Choose a user from Search or Online to start a conversation.")
		var search=_button(panel,"Find a user",true)
		search.connect("pressed",self,"open_page",["search"])
		return
	var data=yield(_api_page("messages",{"user":chat_handle}),"completed")
	if not data.get("ok",false): _panel("Messages unavailable",data.get("message","Could not load conversation.")); return
	var target=data.get("target",{})
	_panel("Chat with %s" % str(target.get("displayName",target.get("username","User"))))
	for m in data.get("messages",[]): content.add_child(RhythianUI.label("%s: %s" % [str(m.get("sender",{}).get("displayName",m.get("sender",{}).get("username","User"))),str(m.get("content",""))],14))
	var row=RhythianUI.hbox(8)
	content.add_child(row)
	var input=_line(row,"Message")
	var send=_button(row,"Send",true)
	send.connect("pressed",self,"_send_direct",[target,input])

func _refresh_direct_silent():
	if chat_handle=="": return
	var data=yield(_api_page("messages",{"user":chat_handle}),"completed")
	if data.get("ok",false):
		var previous_focus=get_focus_owner()
		show_page("messages")
		if previous_focus!=null and previous_focus is LineEdit: previous_focus.grab_focus()

func _send_direct(target:Dictionary,input:LineEdit):
	if input.text.strip_edges()=="": return
	var result=yield(Rhythian._api_request(HTTPClient.METHOD_POST,"/api/rhythkit/portal",{"action":"direct-send","userId":str(target.get("id","")),"content":input.text.strip_edges()},true,25.0),"completed")
	if not result.get("ok",false): status.text=Rhythian._http_error_message(result,"message send"); return
	input.text=""
	show_page("messages")

func _global_chat():
	title_label.text="Global Chat"
	var data=yield(_api_page("global-chat"),"completed")
	if not data.get("ok",false): _panel("Global chat unavailable",data.get("message","Could not load global chat.")); return
	_panel("Global Rhythian Chat","All logged-in Rhythians share this channel. %d users online." % int(data.get("onlineCount",0)))
	for m in data.get("messages",[]): content.add_child(RhythianUI.label("%s: %s" % [str(m.get("sender",{}).get("displayName",m.get("sender",{}).get("username","User"))),str(m.get("content",""))],14))
	var row=RhythianUI.hbox(8)
	content.add_child(row)
	var input=_line(row,"Talk to everyone online")
	var send=_button(row,"Send",true)
	send.connect("pressed",self,"_send_global",[input])

func _refresh_global_chat_silent(): show_page("global-chat")

func _send_global(input:LineEdit):
	if input.text.strip_edges()=="": return
	var result=yield(Rhythian._api_request(HTTPClient.METHOD_POST,"/api/rhythkit/portal",{"action":"global-send","content":input.text.strip_edges()},true,25.0),"completed")
	if not result.get("ok",false): status.text=Rhythian._http_error_message(result,"global chat"); return
	input.text=""
	show_page("global-chat")

func _wiki():
	title_label.text="Wiki"
	var data=yield(_api_page("wiki"),"completed")
	if not data.get("ok",false): _panel("Wiki unavailable",data.get("message","Could not load wiki.")); return
	var articles=data.get("articles",[])
	_panel("Wiki","Published knowledge articles")
	for article in articles:
		var box=_panel(str(article.get("title","Article")),str(article.get("description",article.get("slug",""))))
		var body=RichTextLabel.new()
		body.bbcode_enabled=true
		body.fit_content_height=true
		body.rect_min_size.y=90
		body.text=str(article.get("content",""))
		box.add_child(body)

func _rules():
	title_label.text="Rules"
	var data=yield(_api_page("rules"),"completed")
	if not data.get("ok",false): _panel("Rules unavailable",data.get("message","Could not load rules.")); return
	for rule in data.get("rules",[]):
		var box=_panel(str(rule.get("title","Rule")),str(rule.get("description","")))
		var body=RichTextLabel.new()
		body.bbcode_enabled=true
		body.fit_content_height=true
		body.rect_min_size.y=80
		body.text=str(rule.get("content",""))
		box.add_child(body)

func _community():
	title_label.text="Community Settings"
	var mode=_panel("Score mode","RPL is used when Spin is not selected. RPS is used when Spin is selected. RPV is not supported by this client.")
	var spin=RhythianUI.check_button("Spin mode",spin_enabled)
	spin.connect("toggled",self,"_spin_toggled")
	mode.add_child(spin)

func _account():
	if not Rhythian.logged_in:
		title_label.text="Account"
		var p=_panel("Not signed in","Use the same Rhythians account as the website.")
		var login=_button(p,"Sign in",true)
		login.connect("pressed",self,"_login")
		return
	_profile(Rhythian.username)

func _login():
	_clear()
	title_label.text="Sign in"
	var p=_panel("Waiting for authorization","The existing Rhythians device authorization flow will open the verification page.")
	var cancel=_button(p,"Cancel")
	cancel.connect("pressed",Rhythian,"cancel_login")
	Rhythian.start_login()

func _check_connection():
	status.text="Checking connection..."
	Rhythian.check_connection()

func _battle_mode(index:int): battle_mode=["1v1","2v2","3v3","15v15"][index]
func _battle_type(index:int): battle_type="ranked" if index==0 else "casual"

func _queue_battle():
	if not Rhythian.logged_in: status.text="Sign in before entering battles."; return
	var result=yield(battle.queue_match(battle_mode,battle_type),"completed")
	if not result.get("ok",false): status.text=str(result.get("message","Could not queue battle.")); return
	battle.match_id=str(result.get("matchId",""))
	status.text="Finding opponent..."
	show_page("battles")

func _create_lobby(name:LineEdit):
	var lobby_name=name.text.strip_edges()
	if lobby_name=="": status.text="Enter a lobby name."; return
	var result=yield(battle.create_lobby(lobby_name,battle_mode,battle_type,"regular"),"completed")
	if not result.get("ok",false): status.text=str(result.get("message","Could not create lobby.")); return
	show_page("battles")

func _refresh_lobbies():
	var result=yield(battle.list_lobbies(),"completed")
	if not result.get("ok",false): status.text=str(result.get("message","Could not load lobbies.")); return
	for lobby in result.get("lobbies",[]):
		var row=_panel(str(lobby.get("name","Lobby")),"%s · %s · %d/%d · host %s" % [str(lobby.get("mode","1v1")),str(lobby.get("matchType","casual")),int(lobby.get("playerCount",0)),int(lobby.get("maxPlayers",0)),str(lobby.get("host",""))])
		var join=_button(row,"Join")
		join.connect("pressed",self,"_join_lobby",[str(lobby.get("id",""))])

func _join_lobby(id:String):
	battle.lobby_id=id
	var result=yield(battle.lobby_action("join"),"completed")
	if not result.get("ok",false): status.text=str(result.get("message","Could not join lobby."))
	show_page("battles")

func _lobby_action(action:String,extra:Dictionary,field=null):
	if field!=null: extra["content"]=field.text.strip_edges()
	var result=yield(battle.lobby_action(action,extra),"completed")
	if not result.get("ok",false): status.text=str(result.get("message","Lobby action failed."))
	show_page("battles")

func _leave_lobby(): _lobby_action("leave",{})

func _vote_map(map_id:String):
	var result=yield(battle.battle_action("vote-map",{"mapId":map_id}),"completed")
	if not result.get("ok",false): status.text=str(result.get("message","Vote failed."))

func _check_battle_score():
	var result=yield(battle.battle_action("check-score"),"completed")
	if not result.get("ok",false): status.text=str(result.get("message","Score check failed."))

func _reconnect_battle():
	var result=yield(battle.battle_action("reconnect"),"completed")
	if not result.get("ok",false): status.text=str(result.get("message","Reconnect failed."))

func _forfeit_battle():
	var result=yield(battle.battle_action("forfeit"),"completed")
	if not result.get("ok",false): status.text=str(result.get("message","Forfeit failed."))
	else: _return_battles()

func _return_battles():
	battle.match_id=""
	battle.match_data={}
	show_page("battles")

func _mode_totals():
	var totals={"rpl":0,"rps":0}
	for score in Rhythian.scores_cache:
		if typeof(score)!=TYPE_DICTIONARY or not bool(score.get("passed",false)): continue
		var explicit=str(score.get("cameraMode",score.get("gameMode",score.get("mode","")))).to_lower()
		if explicit=="vr" or bool(score.get("vr",false)) or bool(score.get("isVr",false)): continue
		var is_spin=explicit=="spin" or bool(score.get("spin",false)) or (typeof(score.get("mods",""))==TYPE_STRING and String(score.get("mods","")).findn("spin")>=0)
		var accuracy=clamp(float(score.get("accuracy",100.0))/100.0,0.0,1.0)
		if is_spin: totals["rps"]+=max(1,int(round(30.0*accuracy)))
		else: totals["rpl"]+=max(1,int(round(25.0*accuracy)))
	return totals

func _spin_toggled(value:bool):
	spin_enabled=value
	_save_settings()
	show_page(selected_page)
