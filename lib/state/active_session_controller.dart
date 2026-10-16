import 'package:flutter/foundation.dart';

import '../data/db/sql_executor.dart';
import '../data/repositories/exercise_repo.dart';
import '../data/repositories/session_repo.dart';
import '../data/repositories/set_repo.dart';
import '../domain/rest.dart';
import '../domain/session_label.dart';
import '../domain/types.dart';
import '../domain/exercise_visibility.dart';
import '../domain/plans.dart';
import '../domain/record_management.dart';
import '../data/repositories/workout_plan_repo.dart';
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

  const ActiveExercise({
    required this.sessionExercise,
    required this.exerciseName,
    required this.sets,
  });

  ActiveExercise copyWith({List<SetEntry>? sets}) => ActiveExercise(
    sessionExercise: sessionExercise,
    exerciseName: exerciseName,
    sets: sets ?? this.sets,
  );

  /// 给 `domain/session_label.dart` 用 —— 它只认动作名与每组的完成状态。
  ExerciseProgress get progress => ExerciseProgress(
    exerciseName: exerciseName,
    sets: sets.map((s) => SetProgress(isCompleted: s.isCompleted)).toList(),
  );
}

/// 当前训练的全部状态与操作。
///
/// 这一层是**唯一**允许判定「能不能改这场训练」的地方（每个写操作都先查
/// `finishedAt != null`）—— 界面只管调，不用自己判断训练是否已结束。
///
/// 状态**只存在内存里**，每个写操作都立刻落库，App 重启后靠 [resume]
/// 从库重建。刻意不做持久化：真相来源只留 SQLite 一份，
/// 两处都能改状态必然对不上。
class ActiveSessionController extends ChangeNotifier {
  final SqlExecutor _exec;
  final VoidCallback? onDataChanged;
  bool _starting = false;
  bool _removing = false;

  ActiveSessionController(this._exec, {this.onDataChanged});

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

  /// 载入未结束的训练；没有就返回 false。
  Future<bool> resume() async {
    loading = true;
    notifyListeners();
    try {
      final found = await getActiveSession(_exec);
      if (found == null) {
        session = null;
        exercises = [];
        currentIndex = 0;
        return false;
      }
      final loaded = await _loadExercises(found.id);
      session = found;
      exercises = loaded;
      currentIndex = await _resolveCurrentIndex(found.id, recordingExercises);
      return true;
    } finally {
      loading = false;
      notifyListeners();
    }
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
    String? preferredTemplateId,
    String? selectionToken,
  }) async {
    if (_starting) return StartResult.busy;
    _starting = true;
    try {
      // 复用 resume 而不是另写一次查询：它会把那一场连动作带组一起装进
      // controller，界面选「接着练」时直接导航过去就有东西可渲染 ——
      // 只返回一个 id 的话，记录页会因为 controller 里没有 exercises
      // 而误判成「这次训练还没有动作」。
      if (await resume()) return StartResult.conflict;

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
            preferredTemplateId: preferredTemplateId,
          );
          if (selectionToken != null && selectionToken != plan.selectionToken) {
            throw const PlanValidationException('计划已变化');
          }
          final s = await createSession(
            tx,
            name: name ?? plan.name,
            templateId: plan.templateId,
          );
          for (final exerciseId in plan.exerciseIds) {
            await _addExerciseWithFirstSet(tx, s.id, exerciseId);
          }
          return s;
        });
      } on PlanValidationException {
        return StartResult.planChanged;
      }
      if (created == null) {
        await resume();
        return StartResult.conflict;
      }

      session = created;
      try {
        exercises = await _loadExercises(created.id);
      } catch (_) {
        exercises = [];
        currentIndex = 0;
        notifyListeners();
        return StartResult.refreshFailed;
      }
      currentIndex = 0;
      notifyListeners();
      return StartResult.started;
    } finally {
      _starting = false;
    }
  }

  /// 往训练里加一个动作。
  Future<void> addExercise(String exerciseId) async {
    final current = session;
    // 已结束的训练不能再往里加东西。正常路径下 endWorkout 已经清空 controller、
    // session 为 null，这里挡的是「有人把一场已结束的训练塞回 controller」——
    // 旧项目那个「同一场训练被接上第二次、第三次」的 bug 就是这么来的。
    if (current == null || current.finishedAt != null) return;

    await _addExerciseWithFirstSet(_exec, current.id, exerciseId);

    exercises = await _loadExercises(current.id);
    currentIndex = recordingExercises.length - 1;
    notifyListeners();
  }

  /// 切换当前正在记录的动作。**不写数据库** —— 它是纯界面状态。
  void setCurrentIndex(int index) {
    if (index < 0 || index >= recordingExercises.length) return;
    currentIndex = index;
    notifyListeners();
  }

  /// 记完当前这一组：写数值 → 标完成 → 起休息计时 → 预建下一组，四步都落盘。
  ///
  /// 以下情况**静默返回**（都不报错）：训练已结束、currentIndex 越界、
  /// 该动作已无未完成的组（重复点击）。
  Future<void> completeCurrentSet(double weight, int reps) async {
    final current = session;
    if (current == null || current.finishedAt != null) return;
    final active = currentExercise;
    if (active == null) return;
    final pending = _firstOrNull(active.sets.where((s) => !s.isCompleted));
    if (pending == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // 开始新的一段休息之前，先把**会话里**还在进行的那一段结掉。
    // 理由见 [_findAnyResting] —— 这是「同时至多一段休息在进行」这条
    // 不变量在编排层的守门人，不能只靠界面。
    final previousRest = _findAnyResting();
    if (previousRest != null) {
      await endRest(_exec, previousRest.id, now);
    }

    // 顺序不能反：先把用户填的数值写进去，再标记完成。
    // 反过来一旦中途失败，就会留下「已完成但数值是旧的」的记录 ——
    // 而全局约束要求每完成一组立刻落盘，用户看到的就是最终记录。
    await updateSetValues(_exec, pending.id, weight, reps);
    await completeSet(_exec, pending.id, now);
    await startRest(_exec, pending.id, now);

    // 预先建好下一组，这样休息结束后立刻有东西可填
    await addSet(_exec, active.sessionExercise.id, weight, reps);

    final updated = await listSets(_exec, active.sessionExercise.id);
    exercises = List.of(exercises)
      ..[exercises.indexWhere(
        (e) => e.sessionExercise.id == active.sessionExercise.id,
      )] = active.copyWith(
        sets: updated,
      );
    notifyListeners();
  }

  /// 结束休息、进入下一组：写入这段休息的秒数并清掉 `restStartedAt`。
  ///
  /// 当前没有在休息时只是刷新一下列表，不写库。
  Future<void> beginNextSet() async {
    final current = session;
    if (current == null || current.finishedAt != null) return;
    final active = currentExercise;
    if (active == null) return;

    // **会话级**查找，不是只看当前动作 —— 见 [_findAnyResting]。
    // 「开始下一组」的意思是「休息结束了」，与哪一段无关。
    final resting = _findAnyResting();
    if (resting != null) {
      await endRest(_exec, resting.id, DateTime.now().millisecondsSinceEpoch);
    }

    final updated = await listSets(_exec, active.sessionExercise.id);
    exercises = List.of(exercises)
      ..[exercises.indexWhere(
        (e) => e.sessionExercise.id == active.sessionExercise.id,
      )] = active.copyWith(
        sets: updated,
      );
    notifyListeners();
  }

  /// 找出**整场训练里**正在进行的那一段休息（不属于某个动作，跨全部动作找）。
  ///
  /// ## 为什么必须是会话级的
  ///
  /// 「同时至多一段休息在进行」是一条真实的不变量：`rest_seconds` 存在
  /// **本组做完之后**那段休息上，而结算它的入口（[beginNextSet] /
  /// [completeCurrentSet] / [endWorkout]）只会结束找到的那一段 ——
  /// 若同时有两段在跑，另一段的 `rest_seconds` **永远是 NULL**，
  /// 总结页的平均休息就少了一个数据点，而且**不报错**。
  ///
  /// ## 为什么不能只靠界面
  ///
  /// 记录页的动作条渲染在 body **之外**（换动作不必退出记录界面，这是刻意的），
  /// 而 body 只在**当前动作**在休息时才显示休息界面。于是这条路是通的：
  ///
  /// 1. 深蹲完成一组 → 深蹲进入休息，body 显示休息界面
  /// 2. **动作条还在** → 用户点「卧推」的 chip，body 切回卧推的记录态
  /// 3. 点「✓ 完成这组」→ 卧推也开始休息 → **两段休息同时在跑**
  ///
  /// 所以这条不变量由编排层把守，而不是靠界面碰巧不显示按钮。
  ///
  /// 返回 null 表示当前没有在休息。
  SetEntry? _findAnyResting() {
    for (final item in exercises) {
      final found = _firstOrNull(
        item.sets.where((s) => s.isCompleted && s.restStartedAt != null),
      );
      if (found != null) return found;
    }
    return null;
  }

  /// 结束并**立刻清空** controller。
  ///
  /// 收尾：如果正处在休息中，先把这段休息结掉，否则这一组的 `rest_seconds`
  /// 永远是 NULL，总结页算不出平均休息。
  ///
  /// **按会话找，不是只看当前动作** —— 用户可能在别的动作上还挂着一段休息
  /// （见 [_findAnyResting]），只看当前动作会漏掉它。
  ///
  /// 结束之后立刻清内存，而不是等用户在总结页点「完成」——
  /// 「已经结束但还是当前训练」这个中间态正是旧项目「主页一直显示继续上次训练」
  /// 的直接原因：用户从总结页按系统返回键离开时永远走不到清空那一步，
  /// 而主页只看 controller 里有没有 session。
  ///
  /// **总结页不受影响**：它按路由参数 id 从库里读，不依赖 controller。
  ///
  /// 返回被结束的那场的 id；controller 里本来就没有训练时返回 null。
  Future<String?> endWorkout() async {
    final current = session;
    if (current == null) return null;

    // **丢掉**这段休息，不是把它结掉（`cancelRest` 而不是 `endRest`）。
    //
    // `completeCurrentSet` 给**每一组**都开了休息，所以刚做完最后一组时必然
    // 有一段在进行 —— 它的时长是「做完最后一组到按下结束」的间隔，而这个
    // 间隔**不可知**：用户可能在收杠铃，也可能已经揣兜里了。写成测量值就是
    // 伪造：实测 `[300, 300, 3]` 会让屏幕上出现「平均歇了 3 分 21 秒」，
    // 而用户真歇了 5 分 00 秒；还会把 200 秒那组从 `addWeight` 压成 `positive`。
    //
    // 这条与 [cancelRest] 的既有用途（休息跑太久，显然是忘了按开始下一组）
    // 是同一条道理：**不是真实休息的时长，不该作为数据留下来**。
    // 也与旧设计文档 §503「没有真实的组间休息数据，编一个平均值比留空更糟」
    // 和 `rest_advice` 里「最后一组通常是 null」对齐。
    //
    // 用户若真的歇够了，会先按「开始下一组」——那一按把这段休息**结掉**
    // （`beginNextSet` 走 `endRest`），值由用户确认过，那时 `endWorkout`
    // 已经找不到进行中的休息，这一行不会碰它。
    final resting = _findAnyResting();
    if (resting != null) {
      await cancelRest(_exec, resting.id);
    }

    final finishedId = current.id;
    await finishSession(
      _exec,
      finishedId,
      DateTime.now().millisecondsSinceEpoch,
    );

    reset();
    onDataChanged?.call();
    return finishedId;
  }

  /// 清空内存里的训练状态。**不碰数据库、不结束训练** ——
  /// 调用方要负责先 [finishSession]（[endWorkout] 已经这么做了）。
  void reset() {
    session = null;
    exercises = [];
    currentIndex = 0;
    notifyListeners();
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
  Future<List<ActiveExercise>> _loadExercises(String sessionId) async {
    final sessionExercises = await listSessionExercises(_exec, sessionId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <ActiveExercise>[];

    for (final se in sessionExercises) {
      final exercise = await getExercise(_exec, se.exerciseId);
      var sets = await listSets(_exec, se.id);

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

  /// 「上一次练了哪些动作」—— 没有计划时唯一的动作来源。
  ///
  /// [listSessions] 只返回**已结束**的训练，所以这里天然不会把一场还在
  /// 进行中的训练当成「上一次」。没有历史（第一次用）时返回空数组。

  /// 往训练里加一个动作，并预建它的第一组。
  ///
  /// **预建第一组不是可选项。** 记录界面靠「还没完成的那一组」来确定当前该记
  /// 哪一组，没有这条待完成的记录，[completeCurrentSet] 会直接 return，
  /// **用户点「完成这组」会毫无反应 —— 一个静默的假死按钮。**
  ///
  /// 重量 / 次数沿用上一次练这个动作的第一组，没有历史时用默认值兜底。
  ///
  /// 抽成私有函数是为了让 [startNew] 和 [addExercise] 共用同一条路径。
  /// 两处各写一遍必然漂移，而漂移的后果正是上面那个「按钮没反应」。
  Future<void> _addExerciseWithFirstSet(
    SqlExecutor exec,
    String sessionId,
    String exerciseId,
  ) async {
    final se = await addExerciseToSession(exec, sessionId, exerciseId);
    final last = await getLastPerformance(exec, exerciseId, sessionId);
    final template = last.isEmpty ? null : last.first;
    await addSet(
      exec,
      se.id,
      template?.weight ?? defaultWeightKg,
      template?.reps ?? defaultReps,
    );
  }

  Future<ExerciseRemovalPreview?> previewExerciseRemoval(String id) async {
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
      target.sets.where((s) => s.isCompleted).length,
      visible,
      parent.token,
    );
  }

  Future<bool> removeExercise(
    ExerciseRemovalPreview preview,
    RemoveExerciseChoice choice,
  ) async {
    if (choice == RemoveExerciseChoice.cancel || _removing) return false;
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
      notifyListeners();
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
    );
    notifyListeners();
  }
}

/// `Iterable.firstOrNull` —— 取第一个元素，没有元素时返回 null。
///
/// Dart 的 `Iterable` **没有内置它**（那是 `package:collection` 的扩展）。
/// 本工程里 `collection` 只是传递依赖，直接 import 会触发
/// `depend_on_referenced_packages`；而这里只有三处要用，
/// 因此自己写一个私有的，不为此新增一条依赖。
T? _firstOrNull<T>(Iterable<T> items) {
  for (final item in items) {
    return item;
  }
  return null;
}
