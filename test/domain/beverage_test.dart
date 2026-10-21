import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/beverage.dart';
import 'package:gym_tracker/domain/beverage_energy.dart';
import 'package:gym_tracker/domain/beverage_label_parser.dart';
import 'package:gym_tracker/domain/beverage_trends.dart';
import 'package:gym_tracker/domain/local_date.dart';

Beverage beverage({
  String id = 'cola',
  String? energy = '42',
  String? volume = '330',
  EnergyUnit energyUnit = EnergyUnit.kcal,
  EnergyBasis basis = EnergyBasis.per100ml,
  BeverageSource source = BeverageSource.label,
}) => Beverage(
  id: id,
  name: '可乐',
  volumeMl: volume,
  energyValue: energy,
  energyUnit: energyUnit,
  basis: basis,
  source: source,
  createdAt: 1,
  updatedAt: 1,
);
DrinkRecord drink({
  Beverage? b,
  String id = 'r',
  String amount = '330',
  DrinkUnit unit = DrinkUnit.ml,
  int day = 20,
}) {
  final time = DateTime(2026, 10, day, 23, 59);
  return DrinkRecord(
    id: id,
    beverageId: (b ?? beverage()).id,
    snapshot: b ?? beverage(),
    occurredAt: time.millisecondsSinceEpoch,
    date: LocalDate.fromDateTime(time),
    amount: amount,
    unit: unit,
  );
}

void main() {
  test('kcal per100ml supports ml half/multiple servings', () {
    final b = beverage();
    expect(b.calculate('330', DrinkUnit.ml)!.display, '138.6');
    expect(b.calculate('0.5', DrinkUnit.serving)!.display, '69.3');
    expect(b.calculate('2', DrinkUnit.serving)!.display, '277.2');
  });
  test('kJ conversion and per-serving volume conversion are exact', () {
    final b = beverage(
      energy: '418.4',
      energyUnit: EnergyUnit.kj,
      basis: EnergyBasis.perServing,
      volume: '500',
    );
    expect(b.calculate('1', DrinkUnit.serving)!.exact, '100/1');
    expect(b.calculate('250', DrinkUnit.ml)!.display, '50');
    expect(
      beverage(
        energy: '180',
        energyUnit: EnergyUnit.kj,
      ).calculate('330', DrinkUnit.ml)!.display,
      '142',
    );
  });
  test('sum before rounding; tiny positive differs from exact zero', () {
    final tiny = BeverageEnergy.parse('0.04');
    expect(tiny.display, '<0.1');
    expect((tiny + tiny + tiny).display, '0.1');
    expect(BeverageEnergy.zero.display, '0');
    expect(BeverageEnergy.parse('1.25').display, '1.3');
  });
  test('unknown, explicit zero, unrecorded and estimates remain distinct', () {
    expect(DrinkTotal([]).display, '尚未记录');
    expect(DrinkTotal([drink(b: beverage(energy: null))]).display, '热量待补');
    expect(DrinkTotal([drink(b: beverage(energy: '0'))]).display, '0 kcal');
    final mixed = DrinkTotal([
      drink(b: beverage(source: BeverageSource.estimate)),
      drink(b: beverage(energy: null), id: 'unknown'),
    ]);
    expect(mixed.display, '138.6 kcal');
    expect(mixed.unknown, 1);
    expect(mixed.estimated, isTrue);
  });
  test('no conversion without corresponding serving volume', () {
    final b = beverage(
      volume: null,
      basis: EnergyBasis.perServing,
      energy: '120',
    );
    expect(b.calculate('0.5', DrinkUnit.serving)!.display, '60');
    expect(() => b.calculate('100', DrinkUnit.ml), throwsFormatException);
    expect(
      () => beverage(volume: null).calculate('1', DrinkUnit.serving),
      throwsFormatException,
    );
  });
  for (final invalid in ['-1', 'NaN', 'Infinity', '1e3', '', '1/2', '0x10']) {
    test('rejects $invalid', () {
      expect(() => beverage(energy: invalid), throwsFormatException);
      expect(() => drink(amount: invalid), throwsFormatException);
    });
  }
  test('zero amount forbidden while zero label is allowed', () {
    expect(() => drink(amount: '0'), throwsFormatException);
    expect(beverage(energy: '0').energyValue, '0');
  });
  test('snapshot roundtrip preserves exact basis and detects tampering', () {
    final r = drink();
    expect(DrinkRecord.decode(r.encode()).encode(), r.encode());
    expect(
      () => DrinkRecord.fromJson({...r.toJson(), 'calories': '1/1'}),
      throwsFormatException,
    );
    final j = r.toJson()..remove('calories');
    expect(() => DrinkRecord.fromJson(j), throwsFormatException);
  });
  test('7/30 civil days preserve gaps, unknown and zero', () {
    final records = [
      drink(day: 19),
      drink(b: beverage(energy: '0'), day: 20),
      drink(b: beverage(energy: null), day: 18),
    ];
    final trend = beverageTrend(records, LocalDate(2026, 10, 20), 7);
    expect(trend.length, 7);
    expect(trend[LocalDate(2026, 10, 17)]!.display, '尚未记录');
    expect(trend[LocalDate(2026, 10, 18)]!.display, '热量待补');
    expect(trend[LocalDate(2026, 10, 20)]!.display, '0 kcal');
    expect(beverageTrend(records, LocalDate(2026, 10, 20), 30).length, 30);
    expect(beverageContributions(records).length, 3);
  });
  test('label parser extracts only explicit unambiguous label data', () {
    final parsed = parseBeverageLabel('可口可乐\n净含量: 330mL\n每100毫升\n能量 180 kJ');
    expect(parsed.energy, '180');
    expect(parsed.unit, EnergyUnit.kj);
    expect(parsed.basis, EnergyBasis.per100ml);
    expect(parsed.volumeMl, '330');
    expect(parseBeverageLabel('每100g 能量 180kJ').energy, isNull);
    expect(parseBeverageLabel('每100mL 能量 180kJ 每份 热量 60kcal').energy, isNull);
    expect(parseBeverageLabel('每100mL 180').energy, isNull);
    expect(parseBeverageLabel('每100mL 能量 0 kcal').energy, '0');
    expect(
      parseBeverageLabel('净含量 1.001 升\n每100毫升 能量 180 千焦').volumeMl,
      '1001',
    );
    expect(parseBeverageLabel('净含量 330毫升').volumeMl, '330');
    expect(parseBeverageLabel('品名：可口可乐\n净含量330mL').name, '可口可乐');
  });
}
