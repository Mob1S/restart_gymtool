import 'package:flutter_test/flutter_test.dart';

import 'dart:io';

import 'package:gym_tracker/domain/types.dart';
import 'package:gym_tracker/domain/metrics.dart';
import 'package:gym_tracker/domain/import_records.dart';
import 'package:gym_tracker/domain/csv_records.dart';
import 'package:gym_tracker/domain/workout_csv.dart';

void main() {
  test(
    'source fixtures use existing metrics without rounding stored values',
    () {
      for (final (name, expected) in [
        ('strong', 160.0),
        ('hevy', 1600.0),
        ('xunji', 160.0),
      ]) {
        final parsed = parseWorkoutCsv(
          File('test/fixtures/import/$name.csv').readAsStringSync(),
        );
        expect(parsed.skipped, isEmpty);
        final sets = parsed.workouts
            .expand((w) => w.exercises)
            .expand((e) => e.sets)
            .toList();
        expect(
          totalVolumeLoad([
            for (final s in sets)
              SetLike(weight: s.weight, reps: s.reps, isCompleted: true),
          ]),
          expected,
        );
        if (name == 'hevy') {
          expect(
            estimateOneRepMax(sets.first.weight, sets.first.reps)!.round(),
            62,
          );
        }
      }
    },
  );
  test('strict dates, AM PM, offsets, quote errors and record limit', () {
    for (final bad in [
      '2024-02-31',
      '15/1/2024',
      '1/1/24',
      '2024-01-01 25:00',
      '1/1/2024 13:00 PM',
      '2024-02-31T00:00:00Z',
    ]) {
      expect(
        () => parseImportDate(bad),
        throwsA(isA<ImportValidationException>()),
        reason: bad,
      );
    }
    expect(
      parseImportDate('2024-01-01T10:00:00+08:00'),
      DateTime.utc(2024, 1, 1, 2).millisecondsSinceEpoch,
    );
    expect(
      DateTime.fromMillisecondsSinceEpoch(parseImportDate('1/1/2024 12:00 AM'))
          .hour,
      0,
    );
    expect(
      () => scanCsv(List.filled(100001, 'x').join('\n')),
      throwsA(isA<ImportValidationException>()),
    );
    expect(
      () => parseWorkoutCsv('Date,Date,Exercise Name,Weight,Reps\n'),
      throwsA(isA<ImportValidationException>()),
    );
  });
  test('CSV quoted newlines retain physical rows and escaped quotes', () {
    final rows = scanCsv('a,b\r\n"line1\nline2","a""b"\r\nnext,9');
    expect(rows.map((r) => r.line), [1, 2, 4]);
    expect(rows[1].fields, ['line1\nline2', 'a"b']);
    expect(
      () => scanCsv('a\n"open'),
      throwsA(isA<ImportValidationException>()),
    );
    expect(
      () => scanCsv('"closed"x'),
      throwsA(isA<ImportValidationException>()),
    );
  });
  test(
    'Strong groups by exact time, reports errors and preserves equal sets',
    () {
      final parsed = parseWorkoutCsv(
        'Date,Workout Name,Exercise Name,Weight,Reps\n'
        '2024-01-01 10:00,Push,Bench,135 lb,8\n'
        '2024-01-01 10:00,Push,Bench,135 lb,8\n'
        '2024-01-01 18:00,Push,Bench,20,8\n'
        '2024-02-31,Push,Bench,20,8\n'
        '2024-01-02,Push,Bench,20,1.5',
      );
      expect(parsed.workouts, hasLength(2));
      expect(parsed.workouts.first.exercises.single.sets, hasLength(2));
      expect(
        parsed.workouts.first.exercises.single.sets.first.weight,
        closeTo(61.23496995, 1e-9),
      );
      expect(parsed.poundsConverted, 2);
      expect(parsed.skipped.map((e) => e.line), [5, 6]);
      expect(parsed.unknownDurationCount, 2);
      expect(parsed.workouts.first.note, contains('时长未知'));
    },
  );
  test('Hevy explicit end, conflicting units and conflicting group ends', () {
    final p = parseWorkoutCsv(
      'start_time,end_time,title,exercise_title,weight_kg,reps\n'
      '2024-01-01 10:00,2024-01-01 11:00,Push,Bench,50,8\n'
      '2024-01-02 10:00,,Push,Bench,50 lb,8',
    );
    expect(p.workouts.single.finishedAt - p.workouts.single.startedAt, 3600000);
    expect(p.skipped.single.line, 3);
    final conflict = parseWorkoutCsv(
      'start_time,end_time,exercise_title,weight_kg,reps\n'
      '2024-01-01 10:00,2024-01-01 11:00,Bench,50,8\n'
      '2024-01-01 10:00,2024-01-01 12:00,Bench,50,8',
    );
    expect(conflict.workouts, isEmpty);
    expect(conflict.skipped.map((e) => e.line), [2, 3]);
  });
  test('Xunji fullwidth headers, strict dates and BW', () {
    final p = parseWorkoutCsv('日期,动作名称,重量（kg）,次数\r2024/1/2,深蹲,BW,8次');
    expect(p.source, CsvSource.xunji);
    expect(
      DateTime.fromMillisecondsSinceEpoch(p.workouts.single.startedAt).hour,
      12,
    );
    expect(p.workouts.single.exercises.single.sets.single.weight, 0);
  });
  test('domain rejects invalid batches and canonical names match', () {
    expect(normalizeExerciseName(' ＢＥＮＣＨ Press '), 'benchpress');
    for (final weight in [-1.0, double.nan, double.infinity]) {
      expect(
        () => validateImportedWorkouts([
          ImportedWorkout(
            sourceRow: 1,
            startedAt: 1,
            finishedAt: 2,
            exercises: [
              ImportedExercise(
                name: 'x',
                sets: [ImportedSet(weight: weight, reps: 8)],
              ),
            ],
          ),
        ]),
        throwsA(isA<ImportValidationException>()),
      );
    }
    expect(
      () => validateImportedWorkouts([]),
      throwsA(isA<ImportValidationException>()),
    );
  });
}
