/// Exact decimal/rational arithmetic. No binary floating point enters totals.
class BeverageEnergy implements Comparable<BeverageEnergy> {
  final BigInt numerator;
  final BigInt denominator;
  const BeverageEnergy._(this.numerator, this.denominator);

  factory BeverageEnergy.ratio(BigInt n, BigInt d) {
    if (n.isNegative || d <= BigInt.zero) {
      throw const FormatException('数值必须非负，除数必须为正');
    }
    final gcd = n.gcd(d);
    return BeverageEnergy._(n ~/ gcd, d ~/ gcd);
  }

  factory BeverageEnergy.parse(String input, {bool positive = false}) {
    final text = input.trim();
    if (text.length > 40 || !RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) {
      throw const FormatException('请输入有限非负十进制数（最多 40 位）');
    }
    final parts = text.split('.');
    final n = BigInt.parse(parts.join());
    if (positive && n == BigInt.zero) {
      throw const FormatException('饮用量和容量必须大于 0');
    }
    return BeverageEnergy.ratio(
      n,
      BigInt.from(10).pow(parts.length == 1 ? 0 : parts[1].length),
    );
  }

  static final zero = BeverageEnergy.parse('0');
  BeverageEnergy operator +(BeverageEnergy b) => BeverageEnergy.ratio(
    numerator * b.denominator + b.numerator * denominator,
    denominator * b.denominator,
  );
  BeverageEnergy operator *(BeverageEnergy b) => BeverageEnergy.ratio(
    numerator * b.numerator,
    denominator * b.denominator,
  );
  BeverageEnergy operator /(BeverageEnergy b) => BeverageEnergy.ratio(
    numerator * b.denominator,
    denominator * b.numerator,
  );
  @override
  int compareTo(BeverageEnergy other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);
  @override
  bool operator ==(Object other) =>
      other is BeverageEnergy &&
      numerator == other.numerator &&
      denominator == other.denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);

  String get exact => '$numerator/$denominator';

  /// For finite decimal conversions such as liters to mL. Energy division by
  /// 4.184 may repeat and deliberately has no decimal-text representation.
  String get decimalText {
    var d = denominator;
    var twos = 0;
    var fives = 0;
    while (d % BigInt.two == BigInt.zero) {
      d ~/= BigInt.two;
      twos++;
    }
    final five = BigInt.from(5);
    while (d % five == BigInt.zero) {
      d ~/= five;
      fives++;
    }
    if (d != BigInt.one) throw StateError('不是有限小数');
    final scale = twos > fives ? twos : fives;
    final coefficient =
        numerator * BigInt.two.pow(scale - twos) * five.pow(scale - fives);
    final digits = coefficient.toString().padLeft(scale + 1, '0');
    if (scale == 0) return digits;
    return '${digits.substring(0, digits.length - scale)}.${digits.substring(digits.length - scale)}';
  }

  double get asDouble => numerator.toDouble() / denominator.toDouble();
  String get display {
    if (numerator == BigInt.zero) return '0';
    final ten = BigInt.from(10);
    if (numerator * ten < denominator) return '<0.1';
    final tenths =
        (numerator * ten * BigInt.two + denominator) ~/
        (denominator * BigInt.two);
    final whole = tenths ~/ ten;
    final fraction = tenths % ten;
    return fraction == BigInt.zero ? '$whole' : '$whole.$fraction';
  }
}
