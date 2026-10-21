import 'dart:convert';

import 'beverage_energy.dart';
import 'local_date.dart';

enum BeverageKind { packaged, prepared }

enum EnergyUnit { kcal, kj }

enum EnergyBasis { per100ml, perServing }

enum DrinkUnit { ml, serving }

enum BeverageSource { label, official, publicDatabase, estimate }

extension BeverageSourceLabel on BeverageSource {
  String get label => switch (this) {
    BeverageSource.label => '包装标签',
    BeverageSource.official => '品牌官方',
    BeverageSource.publicDatabase => '公共数据库',
    BeverageSource.estimate => '个人估算',
  };
}

/// All numeric label values remain decimal text, including explicit zero.
class Beverage {
  final String id, name, brand, variant, size, sugar, additions, temperature;
  final BeverageKind kind;
  final String? volumeMl, energyValue;
  final EnergyUnit energyUnit;
  final EnergyBasis basis;
  final BeverageSource source;
  final String sourceNote;
  final String? sourceUrl;
  final int? verifiedAt;
  final bool favorite, archived;
  final int createdAt, updatedAt;

  Beverage({
    required this.id,
    required this.name,
    this.brand = '',
    this.variant = '',
    this.size = '',
    this.sugar = '',
    this.additions = '',
    this.temperature = '',
    this.kind = BeverageKind.packaged,
    this.volumeMl,
    this.energyValue,
    this.energyUnit = EnergyUnit.kcal,
    this.basis = EnergyBasis.per100ml,
    this.source = BeverageSource.estimate,
    this.sourceNote = '',
    this.sourceUrl,
    this.verifiedAt,
    this.favorite = false,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  }) {
    _text(id, 'ID', nonempty: true);
    _text(name, '饮料名称', nonempty: true);
    for (final t in [
      brand,
      variant,
      size,
      sugar,
      additions,
      temperature,
      sourceNote,
    ]) {
      _text(t, '资料');
    }
    if (volumeMl != null) BeverageEnergy.parse(volumeMl!, positive: true);
    if (energyValue != null) BeverageEnergy.parse(energyValue!);
    _time(createdAt);
    _time(updatedAt);
    if (verifiedAt != null) _time(verifiedAt!);
    if (sourceUrl != null) {
      final uri = Uri.tryParse(sourceUrl!);
      if (uri == null ||
          !{'https', 'http'}.contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw const FormatException('来源链接必须是 http(s) 地址');
      }
    }
  }

  String get description => [
    brand,
    variant,
    size,
    if (kind == BeverageKind.prepared) ...[sugar, additions, temperature],
  ].where((s) => s.isNotEmpty).join(' · ');
  String get energyLabel => energyValue == null
      ? '待补热量'
      : '$energyValue ${energyUnit == EnergyUnit.kj ? 'kJ' : 'kcal'} / ${basis == EnergyBasis.per100ml ? '100 mL' : '份'}';
  BeverageEnergy? calculate(String amount, DrinkUnit unit) {
    var quantity = BeverageEnergy.parse(amount, positive: true);
    // Validate conversion even for unknown energy; quantity must have meaning.
    if ((basis == EnergyBasis.per100ml && unit == DrinkUnit.serving) ||
        (basis == EnergyBasis.perServing && unit == DrinkUnit.ml)) {
      if (volumeMl == null) throw const FormatException('没有每份体积，不能换算 mL 与份数');
      final volume = BeverageEnergy.parse(volumeMl!, positive: true);
      quantity = unit == DrinkUnit.serving
          ? quantity * volume
          : quantity / volume;
    }
    if (energyValue == null) return null;
    var energy = BeverageEnergy.parse(energyValue!);
    if (energyUnit == EnergyUnit.kj) {
      energy = energy / BeverageEnergy.parse('4.184');
    }
    if (basis == EnergyBasis.per100ml) {
      quantity = quantity / BeverageEnergy.parse('100');
    }
    return energy * quantity;
  }

  Beverage copyWith({bool? favorite, bool? archived, int? updatedAt}) =>
      Beverage.fromJson({
        ...toJson(),
        'favorite': favorite ?? this.favorite,
        'archived': archived ?? this.archived,
        'updatedAt': updatedAt ?? this.updatedAt,
      });
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'brand': brand,
    'variant': variant,
    'size': size,
    'sugar': sugar,
    'additions': additions,
    'temperature': temperature,
    'kind': kind.name,
    'volumeMl': volumeMl,
    'energyValue': energyValue,
    'energyUnit': energyUnit.name,
    'basis': basis.name,
    'source': source.name,
    'sourceNote': sourceNote,
    'sourceUrl': sourceUrl,
    'verifiedAt': verifiedAt,
    'favorite': favorite,
    'archived': archived,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
  factory Beverage.fromJson(Map<String, dynamic> j) {
    try {
      _required(j, const [
        'id',
        'name',
        'brand',
        'variant',
        'size',
        'sugar',
        'additions',
        'temperature',
        'kind',
        'volumeMl',
        'energyValue',
        'energyUnit',
        'basis',
        'source',
        'sourceNote',
        'sourceUrl',
        'verifiedAt',
        'favorite',
        'archived',
        'createdAt',
        'updatedAt',
      ]);
      return Beverage(
        id: j['id'] as String,
        name: j['name'] as String,
        brand: j['brand'] as String,
        variant: j['variant'] as String,
        size: j['size'] as String,
        sugar: j['sugar'] as String,
        additions: j['additions'] as String,
        temperature: j['temperature'] as String,
        kind: BeverageKind.values.byName(j['kind'] as String),
        volumeMl: j['volumeMl'] as String?,
        energyValue: j['energyValue'] as String?,
        energyUnit: EnergyUnit.values.byName(j['energyUnit'] as String),
        basis: EnergyBasis.values.byName(j['basis'] as String),
        source: BeverageSource.values.byName(j['source'] as String),
        sourceNote: j['sourceNote'] as String,
        sourceUrl: j['sourceUrl'] as String?,
        verifiedAt: j['verifiedAt'] as int?,
        favorite: j['favorite'] as bool,
        archived: j['archived'] as bool,
        createdAt: j['createdAt'] as int,
        updatedAt: j['updatedAt'] as int,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('饮料资料字段无效');
    }
  }
  String encode() => jsonEncode(toJson());
  factory Beverage.decode(String s) =>
      Beverage.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

class DrinkRecord {
  final String id;
  final String? beverageId;
  final Beverage snapshot;
  final int occurredAt;
  final LocalDate date;
  final String amount;
  final DrinkUnit unit;
  final BeverageEnergy? calories;
  DrinkRecord({
    required this.id,
    required this.beverageId,
    required this.snapshot,
    required this.occurredAt,
    required this.date,
    required this.amount,
    required this.unit,
  }) : calories = snapshot.calculate(amount, unit) {
    _text(id, '记录 ID', nonempty: true);
    _time(occurredAt);
    if (beverageId != null) _text(beverageId!, '饮料引用', nonempty: true);
    // Stored civil date is authoritative after a timezone change. It must still
    // be plausible for the instant (any real world offset is within 24 hours).
    final utcDate = LocalDate.fromDateTime(
      DateTime.fromMillisecondsSinceEpoch(occurredAt, isUtc: true),
    );
    if (date.daysSince(utcDate).abs() > 2) {
      throw const FormatException('日期与发生时间不匹配');
    }
  }
  Map<String, Object?> toJson() => {
    'id': id,
    'beverageId': beverageId,
    'snapshot': snapshot.toJson(),
    'occurredAt': occurredAt,
    'date': date.key,
    'amount': amount,
    'unit': unit.name,
    'calories': calories?.exact,
  };
  factory DrinkRecord.fromJson(Map<String, dynamic> j) {
    try {
      _required(j, const [
        'id',
        'beverageId',
        'snapshot',
        'occurredAt',
        'date',
        'amount',
        'unit',
        'calories',
      ]);
      final date = LocalDate.tryParse(j['date'] as String);
      if (date == null) throw const FormatException('饮用日期无效');
      final record = DrinkRecord(
        id: j['id'] as String,
        beverageId: j['beverageId'] as String?,
        snapshot: Beverage.fromJson(j['snapshot'] as Map<String, dynamic>),
        occurredAt: j['occurredAt'] as int,
        date: date,
        amount: j['amount'] as String,
        unit: DrinkUnit.values.byName(j['unit'] as String),
      );
      if (record.calories?.exact != j['calories']) {
        throw const FormatException('历史热量快照与依据不一致');
      }
      return record;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('饮用记录字段无效');
    }
  }
  String encode() => jsonEncode(toJson());
  factory DrinkRecord.decode(String s) =>
      DrinkRecord.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

void _required(Map<String, dynamic> j, List<String> keys) {
  if (keys.any((k) => !j.containsKey(k))) {
    throw const FormatException('饮料数据缺少必需字段');
  }
}

void _text(String s, String label, {bool nonempty = false}) {
  if (s.length > 2000 || (nonempty && s.trim().isEmpty)) {
    throw FormatException('$label 为空或过长');
  }
}

void _time(int t) {
  if (t < 0 || t > 8640000000000000) throw const FormatException('时间超出范围');
}
