extends RefCounted
class_name DebugLog

# DebugLog — jeden vypinac pre diagnosticke vypisy Scrolls systemu
# ([pack], [profile], [synergy], [spawn]). Defaultne VYPNUTE, aby konzola
# ostala cista; v debug builde sa zapina klavesom F11 v hlavnom menu.
# Ziadne nody, ziadne autoloady — staticky stav.

static var enabled: bool = false

static func info(tag: String, text: String) -> void:
	if enabled:
		print("[%s] %s" % [tag, text])
