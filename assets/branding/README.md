# 健身记录图标

图形为橙色哑铃：保留最初版本的圆角杠铃片，中央使用一根水平直杆。根据用户反馈移除了突兀的对勾，不再嵌入额外符号。沿用应用已有的信号橙 / 炭黑方向，Android 桌面名称与网页名称统一为「健身记录」。

- `gym-mark.png`：内置 image_gen 编辑生成的最终透明图形，作为打包源文件。
- `app-icon.png`：1024 × 1024 不透明预览。
- `icon-preview.png`：Android 圆形 / 圆角方形 / 方形与 32–96 px 联系表。
- `icon-assets.json`：实际生成的资源、尺寸和颜色模式清单。

生成使用内置工具，未使用 CLI / API key。打包仅做透明留白测量、等比例缩放、居中、平台底色和尺寸适配；源图保留，不依赖生成缓存目录。

## 平台资源

Android 保留五档 48dp 旧版图标；新增 108dp 透明前景，主图形宽度 54%，逐档检查不超出 66dp 安全圆。API 26 起由系统裁切背景 / 前景，API 33 起提供 monochrome 层。网页提供 32px favicon、192 / 512px 普通与 maskable 图标，主图形宽度 72%。

重新打包需要开发环境 Python + Pillow，不给 Flutter 新增依赖：

```powershell
python scripts/build_icons.py
```

## 最终编辑提示

使用内置 image_gen 的图像编辑模式，以原哑铃 / 对勾版为参考，设置 `transparent_background=true`。最终采用的源输出为 `exec-767baaf4-7964-4351-98ad-ccf620b7c3f5.png`，已复制为本目录的 `gym-mark.png`；打包不引用缓存路径。

```text
Edit ONLY the central connector of this orange dumbbell icon. The user likes the original dumbbell but rejects the checkmark. Remove the checkmark-shaped bend, the checkmark-shaped hole/cutout, and every chevron/check detail from the middle. Replace the entire middle connector with ONE simple solid straight HORIZONTAL orange bar, centered vertically between the inner weight plates. The bar has uniform thickness, about one quarter of the inner plates' height, and joins the two inner plates cleanly. It must be a normal recognizable gym dumbbell, without any symbol embedded in it. Preserve the left and right rounded weight plates, their shapes, relative sizes, spacing, orange color, existing subtle shading, overall silhouette dimensions, and centered square composition. Do not add any other emblem, tick, arrow, chart, letter, text, line, hole, badge, or decoration. Keep the background genuinely transparent. One finished clean icon foreground, no tile, no mockup, no options sheet.
```

杠铃片和几何标记两版候选位于 `candidates/`，仅用于保留设计过程，不用于平台资源。

平台图标打包与验收结果见 [图标复验记录](../../docs/superpowers/plans/2026-10-16-icon-and-retest.md)。
