# 图标源文件

icon.svg 是本项目原创矢量稿：圆角手柄线条、三层触觉弧、浅色底与绿色点缀。采用简约、留白和清晰轮廓的设计原则，不包含 Apple 或手柄品牌标志。

使用 Node.js 与 sharp 执行 `node tools/render_icon.cjs`，生成根目录 preview.jpg（Workshop）与 assets/modicon.png（128×128 游戏图标）。

游戏纹理使用 [Stexatlaser v0.6](https://github.com/oblivioncth/Stexatlaser/releases/tag/v0.6) 的 Windows 静态版本转换，工具本身不随 Mod 分发：

```text
Stex compress -i assets/modicon.png -o modicon.tex -f rgba
Stex decompress -i modicon.tex -o work/modicon-roundtrip.png
```

RGBA 格式保留线条和透明边角，转换器生成 mipmaps。modicon.xml 按整个纹理映射 modicon.tex，modinfo.lua 使用同名 atlas/element。转换后对解码图像进行视觉检查；真实游戏加载仍属于运行验收。
