import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../data/files/video_review_bridge.dart';
import '../../data/repositories/executor_access.dart';
import '../../data/repositories/video_review_repo.dart';
import '../../domain/video_review.dart';
import '../../domain/set_detail.dart';
import 'rep_editor.dart';
import 'review_overlay.dart';

class VideoReviewPage extends StatefulWidget {
  final String setId;
  const VideoReviewPage({super.key, required this.setId});
  @override
  State<VideoReviewPage> createState() => _VideoReviewPageState();
}

class _VideoReviewPageState extends State<VideoReviewPage> {
  final bridge = VideoReviewBridge();
  late VideoReviewRepo repo;
  VideoPlayerController? player;
  StreamSubscription<dynamic>? progressSub;
  Map<String, Object?>? group;
  String? folder, resultFile, message;
  final heldFolders = <String>{};
  List<ReviewFrame> frames = [];
  List<int> times = [];
  List<ReviewRep> reps = [];
  List<Map<String, dynamic>> anchors = [];
  int start = 0, end = 0, time = 0;
  double duration = 1, progress = 0, radius = .08;
  double imageWidth = 640, imageHeight = 360;
  bool busy = false, loading = true, dirty = false, marking = false;
  bool needsAnalysis = false;
  bool trajectory = true, skeleton = true, compare = false, allowPop = false;
  Uint8List? still;
  String? poseError;
  int _lastTick = -1;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    repo = VideoReviewRepo(context.read<SqlExecutor>());
    try {
      group = await repo.group(widget.setId);
      if (!mounted) return;
      if (VideoReviewBridge.supported && group != null) {
        progressSub = VideoReviewBridge.events.receiveBroadcastStream().listen((
          event,
        ) {
          if (mounted && event['folder'] == folder) {
            setState(() => progress = (event['progress'] as num).toDouble());
          }
        }, onError: (_) {});
        final saved = await repo.load(widget.setId);
        if (saved != null) {
          folder = saved['folder'] as String;
          final metadata = await bridge.call('open', {'folder': folder});
          if (!mounted) {
            await bridge.release(folder!);
            return;
          }
          heldFolders.add(folder!);
          await _openPlayer(metadata);
          start = saved['start'] as int;
          end = saved['end'] as int;
          anchors = [
            for (final p in saved['anchors'] as List)
              Map<String, dynamic>.from(p as Map),
          ];
          resultFile = saved['result'] as String;
          await _loadResult(resultFile!);
          reps = [
            for (final r in saved['reps'] as List)
              ReviewRep.fromJson(r as List),
          ];
          await player!.seekTo(Duration(milliseconds: start));
        }
      }
    } catch (e) {
      message = '复盘暂不可用：${_error(e)}。训练记录仍然保留，可重新导入或删除复盘。';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _error(Object e) =>
      e is PlatformException ? e.message ?? e.code : e.toString();
  Future<void> _openPlayer(Map<String, dynamic> metadata) async {
    final next = VideoPlayerController.contentUri(
      Uri.parse(metadata['uri'] as String),
    );
    try {
      await next.initialize();
    } catch (_) {
      await next.dispose();
      rethrow;
    }
    if (!mounted) {
      await next.dispose();
      return;
    }
    final old = player;
    old?.removeListener(_tick);
    player = next;
    next.addListener(_tick);
    duration = (metadata['duration'] as num).toDouble();
    await old?.dispose();
  }

  void _tick() {
    if (!mounted || player == null || still != null) return;
    final t = player!.value.position.inMilliseconds;
    if (player!.value.isPlaying && t >= end && end > start) {
      player!.pause();
    }
    if ((t - _lastTick).abs() >= 60 || !player!.value.isPlaying) {
      _lastTick = t;
      setState(() => time = t);
    }
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('请确认'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _import() async {
    if (folder != null && !await _confirm('选择新视频后需要重新分析，点击保存才替换已有复盘。')) return;
    if (!mounted) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final picked = await FilePicker.pickFile(type: FileType.video);
      if (picked == null) return;
      final path = picked.path;
      if (path == null) throw StateError('视频不可读取，请从本地相册或文件选择');
      final metadata = await bridge.call('import', {'path': path});
      final importedFolder = metadata['folder'] as String;
      heldFolders.add(importedFolder);
      if (!mounted) {
        await bridge.release(importedFolder);
        return;
      }
      await _openPlayer(metadata);
      folder = importedFolder;
      start = 0;
      end = duration.round().clamp(1, 180000);
      time = 0;
      frames = [];
      reps = [];
      anchors = [];
      times = [];
      resultFile = null;
      still = null;
      poseError = null;
      dirty = true;
      needsAnalysis = true;
      marking = false;
    } catch (e) {
      message = _error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _loadResult(String result) async {
    final data = await bridge.load(folder!, result);
    if (data['version'] != 1) throw StateError('不支持的复盘数据版本');
    frames = [
      for (final f in data['frames'] as List)
        ReviewFrame.fromJson(Map<String, dynamic>.from(f as Map)),
    ];
    times = (data['times'] as List).cast<int>();
    imageWidth = (data['width'] as num).toDouble();
    imageHeight = (data['height'] as num).toDouble();
    poseError = data['poseError'] as String?;
  }

  Future<void> _frame(int requested, {bool mark = false}) async {
    if (busy || folder == null) return;
    await player?.pause();
    setState(() => busy = true);
    try {
      final data = await bridge.call('frame', {
        'folder': folder,
        't': requested,
      });
      if (!mounted) return;
      time = (data['t'] as num).toInt();
      await player?.seekTo(Duration(milliseconds: time));
      still = data['bytes'] as Uint8List;
      marking = mark;
    } catch (e) {
      message = _error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _step(bool forward) async {
    final next = forward
        ? times.where((t) => t > time).firstOrNull
        : times.where((t) => t < time).lastOrNull;
    if (next != null) await _frame(next);
  }

  void _mark(Offset point, Size size) {
    if (!marking || busy) return;
    if (time < start || time > end) {
      setState(() => message = '请在选定的一组片段内重新定位');
      return;
    }
    final anchor = <String, dynamic>{
      't': time,
      'x': (point.dx / size.width).clamp(0, 1),
      'y': (point.dy / size.height).clamp(0, 1),
      'radius': radius,
    };
    setState(() {
      anchors = [...anchors.where((a) => a['t'] != time), anchor]
        ..sort((a, b) => (a['t'] as int).compareTo(b['t'] as int));
      dirty = true;
      marking = false;
      message = '已标记 ${_seconds(time)} 秒位置，请重新分析以应用标记。';
      needsAnalysis = true;
    });
  }

  Future<void> _analyze() async {
    if (anchors.isEmpty ||
        (anchors.first['t'] as int) < start ||
        (anchors.first['t'] as int) - start > 150) {
      setState(() => message = '请先点击「标记片段首帧」，再点选杠铃片中心。');
      return;
    }
    await player?.pause();
    setState(() {
      busy = true;
      progress = 0;
      message = null;
    });
    final oldFrames = frames, oldTimes = times, oldReps = reps;
    final oldResult = resultFile;
    try {
      final value = await bridge.call('analyze', {
        'folder': folder,
        'start': start,
        'end': end,
        'anchors': anchors,
      });
      if (!mounted) return;
      final next = value['result'] as String;
      await _loadResult(next);
      resultFile = next;
      needsAnalysis = false;
      reps = detectReviewReps(frames);
      dirty = true;
      still = null;
      marking = false;
      message = '分析完成，请核对次数和边界。识别不清的区间不会计算指标。';
    } catch (e) {
      frames = oldFrames;
      times = oldTimes;
      reps = oldReps;
      resultFile = oldResult;
      message = _error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _editRep(int? index) async {
    final base = index == null
        ? ReviewRep(time, time + 500, time + 500, time + 1000)
        : reps[index];
    final rep = await editReviewRep(context, base);
    if (rep == null || !mounted) return;
    final next = [...reps];
    if (index == null) {
      next.add(rep);
    } else {
      next[index] = rep;
    }
    next.sort((a, b) => a.startMs.compareTo(b.startMs));
    if (!validReviewReps(next, start, end)) {
      setState(() => message = '次数不能重叠或超出选定片段，请调整时间');
      return;
    }
    setState(() {
      reps = next;
      dirty = true;
    });
  }

  Future<void> _save() async {
    if (needsAnalysis) {
      setState(() => message = '标记已经修改，请重新分析后再保存');
      return;
    }
    if (resultFile == null || folder == null) return;
    if (!validReviewReps(reps, start, end)) {
      setState(() => message = '请先修正次数边界');
      return;
    }
    setState(() => busy = true);
    try {
      await repo.save(widget.setId, folder!, {
        'version': 1,
        'result': resultFile,
        'start': start,
        'end': end,
        'anchors': anchors,
        'reps': reps.map((r) => r.toJson()).toList(),
      });
      dirty = false;
      message = '已保存到这组训练，原次数和用力程度保持你的记录。';
      await _collectReleased();
    } catch (e) {
      message = _error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await _confirm('删除本组复盘及应用内视频副本？相册原视频和训练记录保留。')) return;
    setState(() => busy = true);
    try {
      await repo.delete(widget.setId);
      dirty = false;
      if (mounted) {
        setState(() => allowPop = true);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          message = _error(e);
          busy = false;
        });
      }
    }
  }

  Future<void> _collectReleased() async {
    final release = heldFolders.where((f) => f != folder).toList();
    for (final f in release) {
      await bridge.release(f);
      heldFolders.remove(f);
    }
    final results = await repo.resultFiles();
    await bridge.collect(results.keys.toList(), results: results);
  }

  Future<void> _leave() async {
    if (busy) {
      setState(() => message = '正在处理，请先取消分析或等待完成');
      return;
    }
    if (dirty && !await _confirm('本次修改尚未保存，放弃修改并返回？已保存的复盘仍会保留。')) return;
    if (mounted) {
      setState(() => allowPop = true);
      Navigator.pop(context);
    }
  }

  String _seconds(int t) => (t / 1000).toStringAsFixed(2);
  String get _groupLabel {
    if (group == null) return '';
    final g = group!;
    String? effort;
    try {
      effort = g['detail'] == null
          ? null
          : SetDetail.decode(g['detail'] as String).effort?.label;
    } catch (_) {}
    return '${g['name']} · ${g['source_weight'] ?? g['weight']} ${g['source_unit'] ?? 'kg'} × ${g['reps']}${effort == null ? '' : ' · $effort'}';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop || (!dirty && !busy),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('卧推复盘'),
        actions: [
          if (folder != null)
            IconButton(
              tooltip: '删除复盘',
              onPressed: busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          if (resultFile != null)
            TextButton(
              onPressed: busy || needsAnalysis ? null : _save,
              child: Text(dirty ? '保存' : '已保存'),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : group == null
          ? const Center(child: Text('这组训练不存在或尚未完成'))
          : !VideoReviewBridge.supported
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('视频复盘目前支持 Android 手机。训练记录和其他功能可继续使用。'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _groupLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text('固定侧面 · 本地处理 · 实验性功能\n请核对轨迹和次数；识别效果尚待真实卧推视频验证。'),
                const SizedBox(height: 12),
                if (player == null) ...[
                  const Icon(Icons.video_library_outlined, size: 56),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '练完一组，再看每一次\n\n固定手机，从侧面拍摄，让近侧杠铃片和上半身完整入镜。整组不要移动手机或变焦。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ] else ...[
                  _video(),
                  Slider(
                    value: time.toDouble().clamp(0, duration),
                    min: 0,
                    max: duration,
                    onChanged: busy
                        ? null
                        : (v) {
                            setState(() {
                              still = null;
                              marking = false;
                              time = v.round();
                            });
                            player!.seekTo(Duration(milliseconds: v.round()));
                          },
                  ),
                  Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: '上一帧',
                        onPressed: busy || times.isEmpty
                            ? null
                            : () => _step(false),
                        icon: const Icon(Icons.skip_previous),
                      ),
                      IconButton(
                        tooltip: '播放或暂停',
                        onPressed: busy
                            ? null
                            : () async {
                                setState(() {
                                  still = null;
                                  marking = false;
                                });
                                if (player!.value.isPlaying) {
                                  await player!.pause();
                                } else {
                                  if (time < start || time >= end) {
                                    await player!.seekTo(
                                      Duration(milliseconds: start),
                                    );
                                  }
                                  await player!.play();
                                }
                              },
                        icon: Icon(
                          player!.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                      ),
                      IconButton(
                        tooltip: '下一帧',
                        onPressed: busy || times.isEmpty
                            ? null
                            : () => _step(true),
                        icon: const Icon(Icons.skip_next),
                      ),
                      Text('${_seconds(time)} 秒'),
                      for (final speed in [.25, .5, 1.0])
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => player!.setPlaybackSpeed(speed),
                          child: Text('$speed×'),
                        ),
                    ],
                  ),
                  if (resultFile == null) ...[
                    Text(
                      '选择这一组：${_seconds(start)}–${_seconds(end)} 秒（最长 3 分钟）',
                    ),
                    RangeSlider(
                      values: RangeValues(start.toDouble(), end.toDouble()),
                      max: duration,
                      onChanged: busy
                          ? null
                          : (v) {
                              if (v.end - v.start < 300 ||
                                  v.end - v.start > 180000) {
                                return;
                              }
                              setState(() {
                                start = v.start.round();
                                end = v.end.round();
                                anchors = [];
                                dirty = true;
                              });
                            },
                    ),
                  ],
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => _frame(start, mark: true),
                        child: const Text('标记片段首帧'),
                      ),
                      OutlinedButton(
                        onPressed: busy || resultFile == null
                            ? null
                            : () => _frame(time, mark: true),
                        child: const Text('在此重新定位'),
                      ),
                    ],
                  ),
                  if (marking) ...[
                    const Text('点击近侧杠铃片中心。调整圈大小，使它覆盖杠铃片纹理，避开背景。'),
                    Slider(
                      value: radius,
                      min: .02,
                      max: .3,
                      label: '${(radius * 100).round()}%',
                      onChanged: busy
                          ? null
                          : (v) => setState(() => radius = v),
                    ),
                  ],
                  if (anchors.isNotEmpty) Text('已标记 ${anchors.length} 个位置'),
                  FilledButton.icon(
                    onPressed: busy ? null : _analyze,
                    icon: const Icon(Icons.analytics_outlined),
                    label: Text(resultFile == null ? '分析这一组' : '重新分析'),
                  ),
                  if (frames.isNotEmpty) ...[
                    if (needsAnalysis) const Text('当前显示上次分析；新标记尚未应用，请重新分析。'),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('杠铃轨迹'),
                          selected: trajectory,
                          onSelected: (v) => setState(() => trajectory = v),
                        ),
                        FilterChip(
                          label: const Text('骨架'),
                          selected: skeleton,
                          onSelected: (v) => setState(() => skeleton = v),
                        ),
                        FilterChip(
                          label: const Text('多次叠加'),
                          selected: compare,
                          onSelected: (v) => setState(() => compare = v),
                        ),
                      ],
                    ),
                    Text(
                      compare ? '多次轨迹仅平移到共同起点，保留幅度差异。' : '橙色下降 · 青色推起 · 绿色骨架',
                    ),
                    if (frames.any((f) => !f.valid))
                      const Text('部分轨迹识别不清：缺口不会连线，可在缺口处重新定位。'),
                    if (poseError != null) Text(poseError!),
                    _angle(),
                    const Divider(height: 32),
                    Text(
                      '逐次复盘 · 识别 ${reps.length} 次 / 记录 ${group!['reps']} 次',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text('相对幅度以本组有效次数中位数为 100%，不代表厘米。底部停顿是轨迹估计。'),
                    ..._repCards(),
                    TextButton.icon(
                      onPressed: busy ? null : () => _editRep(null),
                      icon: const Icon(Icons.add),
                      label: const Text('手动添加一次'),
                    ),
                  ],
                ],
                if (busy) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                  ),
                  TextButton(
                    onPressed: bridge.cancel,
                    child: const Text('取消分析'),
                  ),
                ],
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(liveRegion: true, child: Text(message!)),
                  ),
                OutlinedButton.icon(
                  onPressed: busy ? null : _import,
                  icon: const Icon(Icons.video_file_outlined),
                  label: Text(folder == null ? '添加卧推视频' : '替换视频'),
                ),
                const Text('视频仅保存在本机，不包含在 JSON 备份中。'),
              ],
            ),
    ),
  );

  Widget _video() => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: ColoredBox(
      color: Colors.black,
      child: AspectRatio(
        aspectRatio: player!.value.aspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              onTapDown: (event) => _mark(event.localPosition, size),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (still != null)
                    Image.memory(
                      still!,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    )
                  else
                    VideoPlayer(player!),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: ReviewOverlay(
                        frames: frames,
                        reps: reps,
                        time: time,
                        trajectory: trajectory,
                        skeleton: skeleton,
                        compare: compare,
                        anchors: anchors,
                      ),
                    ),
                  ),
                  if (marking)
                    const Positioned(
                      left: 8,
                      top: 8,
                      child: ColoredBox(
                        color: Colors.black54,
                        child: Padding(
                          padding: EdgeInsets.all(6),
                          child: Text(
                            '点选杠铃片中心',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
  Widget _angle() {
    final near = frames.where((f) => (f.t - time).abs() <= 100).firstOrNull;
    final value = near == null
        ? null
        : reviewElbowAngle(near, imageWidth, imageHeight);
    return Text(
      value == null
          ? '当前帧肘角：不可计算'
          : '可见侧二维肘角：${value.toStringAsFixed(0)}°（投影参考）',
    );
  }

  List<Widget> _repCards() {
    final metrics = reviewMetrics(frames, reps);
    return [
      for (var i = 0; i < reps.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              setState(() {
                                still = null;
                                time = reps[i].startMs;
                              });
                              player!.seekTo(Duration(milliseconds: time));
                            },
                      child: Text(
                        '第 ${i + 1} 次 · ${_seconds(reps[i].startMs)} 秒',
                      ),
                    ),
                    IconButton(
                      tooltip: '修正第 ${i + 1} 次',
                      onPressed: busy ? null : () => _editRep(i),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: '移除第 ${i + 1} 次',
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              reps = [...reps]..removeAt(i);
                              dirty = true;
                            }),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
                Text(
                  metrics[i].valid
                      ? '下降 ${reps[i].downSeconds.toStringAsFixed(2)} 秒 · 底部 ${reps[i].pauseSeconds.toStringAsFixed(2)} 秒 · 推起 ${reps[i].upSeconds.toStringAsFixed(2)} 秒'
                      : '此次数包含缺失片段，指标不可计算',
                ),
                Text(
                  metrics[i].relativeAmplitude == null
                      ? '相对幅度：暂无可比结果'
                      : '相对幅度 ${metrics[i].relativeAmplitude!.toStringAsFixed(0)}%',
                ),
              ],
            ),
          ),
        ),
    ];
  }

  @override
  void dispose() {
    progressSub?.cancel();
    player?.removeListener(_tick);
    player?.dispose();
    if (VideoReviewBridge.supported) {
      unawaited(() async {
        try {
          await bridge.cancel();
          for (final f in heldFolders) {
            await bridge.release(f);
          }
          final results = await repo.resultFiles();
          await bridge.collect(results.keys.toList(), results: results);
        } catch (_) {
          /* Startup retries orphan cleanup. */
        }
      }());
    }
    super.dispose();
  }
}
