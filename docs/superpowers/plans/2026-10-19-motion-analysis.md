# Motion Analysis Implementation Plan

> Execution: implement inline in this session, following the approved motion-analysis design. The user's implementation request authorizes proceeding with the existing spec.

**Goal:** Independent, local Web/Android side-view bench-press analysis with imported video and camera input.

**Architecture:** Keep SQL project storage separate from platform media/vision adapters. A session controller owns generations, observations, cancellation and saving; reusable Flutter pages provide navigation, marking and review. Web inference and OpenCV run in a Worker; native work runs off the UI thread.

**Tech Stack:** Flutter/Dart, SQLite schema 10, MediaPipe Pose Lite, OpenCV, browser Worker/IndexedDB/MediaRecorder, Android camera/media APIs.

## Global constraints

- Local processing, single person, fixed side-view bench press; no scores, medical claims or absolute speed/distance.
- Maximum analysis interval: 180000 ms. Use source timestamps, normalized upright coordinates and explicit tracking segments.
- Unmarked/lost bar never falls back to body landmarks. Missing observations break repetitions and metrics.
- Cancelled generations cannot publish into newer sessions. Failed recomputation must preserve saved results.
- Each completed training set has at most one project; deleting a set unlinks it. Training JSON excludes all visual/media data; restore unlinks retained projects transactionally.
- Bundle pinned Web runtime/model assets with hashes and licenses. Worker failure produces an actionable capability error.

## Tasks

- [x] 1. Project persistence: add `motion_project_migration.dart`, `motion_project_repo.dart`, adapt `video_review_repo.dart` compatibility and cleanup. Test v9 migration, independent saving, link conflicts, set deletion, restore and rollback in `test/data/motion_project_repo_test.dart` and existing review tests.
- [x] 2. Session contract: reuse `video_review.dart`, add platform bridge and `motion_analysis_controller.dart`; extend `ReviewFrame` with segment/quality metadata. Test gaps, generations, cancellation, incomplete states and source timestamps.
- [x] 3. Web adapter: add `web/motion/{runtime,worker,tracker,store}.js` and pinned vendor assets. Decode real video with seek/frame callbacks, transfer one frame at a time, process pose/LK/template in Worker, record cameras with capability-selected MIME, store Blob in IndexedDB and release URLs. Exercise with the real local sample.
- [x] 4. Flutter interaction: add `analysis_home_page.dart`, `analysis_session_page.dart` and preview/review widgets; five navigation destinations; legacy review route resolves project/set. Cover 360px layout and nested-route selection. Keep boundary editing, playback speeds, frame stepping and optional completed-set linking.
- [x] 5. Android adapter: extend native tracking with template validation, observation events and session IDs; add camera permission, bounded live processing, silent recording, cancellation and lifecycle release. Build debug APK.
- [x] 6. Verification: run Flutter analyze and complete tests, build Web/APK, browser import/incremental/cancel/storage checks and camera checks when hardware is available. Record accuracy datasets and hardware limitations honestly in an execution report.

## Verification commands

```powershell
. .\scripts\env.ps1
flutter analyze
flutter test --reporter expanded
flutter build web
flutter build apk --debug
```

No automatic commits or publication are needed for this working-tree implementation.
