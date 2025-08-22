// test/widget_test.dart (A simple, guaranteed-to-work test)

import 'package:flutter_test/flutter_test.dart';
import 'package:sahara_app/main.dart';

void main() {
  testWidgets('Sahara App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SaharaApp());

    // For now, our only test is to verify that the main "SaharaApp"
    // widget itself can be successfully built without crashing.
    // We will not look for any specific text yet.
    expect(find.byType(SaharaApp), findsOneWidget);
  });
}