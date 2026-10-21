import 'beverage.dart';
import 'beverage_energy.dart';
import 'local_date.dart';

class DrinkTotal {
  final List<DrinkRecord> records;
  DrinkTotal(Iterable<DrinkRecord> records)
    : records = List.unmodifiable(records);
  BeverageEnergy get calories => records.fold(
    BeverageEnergy.zero,
    (n, r) => n + (r.calories ?? BeverageEnergy.zero),
  );
  int get unknown => records.where((r) => r.calories == null).length;
  bool get estimated => records.any(
    (r) => r.snapshot.source == BeverageSource.estimate && r.calories != null,
  );
  String get display => records.isEmpty
      ? '尚未记录'
      : unknown == records.length
      ? '热量待补'
      : '${calories.display} kcal';
  String get note =>
      [if (estimated) '含估算', if (unknown > 0) '$unknown 条待补热量，未计入'].join(' · ');
}

Map<LocalDate, DrinkTotal> beverageTrend(
  Iterable<DrinkRecord> records,
  LocalDate end,
  int days,
) {
  if (days != 7 && days != 30) throw ArgumentError('只支持近 7 / 30 天');
  final grouped = <String, List<DrinkRecord>>{};
  for (final r in records) {
    (grouped[r.date.key] ??= []).add(r);
  }
  return {
    for (var i = days - 1; i >= 0; i--)
      LocalDate.fromDateTime(
        DateTime(end.year, end.month, end.day - i),
      ): DrinkTotal(
        grouped[LocalDate.fromDateTime(
              DateTime(end.year, end.month, end.day - i),
            ).key] ??
            [],
      ),
  };
}

/// Includes the snapshot configuration/energy in the key so distinct versions
/// and edited recipes cannot silently merge into one ranked drink.
List<DrinkTotal> beverageContributions(Iterable<DrinkRecord> records) {
  final groups = <String, List<DrinkRecord>>{};
  for (final r in records) {
    final s = r.snapshot;
    final key = [
      s.id,
      s.name,
      s.description,
      s.energyLabel,
      s.source.name,
    ].join('\u0000');
    (groups[key] ??= []).add(r);
  }
  return groups.values.map(DrinkTotal.new).toList()
    ..sort((a, b) => b.calories.compareTo(a.calories));
}
