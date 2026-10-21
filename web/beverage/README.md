# 本地饮料标签识别

`runtime.js` 只在用户选择图片后启动 OCR。原图和文字不上传；公共饮料搜索仅向 Open Food Facts 发送查询和选中商品条码。

离线引擎：Tesseract.js **6.0.1**、tesseract.js-core **6.0.0**；中英 LSTM 模型：tessdata_fast **4.1.0** 的 `chi_sim` / `eng`。均为 Apache-2.0，完整许可位于 `vendor/LICENSE-*`。引擎、worker、四种 WASM 和模型随 Web 产物提供，不依赖运行时 CDN。首次加载这些同源静态文件后才能离线识别。

获取固定版本资源：用 PowerShell 7 执行 `scripts/fetch_beverage_ocr.ps1`。包文件来自固定版本 unpkg/npm 镜像，模型来自 Tesseract 官方仓库固定发布标签；下载采用临时文件，成功后才替换。`vendor/manifest.json` 记录交付文件的 SHA-256。

来源：

- https://github.com/naptha/tesseract.js/tree/v6.0.1
- https://www.npmjs.com/package/tesseract.js-core/v/6.0.0
- https://github.com/tesseract-ocr/tessdata_fast/tree/4.1.0
- https://openfoodfacts.github.io/openfoodfacts-server/api/

识别只负责提取文字，不依据外观猜热量。反光、旋转、小字可能导致缺失或误识别，必须对照原图核对。多个能量值、每 100 g 或缺失基准不会自动填入热量。原图仅留在当前表单内存，取消会停止 worker 并释放图片。

Android 使用随 APK 打包的 ML Kit 中文模型 `com.google.mlkit:text-recognition-chinese:16.0.1`；相机临时文件放入 cache，无需用户账户或 Google Play 下载模型。
