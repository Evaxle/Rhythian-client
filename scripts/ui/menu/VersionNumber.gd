extends Label

const BUILD_DATE = "8/28/2026"

func _ready():
	text = "Rhythia [%s]  |  %s" % [ProjectSettings.get_setting("application/config/version"), BUILD_DATE]
