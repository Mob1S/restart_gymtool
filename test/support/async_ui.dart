import 'package:flutter_test/flutter_test.dart';

/// SQLite and platform futures use real I/O; fake frame time alone cannot
/// complete them. Wait for observable readiness with a bounded real deadline.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  required String description,
}) async {
  final elapsed = Stopwatch()..start();
  while (elapsed.elapsed < const Duration(seconds: 10)) {
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $description');
}
