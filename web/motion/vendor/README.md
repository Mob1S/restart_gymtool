# Local vision runtime

All inference assets are served from this directory. No frame is sent to a remote API.

- MediaPipe Tasks Vision **0.10.32**: `https://unpkg.com/@mediapipe/tasks-vision@0.10.32/vision_bundle.mjs` and the four `wasm/vision_wasm_*` loaders/binaries from that package. License: Apache-2.0 (`MEDIAPIPE_LICENSE.txt`). Official upstream: https://github.com/google-ai-edge/mediapipe.
- Pose Landmarker Lite **float16/1**: https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task. Apache-2.0 per the official BlazePose GHUM model card; same model as Android. SHA-256 `59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a`.
- OpenCV.js **4.10.0**, packaged build **@techstark/opencv-js 4.10.0-release.1**: https://unpkg.com/@techstark/opencv-js@4.10.0-release.1/dist/opencv.js. OpenCV Apache-2.0 (`OPENCV_LICENSE.txt`). Build provenance: https://github.com/TechStark/opencv-js/tree/v4.10.0-release.1, upstream https://github.com/opencv/opencv/tree/4.10.0. Single-file WASM build; no runtime CDN required.

`manifest.json` records every shipped file hash. Run `node scripts/verify_motion_assets.mjs` after checkout or changes. Hashes provide reproducibility, not an accuracy claim. Initial site load still downloads these local static resources. The supported Web inference path is CPU/WASM in a module Worker with OffscreenCanvas; no synchronous UI-thread fallback.

Tracking thresholds are `lk-fb-template-2`: FB error <1.5px, LK error <25, >=4 and >=60% good features, median motion spread <=2.5px, displacement <=ROI radius, normalized template correlation >=0.65. These are versioned engineering defaults pending the specified accuracy dataset.
