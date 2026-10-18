# Built-in Plans and Personal Load Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Deliver an upgradeable global exercise catalog, three editable programs, staged prescriptions, optional effort recording, recoverable rest-pause sets and history-based load references.

**Architecture:** Preserve existing workout and training-day identities. Add versioned, validated extension records for programs, workout prescription snapshots and actual set details; ordinary workouts retain their existing write path. Pure domain modules own prescriptions, catalog matching and suggestions; repositories own transactions and backup integration.

**Tech Stack:** Flutter/Dart, Provider, existing SQLite executors on Android/Web/FFI, existing decimal equipment readings; no new package dependency.

## Global Constraints

- Approved specification: `docs/superpowers/specs/2026-10-18-built-in-plans-and-load-guidance-design.md`.
- Stay on `main`; preserve `.tmp/` and `.superpowers/`; no force push.
- Append atomic schema 8 and export backup v6; retain restore v1–v5.
- Dot-source `scripts/env.ps1` before Flutter/Dart/Gradle. Serialize Flutter commands to avoid SQLite native-library locks.
- Default RPE, optional RIR, unknown remains unknown. Plan requirements never become actual feedback.
- References require a click; equipment kg/lb and configured decimal step remain authoritative.
- Rest days use existing natural-date progression; stages require user selection and do not reset the cycle.
- Existing history e1RM formula and 1–10 repetition range remain unchanged.
- Execution continues inline as previously selected by the user. The two referenced execution skills are not installed; follow the task/test/review gates directly without claiming their invocation.

## File and interface map

- `lib/domain/training_prescription.dart`: `Effort`, `SetTarget`, `ProgramStage`, `TrainingProgram`, strict versioned JSON codecs.
- `lib/domain/set_detail.dart`: `SetDetail`, `RecordedSegment`, actual effort and recoverable segment state; first segment stays in `set_entry`.
- `lib/domain/exercise_catalog.dart`: stable `CatalogExercise` entries, aliases, load meaning and `matchesExerciseQuery`.
- `lib/domain/load_reference.dart`: `LoadObservation`, `LoadReference`, pure `suggestLoad` with explicit evidence and unavailable reasons.
- `lib/data/db/training_v8_migration.dart`: extension tables with ownership and cascading deletion.
- `lib/data/repositories/exercise_catalog_repo.dart`: `syncExerciseCatalog` / transaction-scoped `readCatalogBindings`.
- `lib/data/repositories/training_program_repo.dart`: `readTrainingProgram`, `saveTrainingProgram`, `selectProgramStage`, immutable workout snapshots.
- `lib/data/repositories/set_detail_repo.dart`: actual-detail codecs and `recordWorkoutSegment` / `endPartialSet` transaction operations.
- `lib/data/repositories/load_reference_repo.dart`: query finished, completed personal facts; translate gear preferences and snapshot targets into domain input.
- `lib/data/builtin_programs.dart`: all three source-attributed datasets, day cycles and explicit KaiTan editorial conventions.
- `lib/features/plans/builtin_plan_page.dart`, `program_editor.dart`: preview/import, phase selection and per-occurrence editable targets.
- `lib/features/workout/effort_input.dart`, `prescription_panel.dart`: compact optional controls outside existing drag regions.
- Existing backup, workout writes/controller, history/CSV and statistics gain narrow integrations instead of parallel sources of truth.

## Task 1 — Typed prescription and actual-detail domain

- [x] Add strict immutable codecs. Reject unknown keys, invalid ranges, repeated stage IDs and invalid segment structures. Keep `RM`, REP and effort independent.
- [x] Add `test/domain/training_prescription_test.dart` and `set_detail_test.dart` with round trips and malformed input:

```dart
test('rest pause is two segments, not fifteen continuous reps', () {
  final target = SetTarget(repsMin: 10, repsMax: 10, extraReps: [5], pauseSeconds: 5);
  expect(target.segmentReps, [10, 5]);
  expect(SetTarget.fromJson(target.toJson()).pauseSeconds, 5);
});
```

- [x] Run `. ./scripts/env.ps1; flutter test test/domain/training_prescription_test.dart test/domain/set_detail_test.dart` before and after implementation. Require passing validation cases, not just snapshot equality.

## Task 2 — Schema, backup and global catalog

- [x] Append schema 8 with `exercise_catalog_binding`, `training_program`, `session_prescription`, `set_detail`; expose a single validated JSON payload per typed extension, not unvalidated opaque data.
- [x] Export/validate/restore corresponding v6 rows, ownership references, nested record count and byte limits. Normalize earlier backups through a separate `upgradeBackupToV6` while preserving independently callable v4/v5 normalizers.
- [x] Add stable catalog mappings for the existing 52 entries and 19 additions. New startup sync runs after existing empty-library initialization; same transaction rechecks identities, capacities and completion marker.
- [x] Add regression assertions:

```dart
expect(await catalogCount(db), 71);
await syncExerciseCatalog(db);
expect(await catalogCount(db), 71);
expect((await getExercise(db, archivedId))!.isArchived, isTrue);
expect(matchesExerciseQuery(frontSquat, '颈前深蹲'), isTrue);
```

- [x] Test `test/data/catalog_repo_test.dart`, `backup_v6_test.dart`, migration rollback and prior backup suites. Verify catalog changes do not rename or overwrite an existing exercise.
- [x] Commit the independently tested data foundation.

## Task 3 — Program datasets, stages and snapshots

- [x] Implement `TrainingProgram` stage targets keyed by stable template-exercise occurrence ID. Reconcile saves with existing occurrence reuse queues; pruning removes only deleted occurrences, not repetitions of the same exercise.
- [x] Build StrongLifts 14-day A/B cycle, PHUL 7-day cycle with optional upper-range sets, KaiTan 11 user-controlled stages and documented editorial corrections. Resolve catalog IDs without changing history.
- [x] In the existing atomic live-session creation, copy each occurrence's selected-stage target list to `session_prescription`; initialize target REP and role without applying estimated weight or actual effort.
- [x] Add tests:

```dart
final before = await readWorkoutTargets(db, sessionExerciseId);
await selectProgramStage(db, planId, nextStageId);
expect(await readWorkoutTargets(db, sessionExerciseId), before);
expect((await getTrainingPlan(db, planId))!.activatedOn, originalActivation);
```

- [x] Run new `test/data/training_program_repo_test.dart` and existing multiday/rest-day suites; commit program persistence/data.

## Task 4 — Effort and recoverable rest-pause writes

- [x] Extend `SetEntry` reads with optional actual details. Completing an ordinary group remains the existing typed transaction with optional effort.
- [x] First part completion stores actual values and completion time immediately; subsequent parts go in validated continuation records, with a distinct intra-set rest timestamp. Final part starts ordinary rest and creates one next logical-group placeholder.
- [x] Support ending a partial group, finishing the session and reloading the app during intra-set rest. Completed data survives each transaction failure or restart.
- [x] Test first-part durability, 5-second recovery, no double-save and early finish:

```dart
await recordWorkoutSegment(db, sessionId: sid, setId: pendingId, reading: kg(30), reps: 10, now: 1000);
expect((await listSets(db, seid)).single.isCompleted, isFalse);
expect((await readSetDetail(db, pendingId)).firstCompletedAt, 1000);
await endPartialSet(db, sessionId: sid, setId: pendingId, now: 2000);
expect((await listSets(db, seid)).first.reps, 10);
```

- [x] Run `test/data/set_detail_repo_test.dart`, current controller edit/removal tests and ordinary workout-write regressions; commit writes/controller integration.

## Task 5 — Personal reference engine

- [x] Query at most 8 comparable finished sessions in 90 days. Exclude future/placeholder/warmup/invalid or incompatible load data. Use actual effort only where present; separate calibrated and uncalibrated cohorts.
- [x] Implement direct matched-target reference, supported 1–10 RM conversion via unchanged historical formula, median of recent 3, direction from 3 vs 3 with 3% threshold, optional one-step bounded increase after two supported successes, 28-day staleness and decimal step alignment.
- [x] For high repetitions and rest-pause patterns, use directly comparable personal performances; return an explicit reason when conversion is unsupported. Never treat pauses as continuous repetitions.
- [x] Test deterministic evidence and limits:

```dart
expect(suggestLoad(noHistory).reading, isNull);
expect(suggestLoad(singleSpike).reading!.amount.asDouble, lessThan(spikeWeight));
expect(suggestLoad(assistedExercise).reading, isNull);
expect(suggestLoad(poundsWithFiveLbStep).reading!.amount.asDouble % 5, 0);
```

- [x] Run `test/domain/load_reference_test.dart`, `test/data/load_reference_repo_test.dart`; preserve existing metrics fixtures and commit.

## Task 6 — Plan and workout interfaces

- [x] Add source-attributed built-in preview/import from existing plan management; no duplicate homepage entry. Show matching/archived choices, stages and editable per-occurrence target lists using existing theme and compact Material controls.
- [x] Add optional RPE/RIR picker with explanatory text, current target/segment display, intra-set countdown, partial-finish control and reference explanation/adopt action. Existing vertical weight/horizontal REP gestures retain all locks.
- [x] Revalidate pending segment, preferences, history revision and target snapshot before adoption. A reference never changes REP, actual effort or completion.
- [x] Add widget scenarios for catalog alias search, per-occurrence edit, stage switching, import, RPE null/picker, reference manual adoption and narrow-screen overflow; run affected widget suites and commit.

## Task 7 — History, statistics and CSV

- [x] History editing preserves targets and displays actual segment readings/effort. Include extension payloads in stale edit/delete tokens; cascade deletion stays scoped to the logical group.
- [x] Volume flattens completed segments, count stays logical groups and e1RM excludes rest-pause groups. Normal historical metrics remain bit-for-bit unchanged.
- [x] Add optional CSV columns for effort/role/group/segment/pause; old CSV remains ordinary groups. New CSV round trips source units and segments without combining reps into a false RM.
- [x] Test history edits, stats and export/reimport with `10+5`, differing segment weights and incomplete groups. Run old history/CSV/progress suites and commit.

## Task 8 — Final validation and delivery

- [x] Run `. ./scripts/env.ps1; flutter test` and then `flutter analyze`, serialize commands and resolve all regressions.
- [x] Run existing mutation checks where affected. Build `flutter build web --no-pub --no-wasm-dry-run`; run browser smoke against the built app with isolated browser data and desktop/mobile widths.
- [x] Build release Android APK using existing offline Gradle command if Flutter's online wrapper stalls; record real build result and hash. Do not claim native acceptance without executing it.
- [x] Update `CHANGELOG.md`, `README.md`, this checklist and an execution record with actual commands/results, then commit exact project changes.
- [ ] `git diff --check`; verify working tree contains only pre-existing user untracked files. Normal push to `origin main`; verify remote HEAD equals local. No force push.
