import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/analysis/motion_catalog_page.dart';

void main() {
  testWidgets('catalog searches and filters the four first actions', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MotionCatalogPage()));
    expect(find.text('杠铃深蹲'), findsOneWidget);
    expect(find.text('自重引体向上'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '引体');
    await tester.pump();
    expect(find.text('自重引体向上'), findsOneWidget);
    expect(find.text('杠铃深蹲'), findsNothing);
  });
}
