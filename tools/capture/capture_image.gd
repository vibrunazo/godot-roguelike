## Saving captured frames for the capture tools (capture.py). Screenshots are
## saved downscaled by default: most captures are an agent checking its own
## work, and a smaller image costs far fewer tokens to look at. The frame is
## always rendered at the game's full resolution (the UI scales with the
## window, so a smaller window would change the layout) and only shrunk when
## saved. capture.py --full-res passes --shot-width=0 to keep every pixel.
class_name CaptureImage
extends RefCounted

## Width in pixels screenshots are saved at unless --shot-width says otherwise.
const DEFAULT_SHOT_WIDTH: int = 768
## Pixels of background between the frames of a contact sheet.
const SHEET_GAP: int = 4


## The width to save screenshots at: --shot-width=N from the command line
## (0 = full resolution), else DEFAULT_SHOT_WIDTH.
static func shot_width() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-width="):
			return maxi(arg.trim_prefix("--shot-width=").to_int(), 0)
	return DEFAULT_SHOT_WIDTH


## The viewport's current frame, or null when it is not available.
static func grab(viewport: Viewport) -> Image:
	if viewport == null or viewport.get_texture() == null:
		return null
	return viewport.get_texture().get_image()


## Shrinks image to width (keeping its aspect) unless width is 0 or the
## image is already that narrow.
static func downscale(image: Image, width: int) -> void:
	if width <= 0 or image.get_width() <= width:
		return
	var height: int = maxi(1, roundi(float(image.get_height()) * width / image.get_width()))
	image.resize(width, height, Image.INTERPOLATE_LANCZOS)


## Saves image as a PNG at file_path (creating its folder), downscaled to
## shot_width() unless full_size. Prints the result under tag. Returns true
## on success.
static func save(image: Image, file_path: String, tag: String, full_size: bool = false) -> bool:
	if image == null:
		printerr("[%s] No image to save for %s." % [tag, file_path])
		return false
	if not full_size:
		downscale(image, shot_width())
	var base_dir: String = file_path.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)
	var err: Error = image.save_png(file_path)
	if err != OK:
		printerr("[%s] Failed to save screenshot: %s error: %s" % [tag, file_path, error_string(err)])
		return false
	print("[%s] Screenshot saved successfully: %s (%dx%d)" % [tag, file_path, image.get_width(), image.get_height()])
	return true


## Tiles frames (all the same size) into one image, columns wide, in order,
## so a whole motion reads in a single picture. The sheet is as wide as one
## screenshot (shot_width(), or the frames' own width at full resolution):
## each frame is shrunk to fit its cell.
static func contact_sheet(frames: Array[Image], columns: int) -> Image:
	var cols: int = clampi(columns, 1, frames.size())
	var rows: int = ceili(float(frames.size()) / cols)
	var sheet_width: int = shot_width()
	if sheet_width <= 0:
		sheet_width = frames[0].get_width() * cols
	var cell_width: int = floori(float(sheet_width - SHEET_GAP * (cols - 1)) / cols)
	var cell_height: int = roundi(float(frames[0].get_height()) * cell_width / frames[0].get_width())
	var sheet: Image = Image.create_empty(sheet_width, cell_height * rows + SHEET_GAP * (rows - 1), false, frames[0].get_format())
	for i: int in range(frames.size()):
		var cell: Image = frames[i].duplicate() as Image
		cell.resize(cell_width, cell_height, Image.INTERPOLATE_LANCZOS)
		var at: Vector2i = Vector2i((i % cols) * (cell_width + SHEET_GAP), floori(float(i) / cols) * (cell_height + SHEET_GAP))
		sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), at)
	return sheet
