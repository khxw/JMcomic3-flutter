import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/badge.dart';

void main() {
  testWidgets('empty badge renders a dot without a number', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Badged(
            badge: '',
            child: Icon(Icons.info_outline_rounded),
          ),
        ),
      ),
    ));

    expect(find.byKey(const ValueKey('version-update-dot')), findsOneWidget);
    expect(find.text('1'), findsNothing);
    expect(UpdateDot.defaultColor, const Color(0xFFE60012));
  });
}
