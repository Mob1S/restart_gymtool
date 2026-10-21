import 'dart:convert';

import '../../domain/beverage.dart';
import '../../domain/beverage_energy.dart';
import '../files/beverage_http.dart';

typedef BeverageHttpGet = Future<String> Function(Uri uri);

class PublicBeverageSearch {
  final BeverageHttpGet get;
  PublicBeverageSearch({BeverageHttpGet? get}) : get = get ?? beverageHttpGet;
  Future<List<Beverage>> search(String query) async {
    final uri = Uri.https('search.openfoodfacts.org', '/search', {
      'q': query,
      'page_size': '15',
    });
    final decoded = jsonDecode(await get(uri));
    if (decoded is! Map || decoded['hits'] is! List) {
      throw const FormatException('公共服务返回了无效响应');
    }
    return [
      for (final product in decoded['hits'] as List)
        if (product is Map<String, dynamic>) ...?parsePublicBeverage(product),
    ];
  }

  Future<Beverage> details(Beverage result) async {
    final code = result.id.replaceFirst('off-', '');
    final decoded = jsonDecode(
      await get(
        Uri.https('world.openfoodfacts.org', '/api/v2/product/$code', {
          'fields': 'code,product_name,product_name_zh,brands,quantity,serving_size,nutrition_data_per,product_quantity_unit,nutriments',
        }),
      ),
    );
    if (decoded is! Map || decoded['product'] is! Map<String, dynamic>) {
      throw const FormatException('公共详情不可用');
    }
    return parsePublicBeverage(decoded['product'] as Map<String, dynamic>)
            ?.first ??
        result;
  }
}

List<Beverage>? parsePublicBeverage(Map<String, dynamic> p) {
  final name = p['product_name_zh'] ?? p['product_name'];
  final code = p['code'];
  if (name is! String ||
      name.trim().isEmpty ||
      code is! String ||
      !RegExp(r'^\d{4,20}$').hasMatch(code)) {
    return null;
  }
  String text(String key) => p[key] is String
      ? p[key] as String
      : p[key] is List
      ? (p[key] as List).whereType<String>().join(', ')
      : '';
  final n = p['nutriments'] is Map ? p['nutriments'] as Map : const {};
  String? number(Object? value) {
    if (value is! num || !value.isFinite || value < 0) return null;
    final s = value.toString();
    return RegExp(r'^\d+(\.\d+)?$').hasMatch(s) && s.length <= 40 ? s : null;
  }

  String? ml(String value) {
    final m = RegExp(
      r'(?:^|\()(\d+(?:\.\d+)?)\s*(ml|l)\s*\)?\s*$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (m == null || double.parse(m[1]!) <= 0) return null;
    return m[2]!.toLowerCase() == 'l'
        ? (BeverageEnergy.parse(m[1]!) * BeverageEnergy.parse('1000'))
              .decimalText
        : m[1];
  }

  final serving = text('serving_size');
  var basis = EnergyBasis.perServing;
  var energy = serving.isNotEmpty ? number(n['energy-kcal_serving']) : null;
  var unit = EnergyUnit.kcal;
  if (energy == null && serving.isNotEmpty) {
    energy = number(n['energy-kj_serving']);
    unit = EnergyUnit.kj;
  }
  // OFF's generic *_100g fields do not establish volume. Never silently
  // assume a density, even when the product is sold in a bottle.
  if (p['nutrition_data_per'] == '100ml') {
    basis = EnergyBasis.per100ml;
    energy = number(n['energy-kcal_100g']);
    unit = EnergyUnit.kcal;
    if (energy == null) {
      energy = number(n['energy-kj_100g']);
      unit = EnergyUnit.kj;
    }
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  try {
    return [
      Beverage(
        id: 'off-$code',
        name: name,
        brand: text('brands'),
        size: serving.isNotEmpty ? serving : text('quantity'),
        volumeMl: basis == EnergyBasis.perServing
            ? ml(serving)
            : ml(text('quantity')),
        energyValue: energy,
        energyUnit: unit,
        basis: basis,
        source: BeverageSource.publicDatabase,
        sourceNote: 'Open Food Facts · 社区资料 · ODbL。请核对实际包装；每 100 g 数据不自动换为 mL。',
        sourceUrl: 'https://world.openfoodfacts.org/product/$code',
        createdAt: now,
        updatedAt: now,
      ),
    ];
  } on FormatException {
    return null;
  }
}
