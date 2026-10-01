extends RefCounted
## Godot 4.7 JNI methods use a separate method table from Object methods.
static func supports(platform, method: String) -> bool:
	if platform == null: return false
	if platform.has_method("has_java_method"): return platform.has_java_method(method)
	return platform.has_method(method)
