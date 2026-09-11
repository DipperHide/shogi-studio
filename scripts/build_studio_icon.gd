extends SceneTree
func _init() -> void:
	var image = Image.new()
	var source = FileAccess.get_file_as_string("res://assets/brand/studio-icon.svg")
	if image.load_svg_from_string(source) != OK: quit(1); return
	image.save_png("res://assets/brand/studio-icon.png")
	var foreground = Image.new()
	var transparent_source = source.replace('<rect width="512" height="512" rx="112" fill="url(#wood)" />', '')
	transparent_source = transparent_source.replace('</defs>', '</defs><g transform="translate(51.2 51.2) scale(0.8)">').replace('</svg>', '</g></svg>')
	if foreground.load_svg_from_string(transparent_source) != OK: quit(1); return
	foreground.save_png("res://assets/brand/studio-foreground.png")
	var images: Array[PackedByteArray] = []
	var sizes = [16, 24, 32, 48, 64, 128, 256]
	for edge in sizes:
		var sized = image.duplicate()
		sized.resize(edge, edge, Image.INTERPOLATE_LANCZOS)
		images.append(sized.save_png_to_buffer())
	var file = FileAccess.open("res://assets/brand/studio.ico", FileAccess.WRITE)
	file.store_16(0); file.store_16(1); file.store_16(sizes.size())
	var offset = 6 + sizes.size() * 16
	for i in range(sizes.size()):
		file.store_8(sizes[i] % 256); file.store_8(sizes[i] % 256)
		file.store_8(0); file.store_8(0); file.store_16(1); file.store_16(32)
		file.store_32(images[i].size()); file.store_32(offset)
		offset += images[i].size()
	for bytes in images: file.store_buffer(bytes)
	file.close()
	print("Studio icon generated from original SVG")
	quit()
