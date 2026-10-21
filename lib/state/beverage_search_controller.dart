import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/beverage.dart';
import '../data/repositories/public_beverage_search.dart';

enum PublicSearchStatus { idle, loading, ready, empty, failed, timeout }

class BeverageSearchController extends ChangeNotifier {
  final PublicBeverageSearch searcher;
  final Duration debounce;
  final Duration minInterval;
  BeverageSearchController({
    PublicBeverageSearch? searcher,
    this.debounce = const Duration(milliseconds: 700),
    this.minInterval = const Duration(seconds: 6),
  }) : searcher = searcher ?? PublicBeverageSearch();
  final _cache = <String, (DateTime, List<Beverage>)>{};
  Timer? _timer;
  DateTime? _lastRequest;
  int _generation = 0;
  bool _disposed = false;
  String query = '';
  PublicSearchStatus status = PublicSearchStatus.idle;
  List<Beverage> results = [];
  void update(String value, {bool immediate = false}) {
    _timer?.cancel();
    final generation = ++_generation;
    query = value.trim();
    results = [];
    if (query.length < 2) {
      status = PublicSearchStatus.idle;
      notifyListeners();
      return;
    }
    final cached = _cache[query];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 10)) {
      results = cached.$2;
      status = results.isEmpty
          ? PublicSearchStatus.empty
          : PublicSearchStatus.ready;
      notifyListeners();
      return;
    }
    status = PublicSearchStatus.loading;
    notifyListeners();
    _timer = Timer(
      immediate ? Duration.zero : debounce,
      () => _run(query, generation),
    );
  }

  Future<void> _run(String value, int generation) async {
    if (_disposed || generation != _generation) return;
    final elapsed = _lastRequest == null
        ? minInterval
        : DateTime.now().difference(_lastRequest!);
    if (elapsed < minInterval) {
      _timer = Timer(minInterval - elapsed, () => _run(value, generation));
      return;
    }
    _lastRequest = DateTime.now();
    try {
      final found = await searcher
          .search(value)
          .timeout(const Duration(seconds: 16));
      if (_disposed || generation != _generation) return;
      if (_cache.length >= 20) _cache.remove(_cache.keys.first);
      _cache[value] = (DateTime.now(), found);
      results = found;
      status = found.isEmpty
          ? PublicSearchStatus.empty
          : PublicSearchStatus.ready;
    } on TimeoutException {
      if (!_disposed && generation == _generation) {
        status = PublicSearchStatus.timeout;
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        status = PublicSearchStatus.failed;
      }
    }
    if (!_disposed && generation == _generation) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
