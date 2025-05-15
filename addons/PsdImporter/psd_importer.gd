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
	return "";

func _get_resource_type() -> String:
	return "";

func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return true;

func _get_preset_count() -> int:
	return 0;

func _get_import_order() -> int:
	return 0;

func _get_preset_name(preset_index) -> String:
	return "";

func _get_import_options(path, preset_index) -> Array[Dictionary]:
	return [
		{ "name": "merge_layers", "default_value": false }
	];

func _get_priority() -> float:
	return 1.0;

func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	var merge_layers := options["merge_layers"] as bool;
	var img_data_array := self.read_psd_file(source_file, merge_layers);
	if img_data_array.size() == 0:
		return ERR_FILE_CORRUPT;
	elif img_data_array.size() == 1:
		var filename := source_file.get_base_dir().path_join(source_file.get_basename().get_file()) + ".tres";
		var compressed := PortableCompressedTexture2D.new();
		compressed.create_from_image(img_data_array[0].image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS);
		var save_error := ResourceSaver.save(compressed, filename);
		if save_error != OK:
			printerr("Unable to save %s: %s" % [filename, save_error]);
			return save_error;
		return OK;
	else:
		var layer_index = 0;
		for image in img_data_array:
			var filename := source_file.get_base_dir().path_join(source_file.get_basename().get_file()) + "." + image.name + ".tres";
			var compressed := PortableCompressedTexture2D.new();
			compressed.create_from_image(image.image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS);
			var save_error := ResourceSaver.save(compressed, filename);
			if save_error != OK:
				printerr("Unable to save %s: %s" % [filename, save_error]);
				return save_error;
		print(gen_files);
		return OK;


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
static func read_psd_file(path: String, merged: bool) -> Array[ImageData]:
	var psd_file := FileAccess.open(path, FileAccess.READ);
	print("Start Importing PSD Document (%s)" % path);
	
	if !psd_file: 
		printerr("Access Error: %s" % FileAccess.get_open_error());
		return [];
	
	var reader := BigEndieanReader.new(psd_file);
	
	if !reader.get_and_match_header("8BPS", "File Start"):
		return [];
	
	var version := reader.get_u16();
	if version != 1:
		printerr("PSD Format Error: %s != 1" % version);
		return [];
	
	var reserved_bytes := psd_file.get_buffer(6);
	if reserved_bytes != PackedByteArray([0,0,0,0,0,0]):
		printerr("Reserved Segment Error: %s != [0,0,0,0,0,0]" % reserved_bytes);
		return [];
	
	var channels := reader.get_u16();
	if channels < 1 || channels > 56:
		printerr("Channel Count Error: %s != 1 ~ 56" % channels);
		return [];
	
	var height := reader.get_u32();
	if height < 1 || height > 30000:
		printerr("Image Height Error: %s != 1 ~ 30000" % height);
		return [];
	
	var width := reader.get_u32();
	if width < 1 || width > 30000:
		printerr("Image Width Error: %s != 1 ~ 30000" % width);
		return [];
	
	var channel_bit_depth := reader.get_u16();
	if ![1,8,16,32].has(channel_bit_depth):
		printerr("Channel Depth Error: %s != 1 | 8 | 16 | 32" % channel_bit_depth);
		return [];

	var color_mode_value := reader.get_u16();
	if color_mode_value > 9:
		printerr("Color Mode Error: %s > 9" % color_mode_value);
		return [];
	var color_mode : ColorMode = color_mode_value;
	
	
	var color_data_length := reader.get_u32();
	match color_mode:
		ColorMode.Indexed:
			if color_data_length != 768:
				printerr("Index Color Mode Data Error: %s != 768" % [color_data_length]);
				return [];
			reader.skip(768);
			pass
		ColorMode.Duotone:
			reader.skip(color_data_length);
			pass
		_:
			if color_data_length != 0:
				printerr("Color Mode Data Error: %s != 0 for %s" % [color_data_length, ColorMode.keys()[color_mode]]);
				return [];
			pass
	
	
	var image_resource_length := reader.get_u32();
	reader.skip(image_resource_length);
	
	var layer_and_mask_length := reader.get_u32();
	
	if !merged: # Analyze Layer Information and Export Image by
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
			var result := record.parse_data(reader, layer_index);
			if result != OK:
				return [];
			layer_records.append(record);
		
		var layer_texture : Array[ImageData];
		
		for layer_record in layer_records:
			print("Importing Layer %s..." % layer_record.layer_name);
			var image = _read_layer_image(
				layer_record.right - layer_record.left, 
				layer_record.bottom - layer_record.top, 
				reader,
				layer_record.channel_info
			);
			if !image:
				return [];
			layer_texture.append(ImageData.new(image, layer_record.layer_name));
		
		return layer_texture;
	else: # 解析并输出合并图信息（需要启动“最大化兼容性”）
		reader.skip(layer_and_mask_length);
		
		# 图像数据部分
		# 首先是所有红色数据，然后是所有绿色数据
		# 长度:2 压缩方法：0 = 原始图像数据 1 = RLE 压缩图像数据 2 = 无预测的 ZIP 3 = 带预测的 ZIP
		var compression_method_value := reader.get_u16();
		if compression_method_value > 3:
			printerr("压缩模式错误 (%s > 3)" % compression_method_value);
			return [];
		var compression_method : CompressionMethod = compression_method_value;
		if compression_method == CompressionMethod.Zip || compression_method == CompressionMethod.ZipWithPrediction:
			printerr("不支持此压缩模式(%s)" % compression_method);
		
		var image_data_bytes := reader.get_rest();
		
		var created_image : Image;
		
		if compression_method == CompressionMethod.Raw:
			var image_data : PackedByteArray;
			var index := 0
			
			while index < width * height:
				for i in range(4):
					var data_byte := image_data_bytes.decode_u8(index + width * height * i);
					image_data.append(data_byte);
				index += 1
			
			created_image = Image.create_from_data(
				width,
				height,
				false,
				Image.FORMAT_RGBA8,image_data
			);
		elif compression_method == CompressionMethod.RLE:
			var sliced_image_data_bytes = image_data_bytes.slice(channels * 2 * height);
			var decoded_data : PackedByteArray;
			var index := 0
			while index < sliced_image_data_bytes.size() - 1:
				var data_byte := sliced_image_data_bytes.decode_u8(index);
				if data_byte >= 0x80: # 该行有重复像素
					index += 1
					for i in range(256 - data_byte + 1):
						decoded_data.append(sliced_image_data_bytes.decode_u8(index))
				else: # 该行没有重复，按字节填充像素
					for i in range(data_byte + 1):
						index += 1;
						decoded_data.append(sliced_image_data_bytes.decode_u8(index));
				index += 1;
			var image_data : PackedByteArray;
			index = 0
			while index < width * height:
				for i in range(channels):
					image_data.append(decoded_data.decode_u8(index + width * height * i));
				index += 1;
			if channels == 3:
				created_image = Image.create_from_data(
					width,
					height,
					false,
					Image.FORMAT_RGB8,
					image_data
				);
			elif channels == 4:
				created_image = Image.create_from_data(
					width,
					height,
					false,
					Image.FORMAT_RGBA8,
					image_data
				);
			else:
				printerr("不支持此数量的通道(%s != [3|4])" % channels);
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
							printerr("Channel UserSuppliedLayerMask not supported");
							return null;
						LayerRecord.ChannelKind.RealUserSuppliedLayerMask:
							printerr("Channel UserSuppliedLayerMask not supported");
							return null;
						_:
							scanlines = height;
					for i in range(scanlines):
						rle_buffer_size += reader.get_u16();
					pass
				data = reader.get_buffer(rle_buffer_size);
			CompressionMethod.Zip:
				printerr("Zip image format not supported");
				return null;
			CompressionMethod.ZipWithPrediction:
				printerr("Zip(with prediction) image format not supported");
				return null;
		var remainder := channel.data_length - reader.get_position() + start;
		reader.skip(remainder);
		result.get_or_add(channel.kind, ChannelData.new(compression, data));
	
	if !result.has(LayerRecord.ChannelKind.Red):
		printerr("Red Channel not found for layer");
		return null;
	
	if !result.has(LayerRecord.ChannelKind.Green):
		printerr("Green Channel not found for layer");
		return null;	
		
	if !result.has(LayerRecord.ChannelKind.Blue):
		printerr("Blue Channel not found for layer");
		return null;
		
	if !result.has(LayerRecord.ChannelKind.TransparencyMask):
		printerr("Alpha Channel not found for layer");
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
			printerr("Unsupported Compression Format: %s" % CompressionMethod.keys()[data.compression]);
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
		input_pos += 1

		if header == -128:
			# Skip byte
			continue
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
	
	func parse_data(file: BigEndieanReader, layer_index : int) -> Error:
		top = file.get_s32()
		left = file.get_s32();
		bottom = file.get_s32()
		right = file.get_s32()
		
		channel_count = file.get_u16();
		for channel_index in range(channel_count):
			var channel_id := file.get_s16();
			if channel_id < -3 || channel_id > 2:
				printerr("ChannelKind Error in Layer#%s Channel#%s: %s < -3 || %s > 2" % [layer_index, channel_index, channel_id, channel_id]);
				return ERR_FILE_CORRUPT;
			var channel_kind : LayerRecord.ChannelKind = channel_id;
			var channel_data_length := file.get_u32();
			channel_info.append(ChannelInfo.new(channel_kind, channel_data_length));
		
		if !file.get_and_match_header("8BIM", "Layer#%s (Blend Mode)" % layer_index):
			return ERR_FILE_CORRUPT;
		
		var blend_mode_key := file.get_ascii(4);
			
		if blend_mode_key != "norm":
			printerr("Unsupported Blend Mode in Layer#%s: %s != norm" % [layer_index, blend_mode_key]);
			return ERR_FILE_CORRUPT;
		# 0 == 0.0, 255 == 1.0
		opacity = file.get_u8();
		if opacity != 255:
			printerr("Unsupported Opacity in Layer#%s: %s != 255" % [layer_index, opacity]);
			return ERR_FILE_CORRUPT;
		
		clipping_is_base = file.get_u8() == 0;
		if !clipping_is_base:
			printerr("Unsupported Clipping in Layer#%s: %s != 0" % [layer_index, opacity]);
			return ERR_FILE_CORRUPT;
		
		flags = file.get_u8();
		var hidden := flags & 0x2;
		
		file.get_u8(); # One Byte Padding
		
		var extra_data_length := file.get_u32();
		
		var layer_mask_length := file.get_u32();
		if layer_mask_length != 0:
			printerr("Layer Mask Not Supported in Layer#%s: %s != 0" % [layer_index, layer_mask_length]);
			return ERR_FILE_CORRUPT;
		
		file.skip(layer_mask_length); # Effectively an NOP
		
		var layer_blending_range_length := file.get_u32();
		file.skip(layer_blending_range_length);
		
		var name_length := file.get_u8();
		var padded_length := _round_up_to_multiple(name_length + 1, 4);
		var name_bytes = file.get_buffer(name_length);
		var skipped_bytes := padded_length - name_length - 1;
		file.skip(skipped_bytes);
		
		layer_name = GBKEncoding.get_string_from_gbk(name_bytes);
		
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
		printerr("Header Mismatch at %s: %s != %s" % [source, buffer, header]);
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
					printerr("%s is not a valid GBK code point!" % gbk_code_point);
					unicode_sequence.append_array(("? %s ?" % gbk_code_point).to_utf16_buffer());
					break;
				unicode_sequence.append_array(unicode_code_point);
				index += 2;
			
		return unicode_sequence.get_string_from_utf16();
	
	static func _load_map() -> void:
		var file := FileAccess.open("res://addons/PsdImporter/gbk_to_utf16.bytes", FileAccess.READ);
		while file.get_position() != file.get_length():
			gbk_to_unicode_map.get_or_add(file.get_buffer(2), file.get_buffer(2));
#endregion
