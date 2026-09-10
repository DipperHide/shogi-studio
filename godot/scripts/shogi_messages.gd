extends RefCounted
## Optional reason codes augment v1 messages; legacy peers still receive reason.
const CATALOG = preload("res://assets/locales/catalog.json")

static func reason(message: Dictionary, fallback: String) -> String:
	var code = message.get("reason_code", "")
	if code is String and not code.is_empty():
		for source in CATALOG.data:
			if source.sha256_text().left(16) == code: return source
	return str(message.get("reason", fallback))
