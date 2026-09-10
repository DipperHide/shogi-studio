extends ScrollContainer
## Let drags bubble through page widgets to Godot's touch scrolling/cancellation.
## Watch new descendants too: lessons and connection lists can update in place.

func _ready() -> void:
	scroll_deadzone = 10
	for child in get_children(): _watch(child)
	child_entered_tree.connect(_watch)

func _watch(node: Node) -> void:
	if node is ScrollBar: return
	if node is Control and node.mouse_filter == Control.MOUSE_FILTER_STOP:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	if node is BaseButton:
		# OptionButton normally opens on press, before a drag can be recognized.
		node.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	for child in node.get_children(): _watch(child)
	if not node.child_entered_tree.is_connected(_watch):
		node.child_entered_tree.connect(_watch)
