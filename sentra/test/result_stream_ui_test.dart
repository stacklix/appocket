import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentra/core/controller.dart';
import 'package:sentra/core/models.dart';
import 'package:sentra/core/stream_preview.dart';
import 'package:sentra/main.dart';
import 'package:sentra/ui/results.dart';
import 'core_test.dart' show MemoryStorage, FakeGateway, config;
import 'anthropic_test.dart' show fixtures;

void main() {
  test('every JSON prefix is safe and full snapshots preserve structure', () {
    for (final data in fixtures.values) {
      final source = jsonEncode(data);
      for (var i = 0; i <= source.length; i++) {
        expect(() => partialResult(source.substring(0, i)), returnsNormally);
      }
      expect(partialResult(source), data);
    }
    expect(partialResult(r'{"notes":["hello\u4f'), {
      'notes': ['hello'],
    });
    expect(partialResult('```json\n{"text":"Hi'), {'text': 'Hi'});
    expect(partialResult(r'{"text":"hi\ud83d'), {'text': 'hi'});
  });
  for (final action in AiAction.values) {
    testWidgets('$action updates structured fields before JSON completion', (
      tester,
    ) async {
      final source = switch (action) {
        AiAction.translate => '{"translations":[{"type":"direct","text":"Hello',
        AiAction.grammar =>
          '{"correct":false,"summary":"Use past tense","structure":[{"text":"went","part":"verb","role":"pred',
        AiAction.improve =>
          '{"alternatives":[{"style":"conversational","text":"Hello',
      };
      Future<void> render(String progress) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResultCard(
                action: action,
                result: null,
                loading: true,
                error: null,
                onRun: null,
                progress: progress,
              ),
            ),
          ),
        ),
      );
      await render(source);
      expect(
        find.text(action == AiAction.grammar ? 'pred' : 'Hello'),
        findsOneWidget,
      );
      expect(
        find.text(switch (action) {
          AiAction.translate => '直译',
          AiAction.grammar => '句子结构',
          AiAction.improve => '更口语',
        }),
        findsOneWidget,
      );
      await render('$source more');
      expect(
        find.text(action == AiAction.grammar ? 'pred more' : 'Hello more'),
        findsOneWidget,
      );
      expect(find.byType(EditableText), findsNothing);
      expect(tester.takeException(), null);
    });
  }
  testWidgets('expression copy excludes explanation and has no text scroller', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    for (final action in [AiAction.translate, AiAction.improve]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResultCard(
                action: action,
                result: null,
                loading: true,
                error: null,
                onRun: null,
                progress: action == AiAction.translate
                    ? '{"translations":[{"type":"direct","text":"Hello"}]}'
                    : '{"alternatives":[{"style":"conversational","text":"Hi","explanation":"A greeting"}]}',
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byTooltip(action == AiAction.translate ? '复制直译' : '复制更口语'),
      );
      await tester.pump();
      expect(copied, action == AiAction.translate ? 'Hello' : 'Hi');
      expect(find.byType(EditableText), findsNothing);
    }
  });
  testWidgets('each tab copies its input and targets migrate to four choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final app = AppController(
      storage: MemoryStorage()
        ..settings = config.withTranslationLanguage('简体中文'),
      gateway: FakeGateway(),
    );
    await app.initialize();
    expect(app.settings.translationLanguage, '英语');
    await tester.pumpWidget(SentraApp(controller: app));
    expect(translationLanguages, ['英语', '日语', '俄语', '希腊语']);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('希腊语').last);
    await tester.pumpAndSettle();
    expect(app.settings.translationLanguage, '希腊语');
    expect(languageCode('Greek'), 'el');
    for (final action in AiAction.values) {
      await tester.tap(find.byKey(Key('tab-${action.name}')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('sentence-input')),
        '${action.name} text',
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('copy-input')));
      await tester.tap(find.byKey(const Key('copy-input')));
      await tester.pump();
      expect(copied, '${action.name} text');
      for (final heading in ['让意思，跨越语言。', '读懂句子的结构。', '找到更自然的说法。']) {
        expect(find.text(heading), findsNothing);
      }
      expect(tester.takeException(), null);
    }
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
