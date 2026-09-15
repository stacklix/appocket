import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentra/core/controller.dart';
import 'package:sentra/core/models.dart';
import 'package:sentra/main.dart';
import 'core_test.dart' show MemoryStorage, FakeGateway;

void main() {
  for (final action in AiAction.values) {
    testWidgets(
      '${action.name} Enter submits, composition and Shift Enter do not',
      (tester) async {
        final gateway = FakeGateway();
        final app = AppController(storage: MemoryStorage(), gateway: gateway);
        await app.initialize();
        app.switchAction(action);
        await tester.pumpWidget(SentraApp(controller: app));
        final field = find.byKey(const Key('sentence-input'));
        await tester.enterText(field, 'hello');
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '你好',
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: 0, end: 2),
          ),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(gateway.requests, isEmpty);
        await tester.enterText(field, 'hello');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(gateway.requests, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(gateway.requests, hasLength(1));
        expect(gateway.requests.single.$1, action);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
