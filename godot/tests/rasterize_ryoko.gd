extends SceneTree
## Run only when changing the source SVGs. Godot supplies its own SVG rasterizer.
func _initialize() -> void:
	var folder = ProjectSettings.globalize_path("res://../assets/calligraphy/ryoko/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder+"masks"))
	var count = 0
	for filename in DirAccess.get_files_at(folder+"glyphs"):
		if not filename.ends_with(".svg"):
			continue
		var image = Image.new()
		var error = image.load_svg_from_string(FileAccess.get_file_as_string(folder+"glyphs/"+filename),2.0)
		assert(error == OK,filename)
		image.save_png(folder+"masks/"+filename.get_basename()+".png")
		count += 1
	print("RYOKO_RASTERIZED: ",count)
	quit(0 if count == 15 else 1)
