import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/files/motion_bridge.dart';
import 'package:gym_tracker/data/repositories/motion_project_repo.dart';
import 'package:gym_tracker/domain/motion_catalog.dart';
import 'package:gym_tracker/state/motion_analysis_controller.dart';

class TestBridge extends MotionBridge {
  final stream = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final tasks = <Completer<Map<String, dynamic>>>[];
  final sessions = <String>[];
  bool failFirstClose = false;
  int closeCalls = 0;
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (method == 'close') {
      closeCalls++;
      if (failFirstClose && closeCalls == 1) throw StateError('close failed');
    }
    if (method == 'analyze') {
      sessions.add(args['session'] as String);
      final task = Completer<Map<String, dynamic>>();
      tasks.add(task);
      return task.future;
    }
    if (method == 'open') return {'uri': 'memory:video', 'duration': 1000};
    if (method == 'load') {
      return {
        'version': 2,
        'frames': <Object>[],
        'times': <Object>[],
        'width': 640,
        'height': 360,
      };
    }
    return {};
  }
}

void main() {
  test(
    'a failed platform close can be retried and successful close is idempotent',
    () async {
      final db = await FfiExecutor.openMigrated(),
          bridge = TestBridge()..failFirstClose = true;
      final c = MotionAnalysisController(MotionProjectRepo(db), bridge: bridge);
      await expectLater(c.closeSession(), throwsStateError);
      await c.closeSession();
      await c.closeSession();
      expect(bridge.closeCalls, 2);
      c.dispose();
      await bridge.stream.close();
      await db.close();
    },
  );
  test(
    'late callbacks and cancelled computation cannot change a new generation',
    () async {
      final db = await FfiExecutor.openMigrated(), bridge = TestBridge();
      final c = MotionAnalysisController(MotionProjectRepo(db), bridge: bridge)
        ..folder = 'media';
      final first = c.analyze();
      await Future<void>.delayed(Duration.zero);
      await c.cancel();
      final second = c.analyze();
      await Future<void>.delayed(Duration.zero);
      bridge.stream.add({
        'session': bridge.sessions.first,
        'frame': {'t': 900, 'x': .1, 'y': .2},
      });
      expect(c.frames, isEmpty);
      bridge.tasks.first.completeError(StateError('old failure'));
      await first;
      expect(c.phase, 'analyzing');
      expect(c.error, isNull);
      bridge.stream.add({
        'session': bridge.sessions.last,
        'frame': {'t': 125, 'x': null, 'y': null, 'missingReason': 'unmarked'},
      });
      expect(c.frames.single.t, 125);
      expect(c.reps, isEmpty);
      await c.cancel();
      bridge.tasks.last.completeError(StateError('cancelled'));
      await second;
      expect(c.phase, 'cancelled');
      expect(c.status, 'incomplete');
      c.dispose();
      await Future<void>.delayed(Duration.zero);
      await bridge.stream.close();
      await db.close();
    },
  );
  test(
    'multi-view load keeps group link and removal retains other media',
    () async {
      final db = await FfiExecutor.openMigrated(), bridge = TestBridge();
      final repo = MotionProjectRepo(db);
      await db.run(
        "INSERT INTO exercise(id,name,created_at) VALUES('e','Bench',0)",
      );
      await db.run("INSERT INTO session(id,started_at) VALUES('s',0)");
      await db.run(
        "INSERT INTO session_exercise(id,session_id,exercise_id,position) VALUES('se','s','e',0)",
      );
      await db.run(
        "INSERT INTO set_entry(id,session_exercise_id,position,weight,reps,is_completed) VALUES('st','se',0,60,8,1)",
      );
      final side = {
        'id': 'side',
        'motionId': 'barbell_bench_press',
        'view': 'side',
        'mode': 'import',
        'folder': 'media-side',
        'result': 'result-side',
        'start': 0,
        'end': 1000,
        'reps': <Object>[],
      };
      final front = {
        'id': 'front',
        'motionId': 'barbell_bench_press',
        'view': 'front',
        'mode': 'import',
        'folder': 'media-front',
        'result': 'result-front',
        'start': 0,
        'end': 1000,
        'reps': <Object>[],
      };
      await repo.save(
        id: 'p',
        setId: 'st',
        mode: 'import',
        folder: 'media-front',
        payload: {
          'version': 3,
          'result': 'result-front',
          'observations': [side, front],
        },
      );
      final c = MotionAnalysisController(repo, bridge: bridge, id: 'p');
      await c.open((await repo.load('p'))!);
      expect(c.setId, 'st');
      expect(c.view.name, 'side');
      await c.selectObservation(1);
      expect(c.view.name, 'front');
      await c.removeObservation(1);
      expect(c.observations, hasLength(1));
      expect(c.view.name, 'side');
      expect((await repo.load('p'))!['setId'], 'st');
      expect(await repo.resultFiles(), {'media-side': 'result-side'});
      c.dispose();
      await Future<void>.delayed(Duration.zero);
      await bridge.stream.close();
      await db.close();
    },
  );
  test('saving a second angle keeps the first result reference', () async {
    final db = await FfiExecutor.openMigrated(), bridge = TestBridge();
    final repo = MotionProjectRepo(db);
    final c = MotionAnalysisController(repo, bridge: bridge, id: 'multi')
      ..folder = 'side-media'
      ..result = 'side-result'
      ..start = 0
      ..end = 1000;
    await c.save();
    expect(c.observations, hasLength(1));
    c.beginAdditional(newView: MotionView.front);
    c.folder = 'front-media';
    c.result = 'front-result';
    c.end = 1000;
    await c.save();
    final saved = (await repo.load('multi'))!;
    expect(saved['observations'], hasLength(2));
    expect(await repo.resultFiles(), {
      'side-media': 'side-result',
      'front-media': 'front-result',
    });
    c.dispose();
    await Future<void>.delayed(Duration.zero);
    await bridge.stream.close();
    await db.close();
  });
}
