
***[English](#godot-photoshop-document-layer-import-plugin) | [简体中文](#用于-godot-的-photoshop-文档图层导入插件)***

## Godot Photoshop Document Layer Import Plugin

A Godot 4.4+ plugin for importing Photoshop Document (PSD) layers into Godot, fully implmented in GDScript.

### Supported Features

- Import PSD files as one single merged texture, or texture set for each layer.
- Alternative layer name encodings: GBK or UTF-8.
- Trimming of transparent pixels per layer.
- Configurable texture namming.

### Installation

1. Download the plugin from the [Releases Page](TBD).
2. Extract the `PSDImporter` directory into your Godot project directory under `res://addons`.
3. Enable the plugin in the Godot editor by going to `Project` -> `Project Settings` -> `Plugins` and enabling the `PSD Importer` plugin.

### Usage

1. Drag and drop a PSD file into the Godot editor's FileSystem panel.
2. Double click the PSD file in the FileSystem panel, please note that it is expected for Godot editor to print `Failed loading resource: res://PATH.TO.THE.psd. Make sure resources have been imported by opening the project in the editor at least once.` in the output panel, this is a known issue with Godot as we are not actually using the PSD file directly as a resource.
3. While the PSD file is selected, go to the `Import` tab in the Inspector panel.
4. Configure the import settings as desired:
   - **Import Mode**: Choose between `ByLayer` (import each layer as a separate texture) or `Merged` (import the entire PSD as a single texture).
   - **Layer Name Encoding** (Available when `Import Mode` is `ByLayer`): Choose between GBK or UTF-8, as Photoshop uses system encoding when saving the layer names.
   - **Layer Trim Enabled** (Available when `Import Mode` is `ByLayer`): Enable this option to trim transparent pixels from the layer.
   - **Layer Resource Naming** (Available when `Import Mode` is `ByLayer`): Input the desired naming format for the layer resources. You can use the following placeholders:
     - `<file>` - The name of the PSD file without the extension.
     - `<layer>` - The name of the layer.
     - Example: If the PSD file is named `example.psd` and the layer is named `Layer1`, using the naming format `<file>-<layer>` will result in a texture named `example-Layer1.tres`.
5. Click the `Reimport` button to apply the import settings.
6. The imported textures will be available in the FileSystem panel under the same directory as the PSD file.

### Limitations (Contribution welcome!)

The plugin does not support the following features:

- PSB (Photoshop Big) files.
- Layer with blend modes other than `Normal`.
- Semi-transparent layers.
- Clipped(masked) layers or layer masks.
- Layer name saved in an encoding that is not GBK or UTF-8.
- Image data that's encoded with `ZIP` or `ZIP with prediction` compression.
- Layer that does not have `RGBA` channels.
- Vector, text, or shape layers.
- Smart objects or linked layers.
- Smart filters.
- Adjustment layers.
- Layer effects or styles.
- 3D layers.
- Layer groups or folders.

## 用于 Godot 的 Photoshop 文档图层导入插件

Godot 4.4+ 的 Photoshop 文档（PSD）图层导入插件，完全使用 GDScript 实现。

### 支持的功能

- 可将 PSD 文件作为单一合并纹理或按图层分别导入为纹理集。
- 支持图层名称编码选择：GBK 或 UTF-8。
- 支持按图层裁剪透明像素。
- 支持自定义纹理命名格式。

### 安装

1. 从 [Releases 页面](TBD) 下载插件。
2. 将 `PSDImporter` 目录解压到你的 Godot 项目目录下的 `res://addons` 目录中。
3. 在 Godot 编辑器中，进入 `项目` -> `项目设置` -> `插件`，启用 `PSD Importer` 插件。

### 使用

1. 将 PSD 文件拖拽到 Godot 编辑器的文件系统面板中。
2. 在文件系统面板中双击 PSD 文件，注意 Godot 编辑器输出面板会提示 `Failed loading resource: res://PATH.TO.THE.psd. Make sure resources have been imported by opening the project in the editor at least once.`，这是已知的Godot编辑器问题，因为插件不会直接将 PSD 文件作为资源使用。
3. 选中 PSD 文件后，切换到检查器面板的 `导入` 选项卡。
4. 根据需要配置导入设置：
   - **导入模式**：选择 `ByLayer`（按图层导入为多个纹理）或 `Merged`（合并为单一纹理）。
   - **图层名称编码**（仅 `ByLayer` 模式可用）：选择 GBK 或 UTF-8，Photoshop 保存图层名时会用系统编码。
   - **图层裁剪启用**（仅 `ByLayer` 模式可用）：启用后会裁剪图层的透明像素。
   - **图层资源命名**（仅 `ByLayer` 模式可用）：输入资源命名格式，可用占位符：
     - `<file>` - PSD 文件名（不含扩展名）
     - `<layer>` - 图层名称
     - 例如：如果 PSD 文件名为 `example.psd`，图层名为 `Layer1`，使用命名格式 `<file>-<layer>` 将生成纹理 `example-Layer1.tres`。
5. 点击 `重新导入` 按钮应用设置。
6. 导入的纹理会出现在与 PSD 文件相同目录下。

### 限制（欢迎贡献！）

插件当前不支持以下功能：

- PSB（大尺寸 Photoshop 文件）。
- 除 `Normal` 外的图层混合模式。
- 半透明图层。
- 剪贴（蒙版）图层或图层蒙版。
- 图层名称编码为非 GBK 或 UTF-8。
- 使用 `ZIP` 或 `ZIP with prediction` 压缩的图像数据。
- 非 RGBA 通道的图层。
- 矢量、文本或形状图层。
- 智能对象或链接图层。
- 智能滤镜。
- 调整图层。
- 图层效果或样式。
- 3D 图层。
- 图层组或文件夹。

## References | 参考

This project uses the following project & scripts as references when implementing the PSD file format:  
此项目在实现 PSD 文件格式时参考了以下项目和脚本：  

***[Adobe Photoshop File Format Specification | Adobe Photoshop 文件格式规范](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/#50577409_19840)***
***[Godot4Library/addons/psd](https://github.com/gaoyan2659365465/Godot4Library)***
***[@webtoon/psd](https://github.com/webtoon/psd)***
***[MolecularMatters/psd_sdk](https://github.com/MolecularMatters/psd_sdk)***
