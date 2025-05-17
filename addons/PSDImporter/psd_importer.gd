@tool
class_name LayeredPSDImportPlugin;
extends EditorImportPlugin

func _get_importer_name() -> String:
	return "psd_layers_importer";
	
func _get_visible_name() -> String:
	return "Photoshop Document Layers";

func _get_recognized_extensions() -> PackedStringArray:
	return ["psd"];

func _get_save_extension() -> String:
	return "tres";

func _get_resource_type() -> String:
	return "PhotoshopDocument";

func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	match option_name:
		"import_mode": return true;
		"old_resource_handling": return true;
		_: return options["import_mode"] == Mode.ByLayer;
	return true;

func _get_preset_count() -> int:
	return 0;

func _get_import_order() -> int:
	return 0;

func _get_preset_name(preset_index) -> String:
	return "";

enum Mode {
	ByLayer,
	Merged,
}

enum LayerNameEncoding {
	Utf8,
	GBK,
}

enum OldResourceHandling {
	Unlink,
	Delete,
}

func _get_import_options(path, preset_index) -> Array[Dictionary]:
	return [
		{
			"name": "import_mode",
			"default_value": Mode.ByLayer,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": _get_enum_selections(Mode),
		},
		{
			"name": "layer_name_encoding",
			"default_value": LayerNameEncoding.GBK,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": _get_enum_selections(LayerNameEncoding),
		},
		{
			"name": "layer_trim_enabled",
			"default_value": false,
		},
		{
			"name": "layer_resource_naming",
			"default_value": "<file>-<layer>"
		},
		{
			"name": "old_resource_handling",
			"default_value": OldResourceHandling.Unlink,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": _get_enum_selections(OldResourceHandling),
		},
		{
			"name": "perform_ownership_analysis",
			"default_value": false,
		}
	];

static func _get_enum_selections(dict : Dictionary) -> String:
	var str : String;
	for value in dict.values():
		if str != "":
			str += ",";
		str += dict.keys()[value] + ":" + str(value);
	return str;

func _get_priority() -> float:
	return 1.0;

func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	var merge_layers := (options["import_mode"] as Mode) == Mode.Merged;
	var layer_name_encoding := options["layer_name_encoding"] as LayerNameEncoding;
	var trim_layer := options["layer_trim_enabled"] as bool;
	var perform_ownership_analysis := options["perform_ownership_analysis"] as bool;
	var template := options["layer_resource_naming"] as String;
	var old_resource_handling := options["old_resource_handling"] as OldResourceHandling;
	var match_template = _substitute_name(template, "FileName", "LayerName");
	if !match_template.is_valid_filename():
		push_error("\"%s\" is not a valid filename" % match_template);
		return ERR_INVALID_PARAMETER;
	var img_data_array := self.read_psd_file(source_file, merge_layers, layer_name_encoding, trim_layer);
	var true_save_path := save_path + "." + _get_save_extension();
	var source_file_name := source_file.get_basename().get_file();
	var base_name := source_file.get_base_dir().path_join(source_file_name);
	
	var resource : PhotoshopDocument;
	var resource_save_path := save_path + "." + _get_save_extension();
	if !FileAccess.file_exists(resource_save_path):
		resource = PhotoshopDocument.new();
	else:
		resource = ResourceLoader.load(resource_save_path) as PhotoshopDocument;
	
	var old_resources := resource.layers.duplicate() as Array[PortableCompressedTexture2D];
	resource.layers.clear();
	
	
	if img_data_array.size() == 0:
		return ERR_FILE_CORRUPT;
	elif img_data_array.size() == 1:
		var filename := base_name + ".tres";
		var compressed := _create_or_get_texture(filename);
		compressed.create_from_image(img_data_array[0].image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS);
		var save_error := ResourceSaver.save(compressed, filename);
		if save_error != OK:
			push_error("Unable to save %s: %s" % [filename, save_error]);
			return save_error;
		_update_uid(filename);
		compressed = ResourceLoader.load(filename) as PortableCompressedTexture2D;
		gen_files.append(filename);
		resource.layers.append(compressed);
		var found := old_resources.find(compressed);
		if found != -1:
			old_resources.remove_at(found);
	else:
		for image_data in img_data_array:
			var filename := _substitute_name(template, source_file_name, image_data.name) + ".tres";
			if !filename.is_valid_filename():
				push_error("\"%s\" is not a valid filename" % filename);
				return ERR_CANT_CREATE;
		for image_data in img_data_array:
			var filename := _substitute_name(template, base_name, image_data.name) + ".tres";
			var compressed := _create_or_get_texture(filename);
			compressed.create_from_image(image_data.image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS);
			var save_error := ResourceSaver.save(compressed, filename);
			if save_error != OK:
				push_error("Unable to save %s: %s" % [filename, save_error]);
				return save_error;
			_update_uid(filename);
			compressed = ResourceLoader.load(filename) as PortableCompressedTexture2D;
			gen_files.append(filename);
			resource.layers.append(compressed);
			var found := old_resources.find(compressed);
			if found == -1: continue;
			old_resources.remove_at(found);
			
	var main_res_save_error := ResourceSaver.save(resource, resource_save_path);
	if main_res_save_error != OK:
		push_error("Unable to save %s: %s" % [resource_save_path, main_res_save_error]);
		return main_res_save_error;
	
	var editor_fs := EditorInterface.get_resource_filesystem();
	
	var project_resources_owner_map : Dictionary[String, Array];
	if perform_ownership_analysis:
		_build_project_resources_owner_map(editor_fs.get_filesystem(), project_resources_owner_map);
	
	if old_resources.size() > 0:
		
		var message_template : String;
		var delete_old := old_resource_handling == OldResourceHandling.Delete;
		var color := "";
		if delete_old:
			print_rich("[color=tomato]The following resources are no longer a part of the origianl file and has been deleted after the PSD update:")
			color = "[color=light_salmon]";
		else:
			print_rich("[color=yellow]The following resources are no longer a part of the origianl file after the PSD update:");
			color = "[color=gold]";
		
		for old_resource in old_resources:
			var resource_path := old_resource.resource_path;
			if delete_old:
				var remove_result := OS.move_to_trash(ProjectSettings.globalize_path(resource_path));
				if remove_result != OK:
					push_error("Unable to delete the resource %s: %s" % [resource_path, remove_result]);
				else:
					editor_fs.update_file(resource_path);
					print_rich("%s  x %s" % [color, resource_path]);
			else:
				print_rich("%s  ⇏ %s" % [color, resource_path]);
			if !project_resources_owner_map.has(resource_path): continue;
			for owner in (project_resources_owner_map[resource_path] as Array[String]):
				if owner == source_file: continue;
				print_rich("%s      ↳ %s is affected" % [color, owner])
			
	print_rich("[color=cyan]The following resources have changed after the PSD update:");
	for updated in resource.layers:
		var resource_path := updated.resource_path;
		print_rich("[color=light_cyan]  ↺ %s" % resource_path);
		if !project_resources_owner_map.has(resource_path): continue;
		for owner in (project_resources_owner_map[resource_path] as Array[String]):
			if owner == source_file: continue;
			print_rich("[color=light_cyan]      ↳ %s is affected" % owner)
		
	return OK;

static func _build_project_resources_owner_map(efsd: EditorFileSystemDirectory, map: Dictionary[String, Array]):
	if !efsd: return;
	for i in efsd.get_subdir_count():
		_build_project_resources_owner_map(efsd.get_subdir(i), map);
	
	for i in efsd.get_file_count():
		var path := efsd.get_file_path(i);
		if !ResourceLoader.exists(path): continue;
		var dependencies := ResourceLoader.get_dependencies(path);
		for dependency in dependencies:
			(map.get_or_add(dependency.get_slice("::", 2), []) as Array[String]).append(path);

static func _substitute_name(template: String, filename: String, layername: String) -> String:
	return template.replace("<file>", filename).replace("<layer>", layername);

static func _create_or_get_texture(filename: String) -> PortableCompressedTexture2D:
	if !FileAccess.file_exists(filename):
		return PortableCompressedTexture2D.new();
	return ResourceLoader.load(filename) as PortableCompressedTexture2D;

static func _update_uid(filename: String) -> void:
	# TODO: Uid consistency, use ResourceSaver.set_uid when Godot 4.5
	pass;

enum ColorMode
{
	Bitmap = 0,
	Grayscale = 1,
	Indexed = 2,
	RGB = 3,
	CMYK = 4,
	Multichannel = 5,
	Duotone = 8,
	Lab = 9,
}

enum CompressionMethod
{
	Raw = 0,
	RLE = 1,
	Zip = 2,
	ZipWithPrediction = 3,
}

# https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/#50577409_19840
static func read_psd_file(path: String, merged: bool, layer_name_encoding: LayerNameEncoding, trim_layer: bool) -> Array[ImageData]:
	var psd_file := FileAccess.open(path, FileAccess.READ);
	print("Start Importing PSD Document (%s)" % path);
	
	if !psd_file: 
		push_error("Access Error: %s" % FileAccess.get_open_error());
		return [];
	
	var reader := BigEndieanReader.new(psd_file);
	
	if !reader.get_and_match_header("8BPS", "File Start"):
		return [];
	
	var version := reader.get_u16();
	if version != 1:
		push_error("PSD Format Error: %s != 1" % version);
		return [];
	
	var reserved_bytes := psd_file.get_buffer(6);
	if reserved_bytes != PackedByteArray([0,0,0,0,0,0]):
		push_error("Reserved Segment Error: %s != [0,0,0,0,0,0]" % reserved_bytes);
		return [];
	
	var channels := reader.get_u16();
	if channels < 1 || channels > 56:
		push_error("Channel Count Error: %s != 1 ~ 56" % channels);
		return [];
	
	var document_height := reader.get_u32();
	if document_height < 1 || document_height > 30000:
		push_error("Image Height Error: %s != 1 ~ 30000" % document_height);
		return [];
	
	var document_width := reader.get_u32();
	if document_width < 1 || document_width > 30000:
		push_error("Image Width Error: %s != 1 ~ 30000" % document_width);
		return [];
	
	var channel_bit_depth := reader.get_u16();
	if ![1,8,16,32].has(channel_bit_depth):
		push_error("Channel Depth Error: %s != 1 | 8 | 16 | 32" % channel_bit_depth);
		return [];

	var color_mode_value := reader.get_u16();
	if color_mode_value > 9:
		push_error("Color Mode Error: %s > 9" % color_mode_value);
		return [];
	var color_mode : ColorMode = color_mode_value;
	
	var color_data_length := reader.get_u32();
	match color_mode:
		ColorMode.Indexed:
			if color_data_length != 768:
				push_error("Index Color Mode Data Error: %s != 768" % [color_data_length]);
				return [];
			reader.skip(768);
			pass
		ColorMode.Duotone:
			reader.skip(color_data_length);
			pass
		_:
			if color_data_length != 0:
				push_error("Color Mode Data Error: %s != 0 for %s" % [color_data_length, ColorMode.keys()[color_mode]]);
				return [];
			pass
	
	
	var image_resource_length := reader.get_u32();
	reader.skip(image_resource_length);
	
	var layer_and_mask_length := reader.get_u32();
	
	if !merged: # Analyze Layer Information and Export Images
		if layer_and_mask_length == 0: return [];
		
		# Layer Info
		
		# Length of the layers info section, rounded up to a multiple of 2.
		var layer_info_length := reader.get_u32();
		
		# Layer count. If it is a negative number, its absolute value is the number of layers and the first alpha channel contains the transparency data for the merged result.
		var layer_count := reader.get_s16();
		
		var first_alpha_channel_is_merged_layers := layer_count < 0;
		layer_count = absi(layer_count);
		
		var layer_records : Array[LayerRecord];
		
		# Layer records
		for layer_index in range(layer_count):
			var record := LayerRecord.new();
			var result := record.parse_data(reader, layer_index, layer_name_encoding);
			if result != OK:
				return [];
			layer_records.append(record);
		
		var layer_texture : Array[ImageData];
		
		for layer_record in layer_records:
			print("  - Importing Layer '%s'..." % layer_record.layer_name);
			var layer_width := layer_record.right - layer_record.left;
			var layer_height := layer_record.bottom - layer_record.top;
			var image := _read_layer_image(
				layer_width, 
				layer_height, 
				reader,
				layer_record.channel_info
			);
			if !image:
				return [];
			
			if !trim_layer:
				var channel_image := Image.create_empty(document_width, document_height, false, Image.FORMAT_RGBA8);
				var layer_offset := Vector2i(layer_record.left, layer_record.top);
				channel_image.blit_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), layer_offset);
				image = channel_image;
				
			layer_texture.append(ImageData.new(image, layer_record.layer_name));
		
		return layer_texture;
	else: # Parse the composite image data at the end of the file
		reader.skip(layer_and_mask_length);
		
		var compression_method_value := reader.get_u16();
		if compression_method_value > 3:
			push_error("Incorrect compression mode: %s" % compression_method_value);
			return [];
		var compression_method : CompressionMethod = compression_method_value;
		if compression_method == CompressionMethod.Zip || compression_method == CompressionMethod.ZipWithPrediction:
			push_error("Unsupported compression mode: %s" % CompressionMethod.keys()[compression_method]);
		
		var image_data_bytes := reader.get_rest();
		
		var created_image : Image;
		
		if compression_method == CompressionMethod.Raw:
			var image_data : PackedByteArray;
			var input_pos := 0;
			
			while input_pos < document_width * document_height:
				for i in range(4):
					var data_byte := image_data_bytes.decode_u8(input_pos + document_width * document_height * i);
					image_data.append(data_byte);
				input_pos += 1
			
			created_image = Image.create_from_data(
				document_width,
				document_height,
				false,
				Image.FORMAT_RGBA8,image_data
			);
		elif compression_method == CompressionMethod.RLE:
			var input := image_data_bytes.slice(channels * 2 * document_height);
			var decoded_data : PackedByteArray;
			var input_pos := 0
			while input_pos < input.size():
				var header := input[input_pos];
				if header > 127:
					header -= 256; # Convert to signed 8-bit
				input_pos += 1;
				
				if header == -128:
					# Skip byte
					continue;
				elif header >= 0:
					# Treat the following (header + 1) bytes as uncompressed data; copy as-is
					for i in range(header + 1):
						if input_pos >= input.size():
							push_error("input terminated while decoding uncompressed segment in RLE slice")
							return [];
						decoded_data.append(input[input_pos]);
						input_pos += 1;
				else:
					# Following byte is repeated (1 - header) times
					if input_pos >= input.size():
						push_error("input terminated while decoding repeat segment in RLE slice");
						return [];
					var repeat := input[input_pos];
					input_pos += 1;
					var count := 1 + (-header);
					for i in range(count):
						decoded_data.append(repeat);
			var image_data : PackedByteArray;
			input_pos = 0;
			while input_pos < document_width * document_height:
				for i in range(channels):
					image_data.append(decoded_data[input_pos + document_width * document_height * i]);
				input_pos += 1;
			if channels == 3:
				created_image = Image.create_from_data(
					document_width,
					document_height,
					false,
					Image.FORMAT_RGB8,
					image_data
				);
			elif channels == 4:
				created_image = Image.create_from_data(
					document_width,
					document_height,
					false,
					Image.FORMAT_RGBA8,
					image_data
				);
			else:
				push_error("不支持此数量的通道(%s != [3|4])" % channels);
		psd_file.close()
		if created_image: return [ImageData.new(created_image, "")];
		return [];

class ImageData extends RefCounted:
	var image : Image;
	var name : String;
	
	func _init(image: Image, name: String) -> void:
		self.image = image;
		self.name = name;

static func _read_layer_image(width: int, height: int, reader: BigEndieanReader, channel_info: Array[ChannelInfo]) -> Image:
	var result : Dictionary[LayerRecord.ChannelKind, ChannelData];
	for channel in channel_info:
		var start := reader.get_position();
		var compression : CompressionMethod = reader.get_u16();
		var data : PackedByteArray;
		match compression:
			CompressionMethod.Raw:
				data = reader.get_buffer(channel.data_length);
			CompressionMethod.RLE:
				var rle_buffer_size := 0;
				if channel.data_length > 0:
					var scanlines : int;
					match channel.kind:
						LayerRecord.ChannelKind.UserSuppliedLayerMask:
							push_error("Channel UserSuppliedLayerMask not supported");
							return null;
						LayerRecord.ChannelKind.RealUserSuppliedLayerMask:
							push_error("Channel UserSuppliedLayerMask not supported");
							return null;
						_:
							scanlines = height;
					for i in range(scanlines):
						rle_buffer_size += reader.get_u16();
					pass
				data = reader.get_buffer(rle_buffer_size);
			CompressionMethod.Zip:
				push_error("Zip image format not supported");
				return null;
			CompressionMethod.ZipWithPrediction:
				push_error("Zip(with prediction) image format not supported");
				return null;
		var remainder := channel.data_length - reader.get_position() + start;
		reader.skip(remainder);
		result.get_or_add(channel.kind, ChannelData.new(compression, data));
	
	if !result.has(LayerRecord.ChannelKind.Red):
		push_error("Red Channel not found for layer");
		return null;
	
	if !result.has(LayerRecord.ChannelKind.Green):
		push_error("Green Channel not found for layer");
		return null;	
		
	if !result.has(LayerRecord.ChannelKind.Blue):
		push_error("Blue Channel not found for layer");
		return null;
		
	if !result.has(LayerRecord.ChannelKind.TransparencyMask):
		push_error("Alpha Channel not found for layer");
		return null;
	
	var r_channel := result[LayerRecord.ChannelKind.Red];
	var g_channel := result[LayerRecord.ChannelKind.Green];
	var b_channel := result[LayerRecord.ChannelKind.Blue];
	var a_channel := result[LayerRecord.ChannelKind.TransparencyMask];
	
	var array := ByRefByteArray.new();
	var pixel_count := width * height;
	array.inner.resize(pixel_count * BYTES_PER_PIXEL);
	
	if !_decode_channel(r_channel, 0, array): return null;
	if !_decode_channel(g_channel, 1, array): return null;
	if !_decode_channel(b_channel, 2, array): return null;
	if !_decode_channel(a_channel, 3, array): return null;
	
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, array.inner);

static func _decode_channel(data: ChannelData, offset: int, buffer: ByRefByteArray) -> bool:
	match data.compression:
		CompressionMethod.Raw:
			return _decode_raw(data.data, offset, buffer);
		CompressionMethod.RLE:
			return _decode_rle(data.data, offset, buffer);
		_:
			push_error("Unsupported Compression Format: %s" % CompressionMethod.keys()[data.compression]);
			return false;

const BYTES_PER_PIXEL := 4;

static func _decode_raw(input: PackedByteArray, channel_offset: int, output: ByRefByteArray) -> bool:
	var output_pos := channel_offset;
	for value in input:
		if output_pos >= output.inner.size():
			push_error("output slice is too small");
			return false;
		output.inner[output_pos] = value;
		output_pos += BYTES_PER_PIXEL;
	return true;

static func _decode_rle(input: PackedByteArray, channel_offset: int, output: ByRefByteArray) -> bool:
	var input_pos := 0;
	var output_pos := channel_offset;

	while input_pos < input.size():
		var header := input[input_pos];
		if header > 127:
			header -= 256  # Convert to signed 8-bit
		input_pos += 1;

		if header == -128:
			# Skip byte
			continue;
		elif header >= 0:
			# Treat the following (header + 1) bytes as uncompressed data; copy as-is
			for i in range(header + 1):
				if input_pos >= input.size():
					push_error("input terminated while decoding uncompressed segment in RLE slice")
					return false;
				if output_pos >= output.inner.size():
					push_error("output slice is too small (%s >= %s)" % [output_pos, output.inner.size()])
					return false;
				output.inner[output_pos] = input[input_pos];
				input_pos += 1;
				output_pos += BYTES_PER_PIXEL;
		else:
			# Following byte is repeated (1 - header) times
			if input_pos >= input.size():
				push_error("input terminated while decoding repeat segment in RLE slice");
				return false;
			var repeat := input[input_pos];
			input_pos += 1;
			var count := 1 + (-header);
			for i in range(count):
				if output_pos >= output.inner.size():
					push_error("output slice is too small (%s >= %s)" % [output_pos, output.inner.size()]);
					return false;
				output.inner[output_pos] = repeat;
				output_pos += BYTES_PER_PIXEL;
	return true;

#region Helper

class ByRefByteArray extends RefCounted:
	var inner : PackedByteArray;

class LayerRecord extends RefCounted:
	enum ChannelKind {
	  Red = 0,
	  Green = 1,
	  Blue = 2,
	  TransparencyMask = -1,
	  UserSuppliedLayerMask = -2,
	  RealUserSuppliedLayerMask = -3,
	}
	
	enum Flags {
		TransparencyProtected = 1 << 0,
		Hidden = 1 << 1,
		Obsolete = 1 << 2,
		Bit4HasUsefulInfo = 1 << 3,
		PixelDataIrrelevantToAppearance = 1 << 4,
	}
	
	var top: int;
	var left: int;
	var bottom: int;
	var right: int;
	var channel_count : int;
	var channel_info : Array[ChannelInfo];
	var blend_mode : String;
	var opacity : int;
	var clipping_is_base : bool;
	var flags : Flags;
	var layer_name : String;
	
	func _to_string() -> String:
		return "<%s: %s, %s, %s, %s, %s, %s, %s>" % [layer_name, [top, left, bottom, right], channel_count, channel_info, blend_mode, opacity, clipping_is_base, flags];
	
	func parse_data(file: BigEndieanReader, layer_index : int, layer_name_encoding: LayerNameEncoding) -> Error:
		top = file.get_s32()
		left = file.get_s32();
		bottom = file.get_s32()
		right = file.get_s32()
		
		channel_count = file.get_u16();
		for channel_index in range(channel_count):
			var channel_id := file.get_s16();
			if channel_id < -3 || channel_id > 2:
				push_error("ChannelKind Error in Layer#%s Channel#%s: %s < -3 || %s > 2" % [layer_index, channel_index, channel_id, channel_id]);
				return ERR_FILE_CORRUPT;
			var channel_kind : LayerRecord.ChannelKind = channel_id;
			var channel_data_length := file.get_u32();
			channel_info.append(ChannelInfo.new(channel_kind, channel_data_length));
		
		if !file.get_and_match_header("8BIM", "Layer#%s (Blend Mode)" % layer_index):
			return ERR_FILE_CORRUPT;
		
		var blend_mode_key := file.get_ascii(4);
			
		if blend_mode_key != "norm":
			push_error("Unsupported Blend Mode in Layer#%s: %s != norm" % [layer_index, blend_mode_key]);
			return ERR_FILE_CORRUPT;
		# 0 == 0.0, 255 == 1.0
		opacity = file.get_u8();
		if opacity != 255:
			push_error("Unsupported Opacity in Layer#%s: %s != 255" % [layer_index, opacity]);
			return ERR_FILE_CORRUPT;
		
		clipping_is_base = file.get_u8() == 0;
		if !clipping_is_base:
			push_error("Unsupported Clipping in Layer#%s: %s != 0" % [layer_index, opacity]);
			return ERR_FILE_CORRUPT;
		
		flags = file.get_u8();
		var hidden := flags & 0x2;
		
		file.get_u8(); # One Byte Padding
		
		var extra_data_length := file.get_u32();
		
		var layer_mask_length := file.get_u32();
		if layer_mask_length != 0:
			push_error("Layer Mask Not Supported in Layer#%s: %s != 0" % [layer_index, layer_mask_length]);
			return ERR_FILE_CORRUPT;
		
		file.skip(layer_mask_length); # Effectively an NOP
		
		var layer_blending_range_length := file.get_u32();
		file.skip(layer_blending_range_length);
		
		var name_length := file.get_u8();
		var padded_length := _round_up_to_multiple(name_length + 1, 4);
		var name_bytes = file.get_buffer(name_length);
		var skipped_bytes := padded_length - name_length - 1;
		file.skip(skipped_bytes);
		
		match layer_name_encoding:
			LayerNameEncoding.Utf8:
				layer_name = name_bytes.get_string_from_utf8();
			LayerNameEncoding.GBK:
				layer_name = GBKEncoding.get_string_from_gbk(name_bytes);
			_:
				push_error("Unsupported layer name encoding: %s" % layer_name_encoding);
				return ERR_CANT_RESOLVE;
		
		var additional_info_length := extra_data_length - layer_mask_length - layer_blending_range_length - padded_length - 8;
		file.skip(additional_info_length);
		
		return OK;

		
	static func _round_up_to_multiple(num_to_round: int, to_multiple_of: int) -> int:
		return (num_to_round + (to_multiple_of - 1)) & ~(to_multiple_of - 1);

class ChannelInfo extends RefCounted:
	var kind : LayerRecord.ChannelKind;
	var data_length : int;
	
	func _init(kind: LayerRecord.ChannelKind, data_length: int) -> void:
		self.kind = kind;
		self.data_length = data_length;

class ChannelData extends RefCounted:
	var compression : CompressionMethod;
	var data : PackedByteArray;
	
	func _to_string() -> String:
		return "%s[%s]" % [CompressionMethod.keys()[compression], data.size()];
	
	func _init(compression: CompressionMethod, data: PackedByteArray) -> void:
		self.compression = compression;
		self.data = data;

class BigEndieanReader extends RefCounted:
	var _file : FileAccess;
	func _init(file : FileAccess) -> void:
		_file = file;
	func get_and_match_header(header: String, source: String) -> bool:
		var buffer := get_ascii(header.length());
		if buffer == header:
			return true;
		push_error("Header Mismatch at %s: %s != %s" % [source, buffer, header]);
		return false;
	func get_ascii(length: int) -> String:
		return _file.get_buffer(length).get_string_from_ascii();
	func get_buffer(length: int) -> PackedByteArray:
		return _file.get_buffer(length);
	func get_rest() -> PackedByteArray:
		return  _file.get_buffer(_file.get_length() - _file.get_position());
	func get_u8() -> int:
		return _file.get_8();
	func get_u32() -> int:
		return _get_reversed(4).decode_u32(0);
	func get_u16() -> int:
		return _get_reversed(2).decode_u16(0);
	func get_s32() -> int:
		return _get_reversed(4).decode_s32(0);
	func get_s16() -> int:
		return _get_reversed(2).decode_s16(0);
	func _get_reversed(size: int) -> PackedByteArray:
		var buffer := _file.get_buffer(size);
		buffer.reverse();
		return buffer;
	func skip(size: int) -> void:
		_file.seek(_file.get_position() + size);
	func get_position() -> int:
		return _file.get_position();


class GBKEncoding:
	
	static var gbk_to_unicode_map : Dictionary[PackedByteArray, PackedByteArray];
	
	static func get_string_from_gbk(buffer: PackedByteArray) -> String:
		if gbk_to_unicode_map.size() == 0:
			_load_map();
		var unicode_sequence : PackedByteArray;
		var index := 0;
		while index < buffer.size():
			var header := buffer[index];
			if header < 127:
				unicode_sequence.append(header);
				unicode_sequence.append(0);
				index += 1;
			else:
				var gbk_code_point = PackedByteArray([buffer[index], buffer[index + 1]]);
				var unicode_code_point := gbk_to_unicode_map.get_or_add(gbk_code_point, null);
				if !unicode_code_point:
					push_error("%s is not a valid GBK code point!" % gbk_code_point);
					unicode_sequence.append_array(("? %s ?" % gbk_code_point).to_utf16_buffer());
					break;
				unicode_sequence.append_array(unicode_code_point);
				index += 2;
			
		return unicode_sequence.get_string_from_utf16();
	
	static func _load_map() -> void:
		var file := FileAccess.open("res://addons/PSDImporter/gbk_to_utf16.bytes", FileAccess.READ);
		while file.get_position() != file.get_length():
			gbk_to_unicode_map.get_or_add(file.get_buffer(2), file.get_buffer(2));
#endregion
