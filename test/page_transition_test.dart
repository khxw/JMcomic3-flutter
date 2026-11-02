import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/compose_ui.dart';

void main() {
  testWidgets('material page routes return with a smooth reverse animation',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(pageTransitionsTheme: composePageTransitions),
        home: const Scaffold(body: Text('previous page')),
      ),
    );

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('current page')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('current page'), findsOneWidget);

    navigatorKey.currentState!.pop();
    await tester.pump();

    expect(find.text('current page'), findsOneWidget);
    expect(find.text('previous page'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 16));
    final reverseOffsets = tester
        .widgetList<SlideTransition>(find.byType(SlideTransition))
        .map((transition) => transition.position.value.dx);
    expect(reverseOffsets.any((offset) => offset > .08), isTrue);
    expect(reverseOffsets.any((offset) => offset < -.002), isTrue);

    await tester.pump(const Duration(milliseconds: 84));
    expect(find.text('current page'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('current page'), findsNothing);
    expect(find.text('previous page'), findsOneWidget);
  });
}
