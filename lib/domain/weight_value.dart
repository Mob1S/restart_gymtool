/// The unit printed on the equipment, independent of the kg statistics value.
enum WeightUnit { kg, lb }

/// An exact, nonnegative decimal equipment reading.
///
/// Decimal coefficients keep repeated custom steps such as 0.1 free of binary
/// floating point tails. Conversion to double happens only at numeric storage
/// and statistics boundaries.
class DecimalReading {
  final BigInt _coefficient;
  final int _scale;

  const DecimalReading._(this._coefficient, this._scale);

  // Well beyond practical equipment precision, while bounding hostile input and
  // exponents before allocating powers of ten or padding decimal strings.
  static const _maxDigits = 4096;
  static final _ten = BigInt.from(10);
  static final _syntax = RegExp(
    r'^([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?\d+))?$',
  );

  factory DecimalReading.parse(String text) {
    if (text.length > _maxDigits) {
      throw const FormatException('重量读数过长');
    }
    final source = text.trim();
    final match = _syntax.firstMatch(source);
    final value = double.tryParse(source);
    if (match == null || value == null || !value.isFinite) {
      throw const FormatException('重量必须为有限的非负十进制数');
    }
    final exponent = int.tryParse(match[5] ?? '0');
    if (exponent == null || exponent.abs() > _maxDigits) {
      throw const FormatException('重量指数超出支持范围');
    }
    final fraction = match[3] ?? match[4] ?? '';
    final scale = fraction.length - exponent;
    if (scale.abs() > _maxDigits) {
      throw const FormatException('重量精度超出支持范围');
    }
    var coefficient = BigInt.parse('${match[2] ?? '0'}$fraction');
    if (match[1] == '-') coefficient = -coefficient;
    if (coefficient.isNegative) {
      throw const FormatException('重量不能为负数');
    }
    return DecimalReading._normalized(coefficient, scale);
  }

  static DecimalReading _normalized(BigInt coefficient, int scale) {
    if (coefficient == BigInt.zero) {
      return DecimalReading._(BigInt.zero, 0);
    }
    if (scale < 0) {
      coefficient *= _ten.pow(-scale);
      scale = 0;
    }
    while (scale > 0 && coefficient % _ten == BigInt.zero) {
      coefficient ~/= _ten;
      scale--;
    }
    return DecimalReading._(coefficient, scale);
  }

  String get text {
    final digits = _coefficient.toString().padLeft(_scale + 1, '0');
    if (_scale == 0) return digits;
    final split = digits.length - _scale;
    return '${digits.substring(0, split)}.${digits.substring(split)}';
  }

  double get asDouble => double.parse(text);

  DecimalReading plusSteps(DecimalReading step, int count) {
    if (step._coefficient <= BigInt.zero) {
      throw ArgumentError.value(step.text, 'step', '步长必须大于 0');
    }
    final common = _scale > step._scale ? _scale : step._scale;
    final a = _coefficient * _ten.pow(common - _scale);
    final b = step._coefficient * _ten.pow(common - step._scale);
    final coefficient = a + b * BigInt.from(count);
    if (coefficient.isNegative) {
      throw ArgumentError.value(count, 'count', '调整后的重量不能为负数');
    }
    final result = DecimalReading._normalized(coefficient, common);
    if (!result.asDouble.isFinite) {
      throw ArgumentError.value(count, 'count', '调整后的重量必须为有限数');
    }
    return result;
  }
}

/// An equipment reading together with its original unit.
class EquipmentWeight {
  final DecimalReading amount;
  final WeightUnit unit;

  const EquipmentWeight(this.amount, this.unit);

  factory EquipmentWeight.kg(double value) =>
      EquipmentWeight(DecimalReading.parse(value.toString()), WeightUnit.kg);

  double get kilograms =>
      unit == WeightUnit.lb ? amount.asDouble * 0.45359237 : amount.asDouble;

  String get label => '${amount.text} ${unit.name}';

  String get kgReference => '≈ ${kilograms.toStringAsFixed(2)} kg';

  EquipmentWeight withUnit(WeightUnit next) => EquipmentWeight(amount, next);

  EquipmentWeight plusSteps(DecimalReading step, int count) =>
      EquipmentWeight(amount.plusSteps(step, count), unit);
}
