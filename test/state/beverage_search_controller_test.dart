import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/repositories/public_beverage_search.dart';
import 'package:gym_tracker/state/beverage_search_controller.dart';

void main() {
  test('public parser never treats per100g as per100ml; accepts explicit serving zero', () {
    final p = {
      'code': '5449000000996',
      'product_name': 'Cola',
      'brands': ['Coca-Cola'],
      'quantity': '330 ml',
      'nutrition_data_per': '100g',
      'nutriments': {'energy-kcal_100g': 42},
    };
    expect(parsePublicBeverage(p)!.single.energyValue, isNull);
    final serving = parsePublicBeverage({
      ...p,
      'serving_size': '1 portion (330 ml)',
      'nutriments': {'energy-kcal_serving': 0},
    })!.single;
    expect(serving.energyValue, '0');
    expect(serving.volumeMl, '330');
    expect(serving.brand, 'Coca-Cola');
  });
  test(
    'changed/cancelled query ignores old responses and caches current results',
    () async {
      final old = Completer<String>(), current = Completer<String>();
      var calls = 0;
      final search = BeverageSearchController(
        debounce: Duration.zero,
        minInterval: Duration.zero,
        searcher: PublicBeverageSearch(
          get: (uri) {
            calls++;
            return uri.queryParameters['q'] == 'old'
                ? old.future
                : current.future;
          },
        ),
      );
      addTearDown(search.dispose);
      search.update('old');
      await Future<void>.delayed(Duration.zero);
      search.update('new');
      await Future<void>.delayed(Duration.zero);
      current.complete(
        jsonEncode({
          'hits': [
            {'code': '12345', 'product_name': 'New'},
          ],
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(search.results.single.name, 'New');
      old.complete(
        jsonEncode({
          'hits': [
            {'code': '54321', 'product_name': 'Old'},
          ],
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(search.results.single.name, 'New');
      search.update('');
      expect(search.results, isEmpty);
      expect(search.status, PublicSearchStatus.idle);
      search.update('new');
      expect(search.results.single.name, 'New');
      expect(calls, 2);
    },
  );
  test('failure and no results produce distinct states', () async {
    final search = BeverageSearchController(
      debounce: Duration.zero,
      minInterval: Duration.zero,
      searcher: PublicBeverageSearch(
        get: (uri) async {
          if (uri.queryParameters['q'] == 'error') throw StateError('offline');
          return '{"hits":[]}';
        },
      ),
    );
    addTearDown(search.dispose);
    search.update('none');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(search.status, PublicSearchStatus.empty);
    search.update('error');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(search.status, PublicSearchStatus.failed);
  });
}
