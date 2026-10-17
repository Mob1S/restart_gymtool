import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/weight_value.dart';
import 'package:gym_tracker/domain/workout_csv.dart' as csv;

void main() {
  group('DecimalReading', () {
    test('normalizes native readings without padding or floating tails', () {
      for (final entry in {
        '50.00': '50',
        '052.500': '52.5',
        '1.250': '1.25',
        '.5': '0.5',
        '1.': '1',
        '+000.000': '0',
        '-0': '0',
        ' 2.5 ': '2.5',
        '1.25e2': '125',
        '5E-3': '0.005',
        '1.25e+1': '12.5',
      }.entries) {
        final reading = DecimalReading.parse(entry.key);
        expect(reading.text, entry.value, reason: entry.key);
        expect(reading.asDouble, double.parse(entry.value));
      }
    });

    test('repeated decimal steps and reverse steps stay exact', () {
      var amount = DecimalReading.parse('0');
      final tenth = DecimalReading.parse('0.1');
      for (var i = 0; i < 10; i++) {
        amount = amount.plusSteps(tenth, 1);
      }
      expect(amount.text, '1');
      expect(amount.plusSteps(tenth, -3).text, '0.7');
      expect(amount.plusSteps(DecimalReading.parse('1.25'), 3).text, '4.75');
      expect(amount.plusSteps(tenth, -10).text, '0');
      expect(amount.plusSteps(tenth, 0).text, '1');
      expect(amount.text, '1');
    });

    test('rejects malformed, negative, nonfinite and unbounded input', () {
      for (final text in [
        '',
        ' ',
        '.',
        '1,5',
        '1e',
        'NaN',
        'Infinity',
        '-Infinity',
        '-1',
        '-0.1',
        '-1e-999',
        '1e309',
        '1e-999999999',
        '0e9999999999999999999999999999999999',
        '0.${'0' * 5000}1',
      ]) {
        expect(
          () => DecimalReading.parse(text),
          throwsFormatException,
          reason: text.length > 100 ? 'oversized input' : text,
        );
      }
    });

    test(
      'arithmetic rejects nonpositive steps, negative results and overflow',
      () {
        final one = DecimalReading.parse('1');
        expect(
          () => one.plusSteps(DecimalReading.parse('0'), 1),
          throwsArgumentError,
        );
        expect(() => one.plusSteps(one, -2), throwsArgumentError);
        expect(
          () =>
              DecimalReading.parse('1e308')
                  .plusSteps(DecimalReading.parse('1e308'), 1),
          throwsArgumentError,
        );
        expect(DecimalReading.parse('1e-308').text, '0.${'0' * 307}1');
      },
    );
  });

  group('EquipmentWeight', () {
    test('器械单位选择保留数字，kg 只做参考', () {
      final original = EquipmentWeight.kg(40);
      final input = original.withUnit(WeightUnit.lb);
      expect(original.label, '40 kg');
      expect(input.label, '40 lb');
      final next = input.plusSteps(DecimalReading.parse('10'), 1);
      expect(next.label, '50 lb');
      expect(next.kilograms, closeTo(22.6796185, 1e-12));
      expect(next.kgReference, '≈ 22.68 kg');
      expect(next.plusSteps(DecimalReading.parse('2.5'), 1).label, '52.5 lb');
      expect(
        next.plusSteps(DecimalReading.parse('1.25'), -1).label,
        '48.75 lb',
      );
      expect(next.withUnit(WeightUnit.kg).kilograms, 50);
    });

    test('kg constructor validates and preserves usable decimal text', () {
      expect(EquipmentWeight.kg(1.25).label, '1.25 kg');
      expect(EquipmentWeight.kg(0).kgReference, '≈ 0.00 kg');
      expect(EquipmentWeight.kg(1e-7).amount.text, '0.0000001');
      for (final value in [
        -1.0,
        double.nan,
        double.infinity,
        -double.infinity,
      ]) {
        expect(() => EquipmentWeight.kg(value), throwsFormatException);
      }
    });

    test('CSV compatibility export refers to the shared unit enum', () {
      expect(identical(csv.WeightUnit.lb, WeightUnit.lb), isTrue);
    });
  });
}
