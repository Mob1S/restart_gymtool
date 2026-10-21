import 'dart:async';

import '../data/files/motion_bridge.dart';
import '../data/repositories/video_review_repo.dart';
import 'data_revision.dart';

class VideoReviewCleanup {
  final VideoReviewRepo repo;
  final DataRevision revision;
  bool _running = false, _again = false, _disposed = false;
  bool? _available;
  VideoReviewCleanup(this.repo, this.revision) {
    revision.addListener(changed);
    changed();
  }
  void changed() {
    if (!MotionBridge.supported || _disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    unawaited(() async {
      try {
        _available ??=
            (await MotionBridge().call('capabilities', {}))['supported'] ==
            true;
        if (_available != true) return;
        final results = await repo.resultFiles();
        await MotionBridge().call('collect', {
          'keep': results.keys.toList(),
          'results': results,
        });
      } catch (_) {
        _available ??= false;
        /* Retry on next data change or restart; training stays usable. */
      } finally {
        _running = false;
        if (_again) {
          _again = false;
          changed();
        }
      }
    }());
  }

  void dispose() {
    _disposed = true;
    revision.removeListener(changed);
  }
}
