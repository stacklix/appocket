import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentra/core/controller.dart';
import 'package:sentra/core/models.dart';
import 'package:sentra/main.dart';
import 'package:sentra/ui/results.dart';
import 'core_test.dart' show MemoryStorage, FakeGateway;

void main() {
  testWidgets('desktop navigation, split results, shortcuts and resizing', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeGateway();
    final app = AppController(storage: MemoryStorage(), gateway: gateway);
    await app.initialize();
    await tester.pumpWidget(SentraApp(controller: app));
    expect(find.byKey(const Key('desktop-sidebar')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(ResultCard), findsNothing);
    await tester.enterText(find.byKey(const Key('sentence-input')), 'Hello');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(gateway.requests, hasLength(1));
    expect(
      tester.getTopLeft(find.byType(ResultCard)).dx,
      greaterThan(
        tester.getTopRight(find.byKey(const Key('sentence-input'))).dx,
      ),
    );
    await tester.tap(find.byKey(const Key('desktop-grammar')));
    await tester.pump();
    expect(app.activeAction, AiAction.grammar);
    expect(app.draft, isEmpty);
    await tester.tap(find.text('连接与偏好'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    Navigator.of(tester.element(find.byType(Dialog))).pop();
    await tester.pumpAndSettle();
    for (final size in [
      const Size(950, 600),
      const Size(760, 600),
      const Size(390, 844),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
