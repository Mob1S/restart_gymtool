import 'package:flutter/foundation.dart';

import '../data/db/sql_executor.dart';
import '../data/repositories/exercise_repo.dart';
import '../data/repositories/session_repo.dart';
import '../data/repositories/set_repo.dart';
import '../domain/rest.dart';
import '../domain/workout_edit.dart';
import '../data/repositories/workout_write_repo.dart';
import '../data/repositories/workout_edit_repo.dart';
import '../data/repositories/exercise_replacement_repo.dart';
import '../domain/session_label.dart';
import '../domain/types.dart';
import '../domain/set_detail.dart';
import '../domain/training_prescription.dart';
import '../domain/load_reference.dart';
import '../data/repositories/load_reference_repo.dart';
import '../data/repositories/set_detail_repo.dart';
import '../domain/weight_value.dart';
import '../domain/exercise_visibility.dart';
import '../domain/plans.dart';
import '../domain/record_management.dart';
import '../domain/backup_codec.dart';
import '../data/repositories/backup_repo.dart';
import '../data/repositories/workout_plan_repo.dart';
import '../data/repositories/training_program_repo.dart';
import '../data/repositories/record_management_repo.dart';

const double defaultWeightKg = 20;
const int defaultReps = 8;

/// [ActiveSessionController.startNew] 的两种结果。
///
/// `conflict` 表示库里已经有一场进行中的训练，此时**没有**新建任何东西，
/// 那一场已经装进 controller —— 界面据此问用户「接着练还是结束它」。
enum StartResult { started, conflict, busy, planChanged, refreshFailed }

enum RemoveExerciseChoice { deleteRecorded, keepRecorded, cancel }

class ExerciseRemovalPreview {
  final String sessionId;
  final String sessionExerciseId;
  final String exerciseName;
  final int completedSets;
  final int visibleCount;
  final String token;
  const ExerciseRemovalPreview._(
    this.sessionId,
    this.sessionExerciseId,
    this.exerciseName,
    this.completedSets,
    this.visibleCount,
    this.token,
  );
}

/// 记录界面上的一个动作卡片：动作本身 + 展示用的名字 + 它的全部组。
///
/// 名字在这里就查好了（而不是让界面自己去 `getExercise`），因为本来就
/// 要为「上次练了多少」查一次库，顺手带上不额外花钱。
class ActiveExercise {
  /// 这一场里的动作记录 —— **`sets` 里的组引用的是它的 id**
  final SessionExercise sessionExercise;

  /// 动作名；动作被删 / 查不到时是「未知动作」
  final String exerciseName;

  /// 该动作的全部组，含界面上那条未完成的占位组
  final List<SetEntry> sets;
  final SessionPrescription? prescription;

  const ActiveExercise({
    required this.sessionExercise,
    required this.exerciseName,
    required this.sets,
    this.prescription,
  });

  ActiveExercise copyWith({List<SetEntry>? sets}) => ActiveExercise(
    sessionExercise: sessionExercise,
    exerciseName: exerciseName,
    sets: sets ?? this.sets,
    prescription: prescription,
  );

  /// 给 `domain/session_label.dart` 用 —— 它只认动作名与每组的完成状态。
  ExerciseProgress get progress => ExerciseProgress(
    exerciseName: exerciseName,
    sets: sets.map((s) => SetProgress(isCompleted: s.isCompleted)).toList(),
  );
}

/// 当前训练的全部状态与操作。
///
/// Coordinates serialized writes and refreshes; repositories revalidate active
/// sessions and record ownership inside each transaction.
///
/// 状态**只存在内存里**，每个写操作都立刻落库，App 重启后靠 [resume]
/// 从库重建。刻意不做持久化：真相来源只留 SQLite 一份，
/// 两处都能改状态必然对不上。
class ActiveSessionController extends ChangeNotifier {
  final SqlExecutor _exec;
  final VoidCallback? onDataChanged;
  bool _starting = false;
  bool _removing = false;
  final int Function() _now;
  bool _writing = false;
  bool _needsReload = false;
  bool _disposed = false;
  int _generation = 0;
  int _resumeRequest = 0;
  bool _resumeInitialized = false;
  Future<bool>? _resuming;
  String? _resumeError;
  String? _writeMessage;
  final Map<String, EquipmentWeight> _stagedWeights = {};
  Future<WorkoutWriteResult>? _flushing;
  bool get writing => _writing || _starting || _removing || loading;
  String? get resumeError => _resumeError;
  String? get writeMessage => _writeMessage;
  bool get savingWeight => _flushing != null;
  bool get hasPendingWeight => _stagedWeights.isNotEmpty;
  double? stagedWeight(String id) => _stagedWeights[id]?.kilograms;
  EquipmentWeight? stagedReading(String id) => _stagedWeights[id];

  bool _sameReading(EquipmentWeight? a, EquipmentWeight b) =>
      a?.unit == b.unit && a?.amount.text == b.amount.text;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<WorkoutWriteResult> _write(
    Future<void> Function() action, {
    String? focusId,
  }) async {
    if (writing || _disposed) return WorkoutWriteResult.busy;
    if (_needsReload) return WorkoutWriteResult.savedNeedsReload;
    _writing = true;
    _writeMessage = null;
    final generation = _generation;
    final preferred = focusId ?? currentSessionExerciseId;
    final index = currentIndex;
    _notify();
    var committed = false;
    try {
      await action();
      committed = true;
      if (generation != _generation || _disposed) {
        return WorkoutWriteResult.saved;
      }
      onDataChanged?.call();
      if (session != null) {
        final loaded = await _loadExercises(session!.id);
        if (generation != _generation || _disposed) {
          return WorkoutWriteResult.saved;
        }
        exercises = loaded;
        currentIndex = resolveRecordingIndex(
          recordingExercises.map((e) => e.sessionExercise.id).toList(),
          focusId ?? preferred,
          index,
        );
      }
      return WorkoutWriteResult.saved;
    } on RecordManagementException catch (e) {
      _writeMessage = e.message;
      return WorkoutWriteResult.conflict;
    } catch (_) {
      _needsReload = committed;
      _writeMessage = committed ? '已保存，页面刷新失败，请重新载入' : '保存失败，请重试';
      return committed
          ? WorkoutWriteResult.savedNeedsReload
          : WorkoutWriteResult.failed;
    } finally {
      _writing = false;
      _notify();
    }
  }

  void stagePendingWeight(String pendingSetId, double weight) {
    if (!weight.isFinite || weight < 0) return;
    stagePendingReading(pendingSetId, EquipmentWeight.kg(weight));
  }

  void stagePendingReading(String pendingSetId, EquipmentWeight reading) {
    if (_disposed ||
        (writing && _flushing == null) ||
        !reading.kilograms.isFinite) {
      return;
    }
    if (!exercises.any(
      (e) => e.sets.any((s) => s.id == pendingSetId && !s.isCompleted),
    )) {
      return;
    }
    if (_sameReading(_stagedWeights[pendingSetId], reading)) return;
    final pending = exercises
        .expand((e) => e.sets)
        .firstWhere((s) => s.id == pendingSetId);
    if (_flushing == null && _sameReading(pending.equipmentWeight, reading)) {
      if (_stagedWeights.remove(pendingSetId) != null) _notify();
      return;
    }
    _stagedWeights[pendingSetId] = reading;
    _notify();
  }

  Future<WorkoutWriteResult> flushPendingWeight() {
    if (_flushing != null) return _flushing!;
    if (_stagedWeights.isEmpty) {
      return Future.value(WorkoutWriteResult.unchanged);
    }
    if (writing) return Future.value(WorkoutWriteResult.busy);
    final generation = _generation;
    final sid = session?.id;
    if (sid == null) return Future.value(WorkoutWriteResult.conflict);
    final future = _write(() async {
      while (_stagedWeights.isNotEmpty && generation == _generation) {
        final item = _stagedWeights.entries.first;
        await savePendingWeight(
          _exec,
          sessionId: sid,
          pendingSetId: item.key,
          weight: item.value.kilograms,
          reading: item.value,
        );
        if (generation != _generation) return;
        if (_sameReading(_stagedWeights[item.key], item.value)) {
          _stagedWeights.remove(item.key);
        }
      }
    });
    _flushing = future;
    return future.whenComplete(() => _flushing = null);
  }

  Future<bool> _flushReady() async {
    final result = await flushPendingWeight();
    return result == WorkoutWriteResult.saved ||
        result == WorkoutWriteResult.unchanged;
  }

  Future<CompletedSetEdit?> previewCompletedSet(String id) async {
    if (!await _flushReady() || writing || session == null) return null;
    return inspectCompletedSet(_exec, session!.id, id);
  }

  Future<UndoSetPreview?> previewUndo() async {
    if (!await _flushReady() ||
        writing ||
        session == null ||
        currentSessionExerciseId == null) {
      return null;
    }
    return inspectUndoSet(
      _exec,
      session!.id,
      currentSessionExerciseId!,
      now: _now(),
    );
  }

  Future<WorkoutWriteResult> editCompletedSet(
    CompletedSetEdit edit,
    double weight,
    int reps, {
    EquipmentWeight? reading,
    SetDetail? detail,
  }) async {
    if (session?.id != edit.sessionId || session?.finishedAt != null) {
      return WorkoutWriteResult.conflict;
    }
    if (!await _flushReady()) return WorkoutWriteResult.failed;
    return _write(
      () => updateCompletedSet(
        _exec,
        edit,
        weight: weight,
        reps: reps,
        reading: reading,
        detail: detail,
      ),
    );
  }

  Future<WorkoutWriteResult> undoLastCompletion(UndoSetPreview preview) async {
    if (session?.id != preview.sessionId || session?.finishedAt != null) {
      return WorkoutWriteResult.conflict;
    }
    if (!await _flushReady()) return WorkoutWriteResult.failed;
    return _write(() => undoCompletedSet(_exec, preview, now: _now()));
  }

  Future<ExerciseReplacementPreview?> previewReplacement(
    String targetId,
  ) async {
    if (!await _flushReady() ||
        writing ||
        session == null ||
        currentSessionExerciseId == null) {
      return null;
    }
    return inspectExerciseReplacement(
      _exec,
      session!.id,
      currentSessionExerciseId!,
      targetId,
    );
  }

  Future<WorkoutWriteResult> replaceExercise(
    ExerciseReplacementPreview preview,
  ) async {
    if (session?.id != preview.sessionId || session?.finishedAt != null) {
      return WorkoutWriteResult.conflict;
    }
    if (!await _flushReady()) return WorkoutWriteResult.failed;
    if (preview.sourceExerciseId == preview.targetExerciseId) {
      return WorkoutWriteResult.unchanged;
    }
    String? target;
    final result = await _write(() async {
      target = await replaceWorkoutExercise(_exec, preview);
    });
    if (result == WorkoutWriteResult.saved && target != null) {
      currentIndex = resolveRecordingIndex(
        recordingExercises.map((e) => e.sessionExercise.id).toList(),
        target,
        0,
      );
      _notify();
    }
    return result;
  }

  /// Invalidates page drafts before replacing the database.
  Future<void> prepareForRestore() async {
    final result = await flushPendingWeight();
    if (result != WorkoutWriteResult.saved &&
        result != WorkoutWriteResult.unchanged) {
      throw StateError('重量尚未保存，请返回训练重试');
    }
    if (writing) throw StateError('训练正在保存，请稍后重试');
    _generation++;
    _invalidateResume();
    _stagedWeights.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _invalidateResume();
    _stagedWeights.clear();
    super.dispose();
  }

  ActiveSessionController(this._exec, {this.onDataChanged, int Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// 正在从库里载入（[resume] 期间为 true），界面据此显示加载态
  bool loading = false;
  WorkoutSession? session;
  List<ActiveExercise> exercises = [];
  int currentIndex = 0;
  List<ActiveExercise> get recordingExercises =>
      exercises.where((e) => isRecordingExercise(e.sets)).toList();
  ActiveExercise? get currentExercise {
    final visible = recordingExercises;
    return currentIndex >= 0 && currentIndex < visible.length
        ? visible[currentIndex]
        : null;
  }

  String? get currentSessionExerciseId => currentExercise?.sessionExercise.id;

  /// Read once for navigation; returning to the recorder keeps its current focus.
  /// Explicit [resume] remains available after a database change.
  Future<bool> ensureResumed() async {
    try {
      final pending = _resuming;
      if (pending != null) return await pending;
      if (_resumeInitialized && !_needsReload) return session != null;
      return await resume();
    } catch (_) {
      // A failed read keeps any loaded workout; the bar offers a retry.
      return session != null;
    }
  }

  /// 载入未结束的训练；没有就返回 false。并发调用共享同一次读取。
  Future<bool> resume() => _restore();

  Future<bool> _restore({bool allowStarting = false}) {
    if (_disposed) return Future.value(false);
    if (_resuming != null) return _resuming!;
    if (_writing || _removing || (_starting && !allowStarting)) {
      return Future.value(session != null);
    }
    final request = ++_resumeRequest;
    final generation = _generation;
    loading = true;
    _resumeError = null;
    _notify();
    final future = _readResume(request, generation);
    _resuming = future;
    return future;
  }

  bool _currentResume(int request, int generation) =>
      !_disposed && request == _resumeRequest && generation == _generation;

  Future<bool> _readResume(int request, int generation) async {
    try {
      final found = await getActiveSession(_exec);
      if (!_currentResume(request, generation)) return session != null;
      if (found == null) {
        session = null;
        exercises = [];
        currentIndex = 0;
        _resumeInitialized = true;
        return false;
      }
      final loaded = await _loadExercises(found.id, generation: generation);
      if (!_currentResume(request, generation)) return session != null;
      final index = await _resolveCurrentIndex(
        found.id,
        loaded.where((e) => isRecordingExercise(e.sets)).toList(),
      );
      if (!_currentResume(request, generation)) return session != null;
      session = found;
      _needsReload = false;
      _writeMessage = null;
      exercises = loaded;
      currentIndex = index;
      _resumeInitialized = true;
      return true;
    } catch (_) {
      if (_currentResume(request, generation)) {
        _resumeInitialized = false;
        _resumeError = '训练读取失败，已保存的数据仍在，请重试';
      }
      rethrow;
    } finally {
      if (_currentResume(request, generation)) {
        loading = false;
        _resuming = null;
        _notify();
      }
    }
  }

  void _invalidateResume() {
    _resumeRequest++;
    _resuming = null;
    _resumeInitialized = false;
    _resumeError = null;
    loading = false;
  }

  /// 开一场新训练。
  ///
  /// 库里已经有一场进行中的训练时**不新建**，返回 [StartResult.conflict]
  /// 并把那一场装进 controller 交回界面。这是「同时只可能有一场进行中的训练」
  /// 这条不变量**唯一的守门人**。
  ///
  /// Phase 1 的动作来源是「复制上一次**已结束**训练的动作组合」；
  /// 分化计划的轮转留到后续 Phase，但**调用顺序现在就遵守**（见下）。
  Future<StartResult> startNew({
    String? name,
    String? planId,
    String? preferredDayId,
    bool freeTraining = false,
    String? preferredTemplateId,
    String? selectionToken,
  }) async {
    // Bootstrap may have published the navigation while its first read is still
    // running. Queue a start behind that read rather than dropping the request.
    final restoring = _resuming;
    if (restoring != null && !_starting && !_writing && !_removing) {
      try {
        final found = await restoring;
        if (_disposed) return StartResult.busy;
        if (found && session != null) return StartResult.conflict;
      } catch (_) {
        // The recovery error remains visible; a failed read must not create a
        // new session when we cannot know whether an older one already exists.
        return StartResult.busy;
      }
    }
    if (writing || _disposed) return StartResult.busy;
    _starting = true;
    try {
      // 复用 resume 而不是另写一次查询：它会把那一场连动作带组一起装进
      // controller，界面选「接着练」时直接导航过去就有东西可渲染 ——
      // 只返回一个 id 的话，记录页会因为 controller 里没有 exercises
      // 而误判成「这次训练还没有动作」。
      if (await _restore(allowStarting: true)) return StartResult.conflict;

      // 顺序不能反：**先探冲突（上面那行）→ 再定计划 → 才建 session**。
      // 轮转的输入是「最近一场已结束训练用的模板」，先建出来的话这一场虽然
      // finished_at 还是 NULL、不会污染那个查询，但「先建后定」很容易在后续
      // 改动里被误用 listSessions 之类的接口把这一场算进去。
      WorkoutSession? created;
      try {
        created = await _exec.transaction((tx) async {
          if (await getActiveSession(tx) != null) return null;
          final plan = await readPlannedWorkout(
            tx,
            planId: planId,
            preferredDayId: preferredDayId,
            freeTraining: freeTraining,
            preferredTemplateId: preferredTemplateId,
            now: DateTime.fromMillisecondsSinceEpoch(_now()),
          );
          if (plan.planId != null && !plan.hasUsableDay) {
            throw const PlanValidationException('当前没有可开始的训练日，请重新选择');
          }
          if (selectionToken != null && selectionToken != plan.selectionToken) {
            throw const PlanValidationException('计划已变化');
          }
          final s = await createSession(
            tx,
            name: name ?? plan.name,
            templateId: plan.templateId,
            planId: plan.planId,
            planNameSnapshot: plan.planName,
            dayNameSnapshot: plan.dayName,
            origin: 'live',
          );
          for (final exerciseId in plan.exerciseIds) {
            await addExerciseWithFirstSet(tx, s.id, exerciseId);
          }
          if (plan.planId != null && plan.templateId != null) {
            await snapshotWorkoutProgram(
              tx,
              plan.planId!,
              plan.templateId!,
              s.id,
            );
          }
          encodeBackup(await readBackupSnapshot(tx, exportedAt: _now()));
          return s;
        });
      } on PlanValidationException {
        return StartResult.planChanged;
      }
      if (created == null) {
        await _restore(allowStarting: true);
        return StartResult.conflict;
      }

      session = created;
      try {
        exercises = await _loadExercises(created.id);
      } catch (_) {
        exercises = [];
        currentIndex = 0;
        _needsReload = true;
        _resumeInitialized = false;
        _resumeError = '训练已开始，读取失败，请重试';
        _notify();
        return StartResult.refreshFailed;
      }
      currentIndex = 0;
      _notify();
      return StartResult.started;
    } finally {
      _starting = false;
      _notify();
    }
  }

  /// 往训练里加一个动作。
  Future<void> addExercise(String exerciseId) async {
    await addExercises([exerciseId]);
  }

  Future<WorkoutWriteResult> addExercises(List<String> exerciseIds) async {
    if (writing) return WorkoutWriteResult.busy;
    if (exerciseIds.isEmpty) return WorkoutWriteResult.unchanged;
    if (!await _flushReady()) return WorkoutWriteResult.failed;
    final current = session;
    if (current == null || current.finishedAt != null) {
      return WorkoutWriteResult.conflict;
    }
    List<String> ids = [];
    final result = await _write(() async {
      ids = await addWorkoutExercises(_exec, current.id, exerciseIds);
    });
    if (result == WorkoutWriteResult.saved && ids.isNotEmpty) {
      currentIndex = resolveRecordingIndex(
        recordingExercises.map((e) => e.sessionExercise.id).toList(),
        ids.first,
        0,
      );
      _notify();
    }
    return result;
  }

  /// 切换当前正在记录的动作。**不写数据库** —— 它是纯界面状态。
  Future<void> setCurrentIndex(int index) async {
    if (writing && !savingWeight) return;
    if ((_stagedWeights.isNotEmpty || savingWeight) && !await _flushReady()) {
      return;
    }
    if (index < 0 || index >= recordingExercises.length) return;
    currentIndex = index;
    _notify();
  }

  /// 记完当前这一组：写数值 → 标完成 → 起休息计时 → 预建下一组，四步都落盘。
  ///
  /// 以下情况**静默返回**（都不报错）：训练已结束、currentIndex 越界、
  /// 该动作已无未完成的组（重复点击）。
  Future<void> completeCurrentSet(double weight, int reps) async {
    if (!weight.isFinite || weight < 0) return;
    await completeCurrentReading(EquipmentWeight.kg(weight), reps);
  }

  Future<WorkoutWriteResult> completeCurrentReading(
    EquipmentWeight reading,
    int reps, {
    Effort? effort,
  }) async {
    if (writing && !savingWeight) return WorkoutWriteResult.busy;
    if (!await _flushReady() || writing) return WorkoutWriteResult.failed;
    final current = session;
    final pending = currentExercise?.sets
        .where((s) => !s.isCompleted)
        .firstOrNull;
    if (current == null || current.finishedAt != null || pending == null) {
      return WorkoutWriteResult.conflict;
    }
    return _write(
      () => completeWorkoutSet(
        _exec,
        sessionId: current.id,
        pendingSetId: pending.id,
        weight: reading.kilograms,
        reading: reading,
        reps: reps,
        now: _now(),
        effort: effort,
      ),
    );
  }

  /// 结束休息、进入下一组：写入这段休息的秒数并清掉 `restStartedAt`。
  Future<WorkoutWriteResult> adoptReference(
    String pendingId,
    LoadReference reference,
  ) async {
    if (!await _flushReady()) return WorkoutWriteResult.failed;
    return _write(
      () => applyLoadReference(
        _exec,
        pendingSetId: pendingId,
        expectedToken: reference.token,
        now: _now(),
      ),
    );
  }

  Future<WorkoutWriteResult> beginNextSegment(String pendingId) async {
    if (!await _flushReady() || session == null) {
      return WorkoutWriteResult.failed;
    }
    return _write(
      () => beginWorkoutSegment(
        _exec,
        sessionId: session!.id,
        setId: pendingId,
        now: _now(),
      ),
    );
  }

  Future<WorkoutWriteResult> finishPartialGroup(String pendingId) async {
    if (!await _flushReady() || session == null) {
      return WorkoutWriteResult.failed;
    }
    return _write(
      () => endPartialSet(
        _exec,
        sessionId: session!.id,
        setId: pendingId,
        now: _now(),
      ),
    );
  }

  /// 结束休息、进入下一组：写入这段休息的秒数并清掉 `restStartedAt`。
  ///
  /// 当前没有在休息时只是刷新一下列表，不写库。
  Future<void> beginNextSet() async {
    if (!await _flushReady() || writing) return;
    final current = session;
    final pending = currentExercise?.sets
        .where((s) => !s.isCompleted)
        .firstOrNull;
    if (current == null || current.finishedAt != null || pending == null) {
      return;
    }
    await _write(
      () => beginWorkoutSet(
        _exec,
        sessionId: current.id,
        pendingSetId: pending.id,
        now: _now(),
      ),
    );
  }

  /// Atomically finish, discard unconfirmed final rest, and clear active memory.
  /// The summary reads the finished session directly from the database.
  Future<String?> endWorkout() async {
    if (!await _flushReady() || writing) return null;
    final current = session;
    if (current == null) return null;
    final result = await _write(() async {
      await finishActiveWorkout(_exec, sessionId: current.id, now: _now());
      session = null;
      exercises = [];
      currentIndex = 0;
    });
    return result == WorkoutWriteResult.saved ||
            result == WorkoutWriteResult.savedNeedsReload
        ? current.id
        : null;
  }

  /// 清空内存里的训练状态。**不碰数据库、不结束训练** ——
  /// 调用方要负责先 [finishSession]（[endWorkout] 已经这么做了）。
  void reset() {
    _generation++;
    _invalidateResume();
    _stagedWeights.clear();
    _needsReload = false;
    _writeMessage = null;
    session = null;
    exercises = [];
    currentIndex = 0;
    _notify();
  }

  // ── 以下为私有实现 ──────────────────────────────────────────────

  /// 把一场训练的动作与组全部读出来。
  ///
  /// 这里还兼任一道闸门：**收拾掉跑过头的休息**。做完一组后如果一直没按
  /// 「开始下一组」（直接关掉 App 走了、或者第二天才打开），`rest_started_at`
  /// 会一直留着。不处理的话有两个后果 —— 重开 App 会被堵在休息页出不来，
  /// 以及这段荒唐的时长会作为 `rest_seconds` 存进库，把休息建议的平均值
  /// 彻底带偏。
  ///
  /// 放在这里而不是各个入口分别处理，是因为 resume / startNew / addExercise /
  /// endWorkout 全都会经过它，**一处覆盖全部**。
  Future<List<ActiveExercise>> _loadExercises(
    String sessionId, {
    int? generation,
  }) async {
    final sessionExercises = await listSessionExercises(_exec, sessionId);
    final now = _now();
    final result = <ActiveExercise>[];

    for (final se in sessionExercises) {
      final exercise = await getExercise(_exec, se.exerciseId);
      var sets = await listSets(_exec, se.id);

      if (_disposed || (generation != null && generation != _generation)) {
        return result;
      }

      final stale = findStaleRest(sets, now);
      if (stale != null) {
        await cancelRest(_exec, stale.id);
        sets = await listSets(_exec, se.id);
      }

      result.add(
        ActiveExercise(
          sessionExercise: se,
          exerciseName: exercise?.name ?? '未知动作',
          sets: sets,
          prescription: await readSessionPrescription(_exec, se.id),
        ),
      );
    }
    return result;
  }

  /// 算出「上次停在第几个动作」，用来恢复记录界面的位置。
  ///
  /// 训练里没有「当前动作」这个字段，但推得出来：`completed_at` 最大的那一组
  /// 就是用户最后碰过的组。**纯查询，不加字段、不做迁移。**
  ///
  /// 正在休息的情况自动落在同一个答案上（`startRest` 就是对刚 `completeSet`
  /// 的同一组调用的），不需要第二条判定。
  ///
  /// 已知不精确、明确接受：切到第 4 个动作但一组都没做就被杀 →
  /// 会回到第 3 个动作。
  ///
  /// `索引夹到 0` 兜住 findIndex 返回 -1 的情况：直接拿去当 currentIndex
  /// 会让记录页取到 `exercises[-1]`，一片空白。
  Future<int> _resolveCurrentIndex(
    String sessionId,
    List<ActiveExercise> loaded,
  ) async {
    final lastActiveId = await findLastActiveSessionExerciseId(
      _exec,
      sessionId,
    );
    if (lastActiveId == null) return 0;
    final index = loaded.indexWhere(
      (e) => e.sessionExercise.id == lastActiveId,
    );
    return index < 0 ? 0 : index;
  }

  /// Flush prepared weight before taking the removal confirmation snapshot.
  Future<ExerciseRemovalPreview?> previewExerciseRemoval(String id) async {
    if (!await _flushReady() || writing) return null;
    final current = session;
    if (current == null || current.finishedAt != null) return null;
    return _exec.transaction((tx) => _removalPreview(tx, current.id, id));
  }

  Future<ExerciseRemovalPreview?> _removalPreview(
    SqlExecutor tx,
    String sessionId,
    String id,
  ) async {
    final parent = await readSessionDeletion(tx, sessionId);
    if (parent == null || parent.session.finishedAt != null) return null;
    final children = await listSessionExercises(tx, sessionId);
    var visible = 0;
    ActiveExercise? target;
    for (final e in children) {
      final sets = await listSets(tx, e.id);
      if (isRecordingExercise(sets)) visible++;
      if (e.id == id) {
        target = ActiveExercise(
          sessionExercise: e,
          exerciseName: (await getExercise(tx, e.exerciseId))?.name ?? '动作',
          sets: sets,
        );
      }
    }
    if (target == null || !isRecordingExercise(target.sets)) return null;
    return ExerciseRemovalPreview._(
      sessionId,
      id,
      target.exerciseName,
      target.sets.where((s) => s.hasRecordedWork).length,
      visible,
      parent.token,
    );
  }

  Future<bool> removeExercise(
    ExerciseRemovalPreview preview,
    RemoveExerciseChoice choice,
  ) async {
    if (choice == RemoveExerciseChoice.cancel || writing) return false;
    if (!await _flushReady() || writing) return false;
    if (session?.id != preview.sessionId || session?.finishedAt != null) {
      return false;
    }
    _removing = true;
    final preferred = currentSessionExerciseId;
    final index = currentIndex;
    try {
      await _exec.transaction((tx) async {
        final current = await _removalPreview(
          tx,
          preview.sessionId,
          preview.sessionExerciseId,
        );
        if (current == null || current.token != preview.token) {
          throw const RecordManagementException('训练已变化，请重新确认移除');
        }
        if (current.visibleCount <= 1) {
          throw const RecordManagementException('请至少保留一个可继续动作');
        }
        if (choice == RemoveExerciseChoice.keepRecorded &&
            current.completedSets > 0) {
          await retainCompletedSets(tx, preview.sessionExerciseId);
        } else {
          await deleteSessionExercise(tx, preview.sessionExerciseId);
        }
      });
      onDataChanged?.call();
      try {
        exercises = await _loadExercises(preview.sessionId);
      } catch (_) {
        throw const RecordManagementException('动作已移除，请重新打开训练以刷新');
      }
      currentIndex = resolveRecordingIndex(
        recordingExercises.map((e) => e.sessionExercise.id).toList(),
        preferred,
        index,
      );
      _notify();
      return true;
    } finally {
      _removing = false;
    }
  }

  void detachTemplate(String templateId) {
    final s = session;
    if (s == null || s.templateId != templateId) return;
    session = WorkoutSession(
      id: s.id,
      name: s.name,
      startedAt: s.startedAt,
      finishedAt: s.finishedAt,
      note: s.note,
      planId: s.planId,
      planNameSnapshot: s.planNameSnapshot,
      dayNameSnapshot: s.dayNameSnapshot,
      origin: s.origin,
    );
    _notify();
  }

  void detachPlan(String planId) {
    final s = session;
    if (s == null || s.planId != planId) return;
    session = WorkoutSession(
      id: s.id,
      name: s.name,
      startedAt: s.startedAt,
      finishedAt: s.finishedAt,
      note: s.note,
      planNameSnapshot: s.planNameSnapshot,
      dayNameSnapshot: s.dayNameSnapshot,
      origin: s.origin,
    );
    _notify();
  }
}
