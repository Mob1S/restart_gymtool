import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../data/files/motion_bridge.dart';
import '../../data/repositories/executor_access.dart';
import '../../data/repositories/motion_project_repo.dart';
import '../../data/repositories/video_review_repo.dart';
import '../../domain/video_review.dart';
import '../../domain/motion_catalog.dart';
import '../../domain/motion_observations.dart';
import '../../state/motion_analysis_controller.dart';
import '../review/review_overlay.dart';
import '../review/rep_editor.dart';

Future<bool> Function()? analysisExitGuard;

class AnalysisSessionPage extends StatefulWidget {
  final String mode;
  final String? projectId, setId;
  final String? motionId;
  const AnalysisSessionPage({
    super.key,
    this.mode = 'import',
    this.projectId,
    this.setId,
    this.motionId,
  });
  @override
  State<AnalysisSessionPage> createState() => _AnalysisSessionPageState();
}

class _AnalysisSessionPageState extends State<AnalysisSessionPage>
    with WidgetsBindingObserver {
  MotionAnalysisController? controller;
  VideoPlayerController? player;
  bool loading = true,
      marking = false,
      skeleton = true,
      trajectory = true,
      mirror = false;
  double radius = .08;
  String? bootError, linkedLabel;
  String? _playerUri;
  bool _leaving = false;
  bool motionSelected = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    analysisExitGuard = _leave;
    _boot();
  }

  Future<void> _boot() async {
    try {
      final exec = context.read<SqlExecutor>(), repo = MotionProjectRepo(exec);
      final saved = widget.projectId != null
          ? await repo.load(widget.projectId!)
          : widget.setId != null
          ? await repo.forSet(widget.setId!)
          : null;
      if (!mounted) return;
      final c = MotionAnalysisController(
        repo,
        id: saved?['id'] as String?,
        setId: widget.setId,
        mode: widget.mode,
        motionId: widget.motionId ?? MotionCatalog.bench,
      );
      motionSelected =
          saved != null || widget.motionId != null || widget.setId != null;
      controller = c;
      c.addListener(_changed);
      if (saved != null) await c.open(saved);
      mirror = c.mirrored;
      if (saved != null && mounted) await _player();
      if (widget.setId != null) {
        final group = await VideoReviewRepo(exec).group(widget.setId!);
        linkedLabel = group == null
            ? '原训练组已删除'
            : '训练记录：${group['weight']} kg × ${group['reps']} 次';
      }
    } catch (e) {
      bootError = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  void _changed() {
    if (mounted) setState(() {});
    if (mounted &&
        controller?.uri != null &&
        controller!.uri != _playerUri &&
        !controller!.cameraActive &&
        !controller!.busy) {
      _player();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = controller;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (c?.phase == 'recording') {
        c!.stopCamera(interrupted: true);
      } else if (c?.phase == 'preview') {
        c!.bridge.call('close').then((_) {
          c.phase = 'ready';
          if (mounted) setState(() {});
        });
      } else if (c?.phase == 'analyzing') {
        c!.cancel();
      }
    }
  }

  Future<bool> _leave() async {
    if (_leaving) return true;
    final c = controller;
    if (c != null && (c.dirty || c.busy || c.cameraActive)) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('离开动作分析？'),
          content: const Text('未保存的本次分析将放弃，摄像头和推理会停止。已保存的项目保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续分析'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('放弃并离开'),
            ),
          ],
        ),
      );
      if (leave != true) return false;
    }
    _leaving = true;
    if (c != null) await c.cancel();
    return true;
  }

  Future<void> _import() async {
    if (controller!.dirty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('替换本次视频？'),
          content: const Text('未保存的修改将放弃，已保存项目在再次保存前保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('替换视频'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    final file = await FilePicker.pickFile(type: FileType.video);
    if (file == null || !mounted) return;
    await player?.pause();
    await controller!.import({
      'path': kIsWeb ? file.uri.toString() : file.path,
    });
    await _player();
  }

  Future<void> _additional(String mode) async {
    final c = controller!;
    if (c.dirty) return;
    await player?.pause();
    await player?.dispose();
    player = null;
    _playerUri = null;
    c.beginAdditional(newView: c.view, newMode: mode);
    if (mounted) setState(() {});
  }

  Future<void> _selectObservation(int index) async {
    await player?.pause();
    await player?.dispose();
    player = null;
    _playerUri = null;
    await controller!.selectObservation(index);
    await _player();
  }

  Future<void> _removeObservation() async {
    final c = controller!;
    if (c.activeObservation < 0 || c.observations.length < 2) return;
    await player?.pause();
    await player?.dispose();
    player = null;
    _playerUri = null;
    await c.removeObservation(c.activeObservation);
    await _player();
  }

  Future<void> _player() async {
    final c = controller!;
    if (c.uri == null || c.uri == _playerUri) return;
    _playerUri = c.uri;
    final next = kIsWeb
        ? VideoPlayerController.networkUrl(Uri.parse(c.uri!))
        : VideoPlayerController.contentUri(Uri.parse(c.uri!));
    try {
      await next.initialize();
      if (!mounted) {
        await next.dispose();
        return;
      }
      final old = player;
      old?.removeListener(_tick);
      player = next;
      next.addListener(_tick);
      await old?.dispose();
      await next.seekTo(Duration(milliseconds: c.start));
      setState(() {});
    } catch (e) {
      await next.dispose();
      _playerUri = null;
      if (mounted) setState(() => bootError = '回放暂不可用：$e');
    }
  }

  void _tick() {
    final c = controller;
    if (c == null || !mounted || c.busy || c.cameraActive || c.image != null) {
      return;
    }
    final t = player!.value.position.inMilliseconds;
    if (player!.value.isPlaying && t >= c.end) player!.pause();
    if ((t - c.time).abs() >= 30) setState(() => c.time = t);
  }

  Future<void> _seek(int t, {bool mark = false}) async {
    final c = controller!;
    await player?.pause();
    await c.frame(t.clamp(c.start, c.end));
    await player?.seekTo(Duration(milliseconds: c.time));
    if (mounted) setState(() => marking = mark);
  }

  Future<void> _edit(int? index) async {
    final c = controller!;
    final r = await editReviewRep(
      context,
      index == null
          ? ReviewRep(c.time, c.time + 500, c.time + 500, c.time + 1000)
          : c.reps[index],
    );
    if (r == null || !mounted) return;
    final reps = [...c.reps];
    if (index == null) {
      reps.add(r);
    } else {
      reps[index] = r;
    }
    reps.sort((a, b) => a.startMs.compareTo(b.startMs));
    if (!validReviewReps(reps, c.start, c.end)) {
      setState(() => c.error = '次数不能重叠或超出片段');
      return;
    }
    c.reps = reps;
    c.changed();
  }

  Future<void> _link() async {
    final c = controller!, sets = await controller!.repo.completedSets();
    if (!mounted) return;
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 450,
          child: ListView(
            children: [
              const ListTile(title: Text('关联已完成组（可选）')),
              ListTile(
                title: const Text('独立保存 · 不关联'),
                onTap: () => Navigator.pop(ctx, ''),
              ),
              for (final s in sets)
                ListTile(
                  title: Text(
                    '${s['name']} · ${s['weight']} kg × ${s['reps']}',
                  ),
                  onTap: () => Navigator.pop(ctx, s['id'] as String),
                ),
            ],
          ),
        ),
      ),
    );
    if (value == null || !mounted) return;
    c.setId = value.isEmpty ? null : value;
    linkedLabel = value.isEmpty ? null : '已选择训练组，保存时关联';
    c.changed();
  }

  Future<void> _delete() async {
    final c = controller!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分析项目？'),
        content: const Text('仅删除应用内副本。用户原视频与训练记录保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await c.repo.delete(c.id);
    c.dirty = false;
    _leaving = true;
    if (mounted) context.go('/analysis');
  }

  String seconds(int t) => (t / 1000).toStringAsFixed(2);
  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (c == null) {
      return Scaffold(body: Center(child: Text(bootError ?? '无法打开分析')));
    }
    final last = c.frames.where((f) => (f.t - c.time).abs() <= 100).lastOrNull;
    final state = switch (c.phase) {
      'loading' => '正在准备模型与输入…',
      'analyzing' => '分析中',
      'recording' => '拍摄中',
      'preview' => '实时预览',
      'cancelled' => '已取消 · 不完整',
      'failed' => '处理失败',
      'saved' => '已保存',
      'review' when c.status == 'completed' => '分析完成 · 请核对次数',
      'review' when c.status == 'stopped' => '已停止 · 请核对次数',
      _ => c.status == 'interrupted' ? '已中断 · 不完整' : '预览与复盘',
    };
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/analysis'),
        ),
        title: Text(c.mode == 'camera' ? '实时拍摄' : '视频分析'),
        actions: [
          if (c.result != null)
            TextButton(
              onPressed: c.busy || c.needsAnalysis
                  ? null
                  : () async {
                      await c.save();
                      if (mounted) setState(() {});
                    },
              child: Text(c.dirty ? '保存' : '已保存'),
            ),
          if (widget.projectId != null || c.result != null)
            IconButton(
              tooltip: '删除项目',
              onPressed: c.busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: !MotionBridge.supported
          ? const Center(child: Text('此设备尚不支持动作分析，请使用 Web 或 Android。'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${MotionCatalog.byId(c.motionId).name} · ${c.view.label}机位 · 本地分析',
                ),
                if (!motionSelected && c.result == null)
                  const Text('请确认动作，再开始分析；也可先导入视频。'),
                if (c.result == null && !c.busy && !c.cameraActive) ...[
                  DropdownButtonFormField<String>(
                    initialValue: c.motionId,
                    decoration: const InputDecoration(labelText: '选择动作'),
                    items: [
                      for (final p in MotionCatalog.profiles)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          c.motionId = v;
                          motionSelected = true;
                        });
                      }
                    },
                  ),
                  DropdownButtonFormField<MotionView>(
                    initialValue: c.view,
                    decoration: const InputDecoration(labelText: '拍摄机位'),
                    items: [
                      for (final v in MotionView.values)
                        DropdownMenuItem(value: v, child: Text(v.label)),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => c.view = v);
                    },
                  ),
                  Text(MotionCatalog.byId(c.motionId).viewAdvice[c.view] ?? ''),
                ],
                if (c.observations.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('项目片段', style: Theme.of(context).textTheme.titleMedium),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var i = 0; i < c.observations.length; i++)
                        ChoiceChip(
                          label: Text(
                            '${i + 1} · ${MotionView.values.firstWhere((v) => v.name == c.observations[i]['view'], orElse: () => MotionView.side).label}',
                          ),
                          selected: c.activeObservation == i,
                          onSelected: c.dirty || c.busy || c.cameraActive
                              ? null
                              : (_) => _selectObservation(i),
                        ),
                    ],
                  ),
                  if (!c.dirty && !c.busy && !c.cameraActive)
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => _additional('import'),
                          icon: const Icon(Icons.add),
                          label: const Text('加入视频'),
                        ),
                        TextButton.icon(
                          onPressed: () => _additional('camera'),
                          icon: const Icon(Icons.videocam_outlined),
                          label: const Text('加入拍摄'),
                        ),
                        if (c.observations.length > 1 &&
                            c.activeObservation >= 0)
                          TextButton.icon(
                            onPressed: _removeObservation,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('移除当前片段'),
                          ),
                      ],
                    ),
                  if (c.observations.length > 1)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('综合对照 · 各片段时间轴独立，无法证明重复一一对应。'),
                        for (final item in c.observations)
                          Text(
                            '${MotionView.values.firstWhere((v) => v.name == item['view'], orElse: () => MotionView.side).label}：${(item['reps'] as List? ?? []).length} 次候选；${item['status'] == 'completed' ? '已分析' : '不完整'}',
                          ),
                        if (c.observations
                                .map(
                                  (item) =>
                                      (item['reps'] as List? ?? []).length,
                                )
                                .toSet()
                                .length >
                            1)
                          const Text('各机位候选次数不同；保留各段原结果，不合并次数。'),
                      ],
                    ),
                ],
                if (linkedLabel != null) Text(linkedLabel!),
                const SizedBox(height: 12),
                if (bootError != null)
                  Text(
                    bootError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (c.error != null)
                  Text(
                    c.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (c.image != null ||
                    player != null ||
                    (c.textureId != null && (c.busy || c.cameraActive)))
                  _preview(c)
                else
                  Container(
                    height: 190,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.center_focus_strong, size: 44),
                        SizedBox(height: 12),
                        Text('让动作全程完整入镜'),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(state, style: Theme.of(context).textTheme.titleMedium),
                if (c.phase == 'analyzing')
                  LinearProgressIndicator(value: c.progress),
                Wrap(
                  spacing: 16,
                  children: [
                    Text(
                      last?.pose.any((p) => p[2] >= .7) == true
                          ? '人体：已识别'
                          : '人体：暂无有效骨架',
                    ),
                    if (c.motionId == MotionCatalog.bench)
                      Text(
                        last?.valid == true
                            ? '杠铃：跟踪中'
                            : c.anchors.isEmpty && !c.cameraActive
                            ? '杠铃：请点选中心'
                            : '杠铃：未标记或丢失，请重新标记',
                      ),
                  ],
                ),
                if (c.motionId == MotionCatalog.bench && c.frames.length >= 2)
                  Text(
                    c.frames.last.valid && c.frames[c.frames.length - 2].valid
                        ? (c.frames.last.y! >= c.frames[c.frames.length - 2].y!
                              ? '当前阶段：下降 ↓'
                              : '当前阶段：推起 ↑')
                        : '当前阶段：未知',
                  ),
                Text('${c.reps.length} 次实验性候选次数 · ${seconds(c.time)} 秒（请人工核对）'),
                Text(
                  '二维肘角：${last == null ? '未知' : reviewElbowAngle(last, c.width, c.height)?.toStringAsFixed(0) ?? '未知'}°',
                ),
                if (c.cameraActive)
                  Text(
                    '处理 ${c.fps.toStringAsFixed(1)} FPS · 延迟 ${c.latency.round()} ms · 过期输入 ${c.dropped}',
                  ),
                if (c.busy)
                  TextButton.icon(
                    onPressed: c.phase == 'recording'
                        ? () async {
                            await c.stopCamera();
                            await _player();
                          }
                        : c.cancel,
                    icon: Icon(
                      c.phase == 'recording' ? Icons.stop : Icons.close,
                    ),
                    label: Text(c.phase == 'recording' ? '停止拍摄' : '取消分析'),
                  ),
                if (!c.busy) ...[
                  if (c.mode == 'import')
                    FilledButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.video_library_outlined),
                      label: Text(c.folder == null ? '选择本地视频' : '替换视频'),
                    ),
                  if (c.mode == 'camera' && !c.cameraActive && c.folder == null)
                    FilledButton.icon(
                      onPressed:
                          motionSelected &&
                              MotionCatalog.byId(c.motionId)
                                      .capability(c.view) !=
                                  MotionCapability.unavailable
                          ? () => c.camera()
                          : null,
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('打开摄像头'),
                    ),
                  if (c.mode == 'camera' && !c.cameraActive && c.folder == null)
                    TextButton(
                      onPressed: () => context.go('/analysis/import'),
                      child: const Text('改用导入视频'),
                    ),
                  if (c.cameraActive) ...[
                    if (!c.canRecord) const Text('仅实时预览，无法保存视频复盘。'),
                    if (c.devices.length > 1)
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: '摄像头'),
                        items: [
                          for (final d in c.devices)
                            DropdownMenuItem(
                              value: d['id'] as String,
                              child: Text(d['label'] as String),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() => marking = false);
                          c.camera(deviceId: v);
                        },
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              mirror = !mirror;
                              c.mirrored = mirror;
                              marking = false;
                            });
                            c.camera();
                          },
                          child: Text(mirror ? '取消镜像并重置' : '镜像并重置'),
                        ),
                        if (c.motionId == MotionCatalog.bench)
                          OutlinedButton(
                            onPressed: () async {
                              await c.bridge.call('freezeCamera');
                              if (mounted) setState(() => marking = true);
                            },
                            child: const Text('标记杠铃'),
                          ),
                        FilledButton(
                          onPressed: motionSelected ? c.startCamera : null,
                          child: const Text('开始'),
                        ),
                      ],
                    ),
                  ],
                  if (c.folder != null && c.uri != null) ...[
                    Slider(
                      value: c.time.toDouble().clamp(0, c.duration.toDouble()),
                      max: c.duration.toDouble(),
                      onChanged: (v) => _seek(v.round()),
                    ),
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                          tooltip: '上一帧',
                          onPressed: () => _seek(
                            c.times.where((t) => t < c.time).lastOrNull ??
                                (c.time - 33),
                          ),
                          icon: const Icon(Icons.skip_previous),
                        ),
                        IconButton(
                          tooltip: '播放或暂停',
                          onPressed: () async {
                            await _player();
                            if (player == null) return;
                            setState(() {
                              c.image = null;
                              marking = false;
                            });
                            if (player!.value.isPlaying) {
                              await player!.pause();
                            } else {
                              if (c.time >= c.end) {
                                await player!.seekTo(
                                  Duration(milliseconds: c.start),
                                );
                              }
                              await player!.play();
                            }
                          },
                          icon: Icon(
                            player?.value.isPlaying == true
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                        ),
                        IconButton(
                          tooltip: '下一帧',
                          onPressed: () => _seek(
                            c.times.where((t) => t > c.time).firstOrNull ??
                                (c.time + 33),
                          ),
                          icon: const Icon(Icons.skip_next),
                        ),
                        for (final speed in [.25, .5, 1.0])
                          TextButton(
                            onPressed: () => player?.setPlaybackSpeed(speed),
                            child: Text('$speed×'),
                          ),
                      ],
                    ),
                    Text(
                      '分析片段：${seconds(c.start)}–${seconds(c.end)} 秒 · 最长 3 分钟',
                    ),
                    RangeSlider(
                      values: RangeValues(c.start.toDouble(), c.end.toDouble()),
                      max: c.duration.toDouble(),
                      onChanged: (v) {
                        if (v.end - v.start < 100 || v.end - v.start > 180000) {
                          return;
                        }
                        setState(() {
                          c.start = v.start.round();
                          c.end = v.end.round();
                          c.needsAnalysis = true;
                          c.changed();
                        });
                      },
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (c.motionId == MotionCatalog.bench)
                          OutlinedButton(
                            onPressed: () => _seek(c.start, mark: true),
                            child: const Text('标记片段首帧'),
                          ),
                        if (c.motionId == MotionCatalog.bench)
                          OutlinedButton(
                            onPressed: () => _seek(c.time, mark: true),
                            child: const Text('重新标记杠铃'),
                          ),
                        FilledButton(
                          onPressed:
                              motionSelected &&
                                  MotionCatalog.byId(c.motionId)
                                          .capability(c.view) !=
                                      MotionCapability.unavailable
                              ? () async {
                                  await player?.pause();
                                  await c.analyze();
                                }
                              : null,
                          child: Text(c.result == null ? '开始分析' : '重新分析'),
                        ),
                      ],
                    ),
                  ],
                ],
                if (marking && c.motionId == MotionCatalog.bench) ...[
                  const Text('点击画面中近侧杠铃片中心'),
                  Slider(
                    value: radius,
                    min: .02,
                    max: .3,
                    label: '跟踪区域',
                    onChanged: (v) => setState(() => radius = v),
                  ),
                ],
                if (c.phase == 'recording' && c.motionId == MotionCatalog.bench)
                  OutlinedButton(
                    onPressed: () async {
                      await c.bridge.call('freezeCamera');
                      if (mounted) setState(() => marking = true);
                    },
                    child: const Text('重新标记杠铃'),
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    FilterChip(
                      label: const Text('骨架'),
                      selected: skeleton,
                      onSelected: (v) {
                        setState(() => skeleton = v);
                        c.bridge.call('renderOptions', {
                          'skeleton': skeleton,
                          'trajectory': trajectory,
                        });
                      },
                    ),
                    FilterChip(
                      label: const Text('轨迹'),
                      selected: trajectory,
                      onSelected: (v) {
                        setState(() => trajectory = v);
                        c.bridge.call('renderOptions', {
                          'skeleton': skeleton,
                          'trajectory': trajectory,
                        });
                      },
                    ),
                  ],
                ),
                if (c.result != null && !c.busy) ...[
                  const Divider(),
                  Text('次数与节奏', style: Theme.of(context).textTheme.titleLarge),
                  Text(
                    c.motionId == MotionCatalog.bench
                        ? '二维投影 · 下降/暂停/推起；暂停不是触胸判定。次数可人工修正，训练记录不会自动更改。'
                        : '基于可见人体关键点的候选周期；器械位置未知。次数可人工修正，训练记录不会自动更改。',
                  ),
                  ..._reps(c),
                  TextButton(
                    onPressed: () => _edit(null),
                    child: const Text('手动添加一次'),
                  ),
                  TextButton(
                    onPressed: _link,
                    child: Text(c.setId == null ? '关联已完成组（可选）' : '修改或解除组关联'),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  '质量观察（${MotionCatalog.byId(c.motionId).candidateObservations.join('、')}）：不可评估，尚缺人工标注验证。识别效果仍需固定机位视频验证；不提供动作评分或绝对速度。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
    );
  }

  Widget _preview(MotionAnalysisController c) {
    final displayFrames = c.motionId == MotionCatalog.bench
        ? c.frames
        : poseDisplayPath(c.frames, c.motionId);
    final native = !kIsWeb && c.textureId != null && (c.busy || c.cameraActive);
    final overlay = ReviewOverlay(
      frames: List.of(displayFrames),
      reps: List.of(c.reps),
      time: c.time,
      trajectory: trajectory,
      skeleton: skeleton,
      compare: false,
      anchors: List.of(c.anchors),
    );
    final aspect = c.image != null || native
        ? c.width / c.height
        : player?.value.aspectRatio ?? 16 / 9;
    Widget content = AspectRatio(
      aspectRatio: aspect,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          onTapDown: marking
              ? (d) async {
                  final x = d.localPosition.dx / constraints.maxWidth;
                  await c.mark(
                    mirror ? 1 - x : x,
                    d.localPosition.dy / constraints.maxHeight,
                    radius,
                  );
                  if (mounted) setState(() => marking = false);
                }
              : null,
          child: Transform.flip(
            flipX: mirror,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (native)
                  Texture(textureId: c.textureId!)
                else if (c.image != null)
                  Image.memory(
                    c.image!,
                    gaplessPlayback: false,
                    fit: BoxFit.fill,
                    frameBuilder: (context, child, frame, synchronous) => Stack(
                      fit: StackFit.expand,
                      children: [
                        child,
                        if (frame != null || synchronous)
                          IgnorePointer(child: CustomPaint(painter: overlay)),
                      ],
                    ),
                  )
                else if (player != null)
                  VideoPlayer(player!),
                if (!native && c.image == null)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: ReviewOverlay(
                        frames: displayFrames,
                        reps: c.reps,
                        time: c.time,
                        trajectory: trajectory,
                        skeleton: skeleton,
                        compare: false,
                        anchors: c.anchors,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(color: Colors.black, child: content),
    );
  }

  List<Widget> _reps(MotionAnalysisController c) {
    final metrics = reviewMetrics(
      c.motionId == MotionCatalog.bench
          ? c.frames
          : poseMotionPath(c.frames, c.motionId),
      c.reps,
    );
    return [
      for (var i = 0; i < c.reps.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '第 ${i + 1} 次 · ${c.reps[i].downSeconds.toStringAsFixed(2)} / ${c.reps[i].pauseSeconds.toStringAsFixed(2)} / ${c.reps[i].upSeconds.toStringAsFixed(2)} 秒',
          ),
          subtitle: Text(
            metrics[i].valid
                ? '相对幅度 ${metrics[i].relativeAmplitude?.toStringAsFixed(0) ?? '未知'}%'
                : '轨迹缺口 · 指标未知',
          ),
          onTap: c.uri == null ? null : () => _seek(c.reps[i].startMs),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '修正边界',
                onPressed: () => _edit(i),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: '删除这次',
                onPressed: () {
                  c.reps.removeAt(i);
                  c.changed();
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
    ];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    analysisExitGuard = null;
    player?.removeListener(_tick);
    player?.dispose();
    controller?.removeListener(_changed);
    controller?.dispose();
    super.dispose();
  }
}
