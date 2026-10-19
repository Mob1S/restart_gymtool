import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/files/video_review_bridge.dart';
import 'package:gym_tracker/data/repositories/video_review_repo.dart';
import 'package:gym_tracker/features/review/video_review_page.dart';

class _Video extends VideoPlayerPlatform {
  Duration position = Duration.zero;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 2),
      size: const Size(640, 360),
    ),
  );
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<void> seekTo(int playerId, Duration p) async {
    position = p;
  }

  @override
  Future<Duration> getPosition(int playerId) async => position;
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FfiExecutor db;
  late VideoReviewRepo repo;
  late VideoPlayerPlatform oldVideo;
  const folder = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  final saved = <String, dynamic>{
    'version': 1,
    'result': 'result-old.json',
    'start': 0,
    'end': 2000,
    'anchors': [
      {'t': 0, 'x': .5, 'y': .2, 'radius': .08},
    ],
    'reps': [
      [0, 1000, 1000, 2000],
    ],
  };
  setUp(() async {
    oldVideo = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _Video();
    db = await FfiExecutor.openMigrated();
    repo = VideoReviewRepo(db);
    await db.run(
      "INSERT INTO exercise(id,name,is_custom,is_archived,created_at) VALUES('e','卧推',1,0,0)",
    );
    await db.run("INSERT INTO session(id,started_at) VALUES('s',0)");
    await db.run(
      "INSERT INTO session_exercise(id,session_id,exercise_id,position) VALUES('se','s','e',0)",
    );
    await db.run(
      "INSERT INTO set_entry(id,session_exercise_id,position,weight,reps,is_completed) VALUES('st','se',0,60,8,1)",
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('gym_tracker/review_progress'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VideoReviewBridge.channel, (call) async {
          if (call.method == 'open') {
            return {
              'folder': folder,
              'duration': 2000,
              'uri': 'file:///private/video',
            };
          }
          if (call.method == 'load') {
            return jsonEncode({
              'version': 1,
              'width': 640,
              'height': 360,
              'times': [0, 33, 67, 100, 150],
              'frames': [
                for (var i = 0; i <= 20; i++)
                  {
                    't': i * 100,
                    'x': .5,
                    'y': .2 + (i <= 10 ? i : 20 - i) * .02,
                    'pose': [],
                  },
              ],
            });
          }
          if (call.method == 'analyze') {
            throw PlatformException(code: 'review_error', message: '测试解码失败');
          }
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VideoReviewBridge.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('gym_tracker/review_progress'),
          null,
        );
    VideoPlayerPlatform.instance = oldVideo;
    await db.close();
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      Provider<SqlExecutor>.value(
        value: db,
        child: const MaterialApp(home: VideoReviewPage(setId: 'st')),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'unsupported platform shows capability message, no native processing',
    (tester) async {
      await open(tester);
      expect(find.textContaining('目前支持 Android'), findsOneWidget);
      expect(find.text('添加卧推视频'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
  testWidgets(
    'saved result loads and failed reanalysis preserves saved record',
    (tester) async {
      await tester.runAsync(() => repo.save('st', folder, saved));
      await open(tester);
      expect(find.textContaining('60.0 kg × 8'), findsOneWidget);
      expect(find.textContaining('复盘暂不可用'), findsNothing);
      await tester.scrollUntilVisible(find.text('重新分析'), 250);
      await tester.tap(find.text('重新分析'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('测试解码失败'), 250);
      expect(find.text('测试解码失败'), findsOneWidget);
      expect(
        (await tester.runAsync(() => repo.load('st')))!['result'],
        'result-old.json',
      );
      expect((await tester.runAsync(() => repo.group('st')))!['reps'], 8);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('missing media shows recovery actions without changing the set', (
    tester,
  ) async {
    await tester.runAsync(() => repo.save('st', folder, saved));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VideoReviewBridge.channel, (call) async {
          if (call.method == 'open') {
            throw PlatformException(code: 'review_error', message: '文件缺失');
          }
          return null;
        });
    await open(tester);
    expect(find.textContaining('文件缺失'), findsOneWidget);
    expect(find.text('替换视频'), findsOneWidget);
    expect((await tester.runAsync(() => repo.group('st')))!['reps'], 8);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('small viewport keeps saved video controls usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => repo.save('st', folder, saved));
    await open(tester);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('手动添加一次'), 250);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
