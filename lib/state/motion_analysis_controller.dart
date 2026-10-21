import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/files/motion_bridge.dart';
import '../data/ids.dart';
import '../data/repositories/motion_project_repo.dart';
import '../domain/video_review.dart';
import '../domain/motion_catalog.dart';
import '../domain/motion_observations.dart';

/// Owns one editor's media and generations. Platform events never own persistence.
class MotionAnalysisController extends ChangeNotifier {
  final MotionBridge bridge;
  final MotionProjectRepo repo;
  final String id;
  String? setId, folder, result, uri, error;
  String mode, phase = 'ready', status = 'incomplete';
  String motionId;
  MotionView view;
  List<Map<String, dynamic>> observations = [];
  int activeObservation = -1;
  List<ReviewFrame> frames = [];
  List<ReviewRep> reps = [];
  List<int> times = [];
  List<Map<String, dynamic>> anchors = [], devices = [];
  Uint8List? image;
  int time = 0, start = 0, end = 1, duration = 1, dropped = 0;
  double width = 640, height = 360, progress = 0, fps = 0, latency = 0;
  bool dirty = false, needsAnalysis = false, canRecord = true;
  bool mirrored = false;
  bool _disposed = false;
  int _generation = 0;
  int _frameGeneration = 0;
  int? textureId;
  String? _session;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  final _held = <String>{};
  MotionAnalysisController(
    this.repo, {
    MotionBridge? bridge,
    String? id,
    this.setId,
    this.mode = 'import',
    this.motionId = MotionCatalog.bench,
    this.view = MotionView.side,
  }) : bridge = bridge ?? MotionBridge(),
       id = id ?? newId() {
    _subscription = this.bridge.events.listen(
      _event,
      onError: (Object e) {
        error = '$e';
        _notify();
      },
    );
  }
  bool get busy =>
      phase == 'loading' ||
      phase == 'analyzing' ||
      phase == 'recording' ||
      phase == 'saving';
  bool get cameraActive => phase == 'preview' || phase == 'recording';
  String _nextSession() => _session = '$id:${++_generation}';
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> run(Future<void> Function() action) async {
    error = null;
    int? generation;
    try {
      final work = action();
      generation = _generation;
      await work;
    } catch (e) {
      if (!_disposed && (generation == null || generation == _generation)) {
        error = '$e';
        if (busy) phase = 'failed';
      }
    }
    _notify();
  }

  void _event(Map<String, dynamic> event) {
    if (_disposed || event['session'] != _session) return;
    textureId = (event['textureId'] as num?)?.toInt() ?? textureId;
    if (event['error'] != null) {
      error = event['error'].toString();
      phase = 'failed';
    }
    if (event['completed'] is Map) {
      _completed(Map<String, dynamic>.from(event['completed'] as Map));
      _notify();
      return;
    }
    if (event['frame'] is Map) {
      final raw = Map<String, dynamic>.from(event['frame'] as Map);
      final frame = ReviewFrame.fromJson(raw);
      time = frame.t;
      width = (raw['width'] as num?)?.toDouble() ?? width;
      height = (raw['height'] as num?)?.toDouble() ?? height;
      if (phase == 'analyzing' || phase == 'recording') {
        if (frames.isEmpty || frame.t > frames.last.t) frames.add(frame);
        reps = detectMotionReps(frames, motionId);
      } else {
        frames = [frame];
      }
      if (event['image'] is String) {
        image = base64Decode(event['image'] as String);
      }
      if (event['bytes'] is Uint8List) image = event['bytes'] as Uint8List;
    }
    progress = (event['progress'] as num?)?.toDouble() ?? progress;
    fps = (event['fps'] as num?)?.toDouble() ?? fps;
    latency = (event['latencyMs'] as num?)?.toDouble() ?? latency;
    dropped = (event['dropped'] as num?)?.toInt() ?? dropped;
    _notify();
  }

  void data(Map<String, dynamic> value) {
    final version = value['version'];
    if (version != 1 && version != 2) throw StateError('不支持的分析结果版本');
    frames = [
      for (final f in value['frames'] as List)
        ReviewFrame.fromJson(Map<String, dynamic>.from(f as Map)),
    ];
    times = [for (final t in value['times'] as List? ?? []) (t as num).toInt()];
    width = (value['width'] as num).toDouble();
    height = (value['height'] as num).toDouble();
    reps = detectMotionReps(frames, motionId);
  }

  Future<void> open(Map<String, dynamic> saved) => run(() async {
    setId = saved['setId'] as String?;
    observations = [
      for (final item in saved['observations'] as List? ?? [])
        Map<String, dynamic>.from(item as Map),
    ];
    if (observations.isEmpty) observations = [Map<String, dynamic>.from(saved)];
    await _openObservation(observations.first);
    activeObservation = 0;
  });

  Future<void> selectObservation(int index) => run(() async {
    if (index < 0 || index >= observations.length) {
      throw RangeError.index(index, observations);
    }
    if (dirty) throw StateError('请先保存当前片段');
    await _openObservation(observations[index]);
    activeObservation = index;
  });

  Future<void> _openObservation(Map<String, dynamic> saved) async {
    _nextSession();
    final generation = _generation;
    phase = 'loading';
    _notify();
    mode = saved['mode'] as String? ?? 'import';
    motionId = MotionCatalog.byId(saved['motionId'] as String?).id;
    view = MotionView.values.firstWhere(
      (v) => v.name == saved['view'],
      orElse: () => MotionView.side,
    );
    folder = saved['folder'] as String;
    _held.add(folder!);
    result = saved['result'] as String;
    canRecord = saved['hasVideo'] != false;
    mirrored = saved['mirrored'] == true;
    if (canRecord) {
      final metadata = await bridge.call('open', {'folder': folder});
      if (_disposed || generation != _generation) return;
      uri = metadata['uri'] as String?;
      duration = (metadata['duration'] as num).round();
    } else {
      duration = (saved['end'] as num).round();
    }
    start = (saved['start'] as num?)?.toInt() ?? 0;
    end = (saved['end'] as num?)?.toInt() ?? duration;
    anchors = [
      for (final a in saved['anchors'] as List? ?? [])
        Map<String, dynamic>.from(a as Map),
    ];
    final loaded = await bridge.call('load', {
      'folder': folder,
      'result': result,
    });
    if (_disposed || generation != _generation) return;
    data(loaded);
    reps = [
      for (final r in saved['reps'] as List? ?? [])
        ReviewRep.fromJson(r as List),
    ];
    status = saved['status'] as String? ?? 'completed';
    phase = 'review';
    dirty = false;
    time = start;
  }

  void beginAdditional({
    required MotionView newView,
    String newMode = 'import',
  }) {
    if (dirty || busy) throw StateError('请先保存当前片段');
    _nextSession();
    activeObservation = -1;
    view = newView;
    mode = newMode;
    folder = result = uri = null;
    frames = [];
    reps = [];
    times = [];
    anchors = [];
    image = null;
    phase = 'ready';
    status = 'incomplete';
    time = start = 0;
    end = duration = 1;
    _notify();
  }

  Future<void> removeObservation(int index) => run(() async {
    if (busy || dirty) throw StateError('请先保存当前片段');
    if (observations.length < 2) throw StateError('最后一段请删除整个项目');
    if (index < 0 || index >= observations.length) {
      throw RangeError.index(index, observations);
    }
    final saved = await repo.load(id);
    if (saved == null) throw StateError('项目已不存在');
    final next = [
      for (var i = 0; i < observations.length; i++)
        if (i != index) Map<String, dynamic>.from(observations[i]),
    ];
    final latest = next.last;
    final payload = Map<String, dynamic>.from(saved)
      ..remove('id')
      ..remove('setId')
      ..remove('mode')
      ..remove('folder')
      ..remove('createdAt')
      ..remove('updatedAt');
    payload['observations'] = next;
    for (final key in [
      'result',
      'start',
      'end',
      'anchors',
      'reps',
      'status',
      'hasVideo',
      'mirrored',
      'view',
    ]) {
      payload[key] = latest[key];
    }
    await repo.save(
      id: id,
      setId: setId,
      mode: latest['mode'] as String,
      folder: latest['folder'] as String,
      payload: payload,
    );
    observations = next;
    activeObservation = 0;
    await _openObservation(next.first);
  });

  Future<void> import(Map<String, dynamic> input) => run(() async {
    phase = 'loading';
    _nextSession();
    final generation = _generation;
    _notify();
    final value = await bridge.call('import', input);
    if (_disposed || generation != _generation) {
      if (value['folder'] is String) {
        await bridge.call('release', {'folder': value['folder']});
      }
      return;
    }
    folder = value['folder'] as String;
    _held.add(folder!);
    uri = value['uri'] as String?;
    duration = (value['duration'] as num).round();
    start = 0;
    end = duration.clamp(1, 180000);
    time = 0;
    width = (value['width'] as num?)?.toDouble() ?? width;
    height = (value['height'] as num?)?.toDouble() ?? height;
    frames = [];
    times = [];
    anchors = [];
    reps = [];
    result = null;
    image = null;
    status = 'incomplete';
    dirty = true;
    needsAnalysis = true;
    mode = 'import';
    phase = 'ready';
  });
  Future<void> frame(int t) => run(() async {
    final request = ++_frameGeneration, generation = _generation;
    final value = await bridge.call('frame', {'folder': folder, 't': t});
    if (_disposed || request != _frameGeneration || generation != _generation) {
      return;
    }
    time = (value['t'] as num).round();
    image = value['image'] is String
        ? base64Decode(value['image'] as String)
        : value['bytes'] as Uint8List?;
    width = (value['width'] as num?)?.toDouble() ?? width;
    height = (value['height'] as num?)?.toDouble() ?? height;
  });
  Future<void> mark(double x, double y, double radius) => run(() async {
    if (!cameraActive && (time < start || time > end)) {
      throw StateError('请在选定片段内标记杠铃');
    }
    final anchor = <String, dynamic>{
      't': time,
      'x': x.clamp(0, 1),
      'y': y.clamp(0, 1),
      'radius': radius,
    };
    if (cameraActive) {
      await bridge.call('mark', {'anchor': anchor});
      if (phase == 'recording') {
        anchors = [...anchors.where((a) => a['t'] != time), anchor];
      }
    } else {
      anchors = [...anchors.where((a) => a['t'] != time), anchor]
        ..sort((a, b) => (a['t'] as int).compareTo(b['t'] as int));
      needsAnalysis = true;
    }
    dirty = true;
  });
  Future<void> analyze() => run(() async {
    final session = _nextSession();
    final generation = _generation;
    phase = 'loading';
    needsAnalysis = true;
    progress = 0;
    _notify();
    // Incremental observations replace only this editor's working copy.
    frames = [];
    reps = [];
    times = [];
    phase = 'analyzing';
    _notify();
    final value = await bridge.call('analyze', {
      'folder': folder,
      'start': start,
      'end': end,
      'anchors': anchors,
      'session': session,
    });
    if (_disposed || generation != _generation) return;
    final next = value['result'] as String;
    data(
      value['data'] is Map
          ? Map<String, dynamic>.from(value['data'] as Map)
          : await bridge.call('load', {'folder': folder, 'result': next}),
    );
    result = next;
    if (!kIsWeb && textureId != null && frames.isNotEmpty) {
      await frame(frames.last.t);
      if (_disposed || generation != _generation) return;
    }
    status = 'completed';
    phase = 'review';
    progress = 1;
    dirty = true;
    needsAnalysis = false;
  });
  Future<void> camera({String? deviceId}) => run(() async {
    final session = _nextSession();
    final generation = _generation;
    phase = 'loading';
    mode = 'camera';
    _notify();
    final value = await bridge.call('camera', {
      'session': session,
      'deviceId': deviceId,
    });
    if (_disposed || generation != _generation) return;
    devices = [
      for (final d in value['devices'] as List? ?? [])
        Map<String, dynamic>.from(d as Map),
    ];
    canRecord = value['canRecord'] != false;
    phase = 'preview';
    frames = [];
    anchors = [];
    image = null;
    _notify();
  });
  Future<void> startCamera() => run(() async {
    final generation = _generation;
    phase = 'loading';
    _notify();
    try {
      await bridge.call('startCamera');
    } catch (_) {
      await bridge.call('close');
      rethrow;
    }
    if (_disposed || generation != _generation) return;
    frames = [];
    reps = [];
    times = [];
    start = 0;
    time = 0;
    phase = 'recording';
    dirty = true;
  });
  void _completed(Map<String, dynamic> value) {
    if (value['folder'] == null) return;
    folder = value['folder'] as String;
    _held.add(folder!);
    uri = value['uri'] as String?;
    result = value['result'] as String;
    data(Map<String, dynamic>.from(value['data'] as Map));
    duration = (value['duration'] as num).round().clamp(1, 180000);
    start = 0;
    end = duration;
    status = value['status'] as String? ?? 'stopped';
    phase = 'review';
    canRecord = value['canRecord'] != false;
    dirty = true;
    needsAnalysis = false;
  }

  Future<void> stopCamera({bool interrupted = false}) => run(() async {
    final generation = _generation;
    phase = 'loading';
    _notify();
    final value = await bridge.call('stopCamera', {'interrupted': interrupted});
    if (_disposed || generation != _generation) return;
    _completed(value);
    if (value['folder'] == null) phase = 'ready';
  });
  Future<void> cancel() async {
    _nextSession();
    phase = 'cancelled';
    status = 'incomplete';
    await bridge.call('cancel');
    _notify();
  }

  Future<void> save() => run(() async {
    if (folder == null || result == null || needsAnalysis) {
      throw StateError('请先完成分析后保存');
    }
    if (!validReviewReps(reps, start, end)) throw StateError('请修正次数边界');
    phase = 'saving';
    _notify();
    final observation = <String, dynamic>{
      'id': activeObservation >= 0
          ? observations[activeObservation]['id']
          : newId(),
      'motionId': motionId,
      'profileVersion': MotionCatalog.byId(motionId).version,
      'analyzerId': MotionCatalog.byId(motionId).analyzerId,
      'analyzerVersion': MotionCatalog.byId(motionId).analyzerVersion,
      'resultVersion': MotionCatalog.byId(motionId).resultVersion,
      'modelDependencies': MotionCatalog.byId(motionId).modelDependencies,
      'view': view.name,
      'mode': mode,
      'folder': folder,
      'result': result,
      'start': start,
      'end': end,
      'anchors': anchors,
      'reps': reps.map((r) => r.toJson()).toList(),
      'status': status,
      'hasVideo': canRecord,
      'mirrored': mirrored,
      'width': width,
      'height': height,
      'qualityObservations': [
        for (
          var i = 0;
          i < MotionCatalog.byId(motionId).candidateObservations.length;
          i++
        )
          {
            'metricId': '$motionId.quality.$i',
            'name': MotionCatalog.byId(motionId).candidateObservations[i],
            'state': 'unknown',
            'reason': 'not_validated',
            'startMs': start,
            'endMs': end,
            'view': view.name,
            'profileVersion': MotionCatalog.byId(motionId).version,
            'requiredLandmarks': MotionCatalog.byId(motionId).landmarks,
          },
      ],
    };
    final next = [
      for (final item in observations) Map<String, dynamic>.from(item),
    ];
    if (activeObservation < 0) {
      next.add(observation);
    } else {
      next[activeObservation] = observation;
    }
    await repo.save(
      id: id,
      setId: setId,
      mode: mode,
      folder: folder!,
      payload: {
        'version': 3,
        'motionId': motionId,
        'profileVersion': MotionCatalog.byId(motionId).version,
        'view': view.name,
        'observations': next,
        'result': result,
        'start': start,
        'end': end,
        'anchors': anchors,
        'reps': reps.map((r) => r.toJson()).toList(),
        'status': status,
        'model': 'pose-lite-f16-1',
        'algorithm': 'lk-fb-template-2',
        'hasVideo': canRecord,
        'mirrored': mirrored,
      },
    );
    observations = next;
    activeObservation = next.indexWhere(
      (item) => item['id'] == observation['id'],
    );
    dirty = false;
    phase = 'saved';
  });
  void changed() {
    dirty = true;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _subscription?.cancel();
    unawaited(() async {
      try {
        await bridge.call('close');
        for (final f in _held) {
          await bridge.call('release', {'folder': f});
        }
        final files = await repo.resultFiles();
        await bridge.call('collect', {
          'keep': files.keys.toList(),
          'results': files,
        });
      } catch (_) {
        /* Cleanup retries on the next editor/startup. */
      }
    }());
    super.dispose();
  }
}
