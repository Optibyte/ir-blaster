import 'package:esp/screens/ac_app/sigin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SignInPage smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: SignInPage()));

    // Verify that "Sign in" text is present
    expect(find.text('Sign in to access Dashboard'), findsOneWidget);
  });
}
