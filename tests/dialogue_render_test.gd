extends SceneTree
## Render the shared dialogue UI at exact logical output sizes independent of OS window limits.

const TOWN: MapData = preload("res://data/maps/town.tres")
const OUTPUT := "res://build/screenshots"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for dimensions in [Vector2i(720, 480), Vector2i(1200, 700), Vector2i(720, 900)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var scale_factor: float = minf(float(dimensions.x) / 960.0, float(dimensions.y) / 640.0)
		var holder := Control.new()
		holder.size = Vector2(960, 640)
		holder.scale = Vector2.ONE * scale_factor
		holder.position = (Vector2(dimensions) - holder.size * scale_factor) * 0.5
		viewport.add_child(holder)
		var ui := GameUI.new()
		holder.add_child(ui)
		ui.screen = "dialogue"
		var model := DialogueModel.new()
		assert(model.start(TOWN.npcs[0].dialogue, ui.font))
		ui.dialogue_view.set_content(model)
		ui.dialogue_view.visible = true
		ui.queue_redraw()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		assert(image.get_size() == dimensions)
		assert(image.save_png(OUTPUT.path_join("dialogue_exact_%dx%d.png" % [dimensions.x, dimensions.y])) == OK)
		viewport.queue_free()
		await process_frame
	print("PASS: exact 720x480, 1200x700 and 720x900 dialogue UI images saved.")
	quit()
