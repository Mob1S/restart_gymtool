import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/executor_access.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../data/repositories/session_repo.dart';
import '../../data/repositories/settings_repo.dart';
import '../../data/repositories/training_plan_repo.dart';
import '../../data/repositories/workout_plan_repo.dart';
import '../../domain/local_date.dart';
import '../../domain/plans.dart';
import '../../domain/session_label.dart';
import '../../domain/training_plans.dart';
import '../../domain/training_schedule.dart';
import '../../state/active_session_controller.dart';
import '../../state/data_revision.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/primary_button.dart';
import '../plans/plan_picker.dart';
import 'conflict_dialog.dart';
import 'training_calendar.dart';

const activeTrainingPlanKey = 'active_training_plan_id';

class WorkoutHomePage extends StatefulWidget {
  final DateTime Function()? now;
  const WorkoutHomePage({super.key, this.now});
  @override
  State<WorkoutHomePage> createState() => _WorkoutHomePageState();
}

class _WorkoutHomePageState extends State<WorkoutHomePage>
    with WidgetsBindingObserver {
  Timer? _midnight;
  LocalDate? _lastDate;
  DateTime get _now => widget.now?.call() ?? DateTime.now();
  bool get _homeVisible =>
      (GoRouter.maybeOf(context)?.state.uri.path ?? '/') == '/';
  PlannedWorkout? _planned;
  List<TrainingPlanDetail> _plans = [];
  Map<String, String> _exerciseNames = {};
  String? _selectedPlanId, _preferredDayId, _message;
  bool _freeTraining = false, _selectionLoaded = false, _starting = false;
  bool _planLoading = true;
  int? _revision;
  int _planGeneration = 0, _calendarGeneration = 0;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Set<String> _completed = {};
  final _topKey = GlobalKey(),
      _actionKey = GlobalKey(),
      _detailsKey = GlobalKey(),
      _cardKey = GlobalKey();
  Size? _topSize, _actionSize, _detailsSize, _cardSize;

  void _measureLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final top = _topKey.currentContext?.size;
      final action = _actionKey.currentContext?.size;
      final details = _detailsKey.currentContext?.size;
      final card = _cardKey.currentContext?.size;
      if (top != _topSize ||
          action != _actionSize ||
          details != _detailsSize ||
          card != _cardSize) {
        setState(() {
          _topSize = top;
          _actionSize = action;
          _detailsSize = details;
          _cardSize = card;
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastDate = LocalDate.fromDateTime(_now);
    _scheduleMidnight();
    WidgetsBinding.instance.addPostFrameCallback((_) => _probe());
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = _now;
    _midnight = Timer(
      LocalDate.fromDateTime(now).nextStart.difference(now),
      () {
        _refreshDate();
      },
    );
  }

  void _refreshDate({bool force = false}) {
    if (!mounted) return;
    final today = LocalDate.fromDateTime(_now);
    final changed = today != _lastDate;
    _lastDate = today;
    if (changed) _preferredDayId = null;
    if ((force || changed) && !_starting) {
      _loadPlan();
      _loadMonth();
    }
    _scheduleMidnight();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDate(force: true);
  }

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.watch<DataRevision?>()?.value ?? 0;
    if (_revision == revision) return;
    _revision = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // The start flow explicitly reloads after ending the old workout.
        // Do not supersede that awaited load with a revision refresh.
        if (!_starting) {
          _loadPlan();
        }
        _loadMonth();
      }
    });
  }

  Future<void> _probe() async {
    if (!mounted) return;
    await context.read<ActiveSessionController>().ensureResumed();
    if (mounted) await _loadPlan();
  }

  Future<void> _loadMonth() async {
    if (!mounted) return;
    final generation = ++_calendarGeneration;
    final month = _month;
    try {
      final dates = await listCompletedTrainingDates(
        context.read<SqlExecutor>(),
        LocalDate(month.year, month.month, 1),
      );
      if (mounted && generation == _calendarGeneration) {
        setState(() => _completed = dates);
      }
    } catch (_) {
      if (mounted && generation == _calendarGeneration) {
        setState(() => _message = '月历载入失败，请稍后重试');
      }
    }
  }

  Future<void> _loadPlan() async {
    if (!mounted || !_homeVisible) return;
    final generation = ++_planGeneration;
    setState(() => _planLoading = true);
    final exec = context.read<SqlExecutor>();
    try {
      final plans = await listTrainingPlans(exec);
      String? selected = _selectedPlanId;
      if (!_selectionLoaded) {
        selected = await getSetting(exec, activeTrainingPlanKey);
      }
      if (!mounted || generation != _planGeneration) return;
      _selectionLoaded = true;
      if (selected == null || !plans.any((plan) => plan.id == selected)) {
        selected = plans.firstOrNull?.id;
        _preferredDayId = null;
      }
      final day = _preferredDayId;
      if (day != null &&
          !plans.any(
            (p) =>
                p.id == selected &&
                p.days.any(
                  (d) => d.id == day && d.kind == TrainingDayKind.training,
                ),
          )) {
        _preferredDayId = null;
      }
      if (!_freeTraining && selected != null && _homeVisible) {
        await activateTrainingPlan(
          exec,
          selected,
          today: LocalDate.fromDateTime(_now),
        );
      }
      if (!mounted || generation != _planGeneration) return;
      final plan = await loadNextWorkout(
        exec,
        planId: _freeTraining ? null : selected,
        preferredDayId: _freeTraining ? null : _preferredDayId,
        freeTraining: _freeTraining || plans.isEmpty,
        now: _now,
      );
      final exercises = await listExercises(exec, includeArchived: true);
      if (!mounted || generation != _planGeneration) return;
      setState(() {
        _selectedPlanId = selected;
        _plans = plans;
        _planned = plan;
        _exerciseNames = {for (final e in exercises) e.id: e.name};
      });
      if (selected != null) {
        await setSetting(exec, activeTrainingPlanKey, selected);
      }
    } catch (_) {
      if (mounted && generation == _planGeneration) {
        setState(() {
          _planned = null;
          _message = '计划已变化，请重新选择';
        });
      }
    } finally {
      if (mounted && generation == _planGeneration) {
        setState(() => _planLoading = false);
      }
    }
  }

  Future<void> _pickPlan() async {
    final choice = await showPlanPicker(
      context,
      _plans,
      selectedId: _freeTraining ? null : _selectedPlanId,
    );
    if (!mounted || choice == null) return;
    _freeTraining = choice == freeTrainingChoice;
    if (!_freeTraining) _selectedPlanId = choice;
    _preferredDayId = null;
    await _loadPlan();
  }

  Future<void> _pickDay() async {
    final parent = _plans.where((p) => p.id == _selectedPlanId).firstOrNull;
    if (parent == null ||
        !parent.days.any((d) => d.kind == TrainingDayKind.training)) {
      return;
    }
    final choice = await showTrainingDayPicker(
      context,
      parent,
      selectedId: _planned?.templateId,
    );
    if (!mounted || choice == null) return;
    _preferredDayId = choice;
    _freeTraining = false;
    await _loadPlan();
  }

  Future<void> _chooseFreeTraining() async {
    _freeTraining = true;
    _preferredDayId = null;
    await _loadPlan();
  }

  Future<void> _manage() async {
    await context.push('/plans');
    if (mounted) await _loadPlan();
  }

  Future<void> _startNew() async {
    if (_starting || _planLoading || _planned == null) return;
    setState(() {
      _starting = true;
      _message = null;
    });
    try {
      final c = context.read<ActiveSessionController>();
      await c.ensureResumed();
      if (c.resumeError != null) {
        if (mounted) setState(() => _message = c.resumeError);
        return;
      }
      if (!mounted) return;
      if (c.session != null) {
        final choice = await showConflictDialog(
          context,
          description: _describe(c),
        );
        if (!mounted) return;
        switch (choice) {
          case ConflictChoice.resume:
            await _continue();
            return;
          case ConflictChoice.endAndStartNew:
            if (await c.endWorkout() == null) {
              if (mounted) {
                setState(() => _message = c.writeMessage ?? '无法结束上一场训练，请重试');
              }
              return;
            }
            await _loadPlan();
            break;
          case ConflictChoice.cancel:
          case null:
            return;
        }
      }
      if (!mounted || _planned == null) return;
      final result = await c.startNew(
        planId: _planned!.planId,
        preferredDayId: _planned!.templateId,
        freeTraining: _planned!.freeTraining,
        selectionToken: _planned!.selectionToken,
      );
      if (!mounted) return;
      if (result == StartResult.started) {
        _preferredDayId = null;
        await context.push('/session/${c.session!.id}');
        if (mounted) await _probe();
      } else if (result == StartResult.planChanged) {
        _preferredDayId = null;
        await _loadPlan();
        if (mounted) setState(() => _message = '计划已变化，请核对后重新开始');
      } else if (result == StartResult.refreshFailed) {
        setState(() => _message = '训练已开始，载入失败，请从继续训练入口重试');
      }
    } catch (_) {
      if (mounted) setState(() => _message = '无法开始训练，本次未创建新训练，请重试');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _continue() async {
    final session = context.read<ActiveSessionController>().session;
    if (session == null) return;
    await context.push('/session/${session.id}');
    if (mounted) await _probe();
  }

  String _describe(ActiveSessionController c) =>
      describeExercises(c.exercises.map((e) => e.progress).toList());

  Widget _calendar({required bool compact}) => TrainingCalendar(
    displayedMonth: _month,
    completedDates: _completed,
    compact: compact,
    onDateSelected: (date) => context.go('/history?date=${date.key}'),
    onMonthChanged: (month) {
      setState(() {
        _month = month;
        _completed = {};
      });
      _loadMonth();
    },
  );
  Widget _planCard() {
    final parent = _plans.where((p) => p.id == _planned?.planId).firstOrNull;
    final planned = _planned;
    final resting =
        planned?.schedule?.state == TrainingScheduleState.rest ||
        planned?.schedule?.state == TrainingScheduleState.completed;
    final nextTraining = planned?.schedule?.nextTrainingDay;
    return AppCard(
      key: const ValueKey('home-plan-card'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            parent?.name ?? '自由训练',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (parent != null)
            Text(
              '${parent.days.where((d) => d.kind == TrainingDayKind.training).length} 个训练日 · ${parent.days.where((d) => d.kind == TrainingDayKind.rest).length} 个休息日',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 6),
          Text(
            parent != null && parent.days.isEmpty
                ? '尚未配置训练日'
                : planned?.dayName ?? '按自己的节奏开始',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            parent != null && parent.days.isEmpty
                ? '进入管理计划配置周期，或切换到自由训练'
                : resting
                ? nextTraining == null
                      ? '按自然日休息，可随时自由训练'
                      : '下一次：${nextTraining.name}'
                : planned == null
                ? '正在载入…'
                : planned.exerciseIds.isEmpty
                ? '本次没有动作，可在训练中添加'
                : planned.exerciseIds
                      .map((id) => _exerciseNames[id] ?? '动作')
                      .join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: appColors(context).textSecondary),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: _starting ? null : _pickPlan,
                child: const Text('切换计划'),
              ),
              TextButton(
                onPressed:
                    _starting ||
                        parent == null ||
                        !parent.days.any(
                          (d) => d.kind == TrainingDayKind.training,
                        )
                    ? null
                    : _pickDay,
                child: const Text('选择训练日'),
              ),
              TextButton(
                onPressed: _starting ? null : _manage,
                child: const Text('管理计划'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _measureLayout();
    final c = context.watch<ActiveSessionController>();
    final hasActive = c.session != null;
    final canStart =
        _planned != null && (_planned!.freeTraining || _planned!.hasUsableDay);
    final scheduleState = _planned?.schedule?.state;
    final resting =
        scheduleState == TrainingScheduleState.rest ||
        scheduleState == TrainingScheduleState.completed;
    final button = !hasActive && resting
        ? ConstrainedBox(
            key: const ValueKey('home-primary-action'),
            constraints: const BoxConstraints(minHeight: 56),
            child: Center(
              child: Text(
                scheduleState == TrainingScheduleState.rest ? '今天休息' : '今日已完成',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          )
        : PrimaryButton(
            key: const ValueKey('home-primary-action'),
            label: hasActive ? '继续训练' : '开始训练',
            icon: Icons.play_arrow_rounded,
            onPressed: _starting || (!hasActive && (_planLoading || !canStart))
                ? null
                : hasActive
                ? _continue
                : _startNew,
          );
    final action = SizedBox(key: _actionKey, child: button);
    final details = Column(
      key: _detailsKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Text(
          hasActive
              ? _describe(c)
              : scheduleState == TrainingScheduleState.completed
              ? '明天休息'
              : _planned?.dayName ?? '今天也为自己留一点时间',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: appColors(context).textSecondary),
        ),
        if (hasActive)
          TextButton(
            onPressed: _starting || _planLoading || !canStart
                ? null
                : _startNew,
            child: const Text('开始新训练'),
          ),
        if (resting)
          TextButton(
            onPressed: _starting || _planLoading ? null : _chooseFreeTraining,
            child: const Text('自由训练'),
          ),
        if (_message != null) Text(_message!, textAlign: TextAlign.center),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final contentHeight = constraints.maxHeight - 24;
        final actionHalf = (_actionSize?.height ?? 56) / 2;
        // Measure the actual calendar, text and card. Long names, large text,
        // landscape and small displays use a reachable scrolling layout.
        final canCenter =
            _topSize != null &&
            _actionSize != null &&
            _cardSize != null &&
            _detailsSize != null &&
            _topSize!.height + 12 <= contentHeight / 2 - actionHalf &&
            _cardSize!.height + 12 <=
                contentHeight / 2 - actionHalf - _detailsSize!.height;
        final top = Column(
          key: _topKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [_calendar(compact: scale <= 1.15)],
        );
        final card = SizedBox(key: _cardKey, child: _planCard());
        return Padding(
          key: const ValueKey('training-content'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            12,
            AppSpacing.screenH,
            12,
          ),
          child: canCenter
              ? Stack(
                  children: [
                    Positioned(top: 0, left: 0, right: 0, child: top),
                    // Button itself is centered, independent of the text below it.
                    Positioned(
                      top: (constraints.maxHeight - 24) / 2 - actionHalf,
                      left: 0,
                      right: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [action, details],
                      ),
                    ),
                    Positioned(bottom: 0, left: 0, right: 0, child: card),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      top,
                      const SizedBox(height: 28),
                      action,
                      details,
                      const SizedBox(height: 28),
                      card,
                    ],
                  ),
                ),
        );
      },
    );
  }
}
