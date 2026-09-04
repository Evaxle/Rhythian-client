extends Node

signal clips_updated(clips)
signal upload_progress(sent, total)
signal upload_finished(success, message)

var last_error:String = ""
const MAX_UPLOAD_BYTES:int = 524288000

func list_clips(limit:int=24) -> Dictionary:
	var result = yield(Rhythian._api_request(HTTPClient.METHOD_GET,"/api/rhythkit/clips?limit="+str(clamp(limit,1,50)),null,true,20.0),"completed")
	if not result.get("ok",false):
		last_error=Rhythian._http_error_message(result,"clips")
		return {"ok":false,"message":last_error}
	var body=result.get("json",{})
	var clip_list=body.get("clips",[]) if typeof(body)==TYPE_DICTIONARY else []
	last_error=""
	emit_signal("clips_updated",clip_list)
	return {"ok":true,"clips":clip_list}

func submit(file_path:String,title:String,song_name:String,description:String,camera_mode:String) -> Dictionary:
	if not Rhythian.logged_in:
		return {"ok":false,"message":"Sign in before submitting a clip."}
	var actual_path=file_path
	if not actual_path.is_abs_path():
		actual_path=Globals.p(actual_path)
	var file=File.new()
	if not file.file_exists(actual_path):
		return {"ok":false,"message":"Clip file could not be found."}
	if file.open(actual_path,File.READ)!=OK:
		return {"ok":false,"message":"The clip file could not be opened."}
	var size=file.get_len()
	var content_type=_content_type(actual_path)
	if content_type=="":
		file.close()
		return {"ok":false,"message":"Clip must be MP4, WebM, or MOV."}
	if size<=0 or size>MAX_UPLOAD_BYTES:
		file.close()
		return {"ok":false,"message":"Clip must be between 1 byte and 500 MB."}
	var upload_request=yield(Rhythian._api_request(HTTPClient.METHOD_POST,"/api/clip-upload",{"fileName":actual_path.get_file(),"contentType":content_type,"folder":"clips","fileSize":size},true,25.0),"completed")
	if not upload_request.get("ok",false):
		file.close()
		last_error=Rhythian._http_error_message(upload_request,"clip upload")
		return {"ok":false,"message":last_error}
	var upload_data=upload_request.get("json",{})
	var upload_url=str(upload_data.get("uploadUrl",""))
	var storage_path=str(upload_data.get("path",""))
	if upload_url=="" or storage_path=="":
		file.close()
		return {"ok":false,"message":"The storage service returned an invalid upload URL."}
	var bytes=file.get_buffer(size)
	file.close()
	emit_signal("upload_progress",0,size)
	var request=HTTPRequest.new()
	add_child(request)
	request.use_threads=true
	request.timeout=900.0
	var headers=PoolStringArray(["Content-Type: "+content_type])
	var err=request.request_raw(HTTPClient.METHOD_PUT,upload_url,headers,bytes)
	if err!=OK:
		request.queue_free()
		last_error="Could not start the clip upload. Check your internet connection."
		return {"ok":false,"message":last_error}
	var response=yield(request,"request_completed")
	request.queue_free()
	if int(response[0])!=HTTPRequest.RESULT_SUCCESS or int(response[1])<200 or int(response[1])>=300:
		last_error="The clip upload failed (HTTP %d)." % int(response[1])
		return {"ok":false,"message":last_error}
	emit_signal("upload_progress",size,size)
	var submit_request=yield(Rhythian._api_request(HTTPClient.METHOD_POST,"/api/clips/submit",{"title":title.strip_edges(),"songName":song_name.strip_edges(),"description":description.strip_edges(),"cameraMode":camera_mode,"storagePath":storage_path},true,30.0),"completed")
	if not submit_request.get("ok",false):
		last_error=Rhythian._http_error_message(submit_request,"clip submission")
		return {"ok":false,"message":last_error}
	var body=submit_request.get("json",{})
	last_error=""
	emit_signal("upload_finished",true,"Clip submitted for review.")
	return {"ok":true,"clipId":body.get("clipId",""),"status":body.get("status","pending")}

func _content_type(path:String) -> String:
	var ext=path.get_extension().to_lower()
	if ext=="mp4": return "video/mp4"
	if ext=="webm": return "video/webm"
	if ext=="mov": return "video/quicktime"
	return ""
