import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/local_date.dart';

void main() {
  test('strict date parsing rejects malformed and overflowing dates', () {
    for (final value in <String?>[
      null,
      '',
      '2026-2-01',
      '2026-02-1',
      ' 2026-02-01',
      '2026-02-01 ',
      '2026-02-01\n',
      '2026-02-01T00:00:00',
      '2026-02-30',
      '2025-02-29',
      '1900-02-29',
      '2026-00-01',
      '2026-13-01',
      '2026-01-00',
      '2026-04-31',
      '10000-01-01',
    ]) {
      expect(LocalDate.tryParse(value), isNull, reason: '$value');
    }
    expect(LocalDate.tryParse('2024-02-29')!.key, '2024-02-29');
    expect(LocalDate.tryParse('2000-02-29')!.key, '2000-02-29');
  });

  test('local boundaries use consecutive calendar dates', () {
    final day = LocalDate.tryParse('2026-10-16')!;
    expect((day.year, day.month, day.day), (2026, 10, 16));
    expect(day.key, '2026-10-16');
    expect(day.start, DateTime(2026, 10, 16));
    expect(day.nextStart, DateTime(2026, 10, 17));
    expect(day.start.isUtc, isFalse);
    expect(day.nextStart.isUtc, isFalse);
    expect(LocalDate(2026, 12, 31).nextStart, DateTime(2027));
    expect(LocalDate(2024, 2, 29).nextStart, DateTime(2024, 3));
  });

  test(
    'constructor rejects invalid dates rather than normalizing overflow',
    () {
      expect(() => LocalDate(2026, 2, 30), throwsArgumentError);
      expect(() => LocalDate(2026, 13, 1), throwsArgumentError);
      expect(() => LocalDate(-1, 1, 1), throwsArgumentError);
      expect(() => LocalDate(10000, 1, 1), throwsArgumentError);
      expect(LocalDate(1, 1, 2).key, '0001-01-02');
    },
  );

  test('date values compare by calendar fields and support sets', () {
    final a = LocalDate(2026, 10, 16);
    final b = LocalDate.tryParse('2026-10-16')!;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect({a, b, LocalDate(2026, 10, 17)}, hasLength(2));
    expect(a.toString(), '2026-10-16');
    expect(LocalDate.fromDateTime(DateTime(2026, 10, 16, 23, 59)), a);
    final utc = DateTime.utc(2026, 10, 16, 23, 59);
    final local = utc.toLocal();
    expect(
      LocalDate.fromDateTime(utc),
      LocalDate(local.year, local.month, local.day),
    );
  });
}
