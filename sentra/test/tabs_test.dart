import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sentra/core/api.dart';
import 'package:sentra/core/controller.dart';
import 'package:sentra/core/models.dart';
import 'package:sentra/main.dart';
import 'core_test.dart' show MemoryStorage, FakeGateway, config, flush, result;

Sentence sample(String text, {String target = '日语'}) => Sentence(
  id: 'test',
  text: text,
  translationLanguage: target,
  explanationLanguage: '简体中文',
  level: '中级',
  createdAt: DateTime(2026),
);
DirectAiGateway gateway(
  Map<String, dynamic> data, {
  void Function(String)? check,
}) => DirectAiGateway(
  clientFactory: () => MockClient((req) async {
    check?.call(jsonDecode(req.body)['messages'][0]['content'] as String);
    return http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(data)},
            },
          ],
        }),
      ),
      200,
    );
  }),
);
void main() {
  for (final target in ['英语', '日语', '法语']) {
    test('translation obeys explicitly selected $target target', () async {
      final data = {
        'source_language': '中文',
        'translation_language': target,
        'translations': [
          {'text': 'test translation', 'type': 'direct'},
          {'text': 'test translation', 'type': 'natural'},
        ],
        'notes': [],
      };
      final r = await gateway(
        data,
        check: (prompt) {
          expect(prompt, contains('TRANSLATION_LANGUAGE = $target'));
          expect(prompt, contains('EXPLANATION_LANGUAGE = 简体中文'));
          expect(prompt, isNot(contains('LEARNING_LANGUAGE')));
        },
      ).analyze(AiAction.translate, sample('你好', target: target), config);
      expect(r.schemaVersion, 3);
      expect(AnalysisResult.fromJson(r.toJson()).data, data);
    });
  }
  for (final text in ['我昨天去了电影院。', 'I go yesterday.', '昨日映画を見ます。']) {
    for (final action in [AiAction.grammar, AiAction.improve]) {
      test('${action.name} analyzes original input: $text', () async {
        final data = action == AiAction.grammar
            ? {
                'source_language': 'auto',
                'analysis_text': text,
                'analysis_origin': 'original',
                'correct': true,
                'summary': '解释',
                'corrections': [],
                'structure': [
                  {'text': text, 'part': '句子', 'role': '陈述'},
                ],
                'grammar_points': [],
              }
            : {
                'source_language': 'auto',
                'reference_text': text,
                'reference_origin': 'original',
                'naturalness': '较自然',
                'alternatives': [
                  {
                    'text': text,
                    'style': 'natural',
                    'translation': '释义',
                    'explanation': '解释',
                  },
                ],
              };
        final r = await gateway(
          data,
          check: (prompt) {
            expect(prompt, isNot(contains('TRANSLATION_LANGUAGE =')));
            expect(prompt, contains('original input in its own language'));
            expect(prompt, contains(DirectAiGateway.prompts[action]!));
          },
        ).analyze(action, sample(text), config);
        expect(r.data, data);
      });
    }
  }
  test(
    'reject automatic translation before grammar and wrong translation target',
    () async {
      final grammar = {
        'source_language': '中文',
        'analysis_text': 'Hello',
        'analysis_origin': 'translation',
        'correct': true,
        'summary': '...',
        'corrections': [],
        'structure': [
          {'text': 'Hello', 'part': 'word', 'role': 'greeting'},
        ],
        'grammar_points': [],
      };
      await expectLater(
        gateway(grammar).analyze(AiAction.grammar, sample('你好'), config),
        throwsA(isA<UserFacingException>()),
      );
      grammar['analysis_origin'] = 'original';
      await expectLater(
        gateway(grammar).analyze(AiAction.grammar, sample('你好'), config),
        throwsA(isA<UserFacingException>()),
      );
      final translation = {
        'source_language': '中文',
        'translation_language': '英语',
        'translations': [
          {'text': 'hello', 'type': 'direct'},
          {'text': 'hello', 'type': 'natural'},
        ],
        'notes': [],
      };
      await expectLater(
        gateway(
          translation,
        ).analyze(AiAction.translate, sample('你好', target: '日语'), config),
        throwsA(isA<UserFacingException>()),
      );
    },
  );
  test(
    'tab drafts and late results are independent; target changes only translation',
    () async {
      final store = MemoryStorage(), fake = FakeGateway();
      final app = AppController(storage: store, gateway: fake);
      await app.initialize();
      app.setDraft('你好');
      final translation = app.run(AiAction.translate);
      await flush();
      final originalTranslation = app.current;
      app.switchAction(AiAction.grammar);
      expect(app.draft, isEmpty);
      app.setDraft('I go yesterday.');
      final grammar = app.run(AiAction.grammar);
      await flush();
      final grammarSentence = app.current;
      fake.requests[0].$3.complete(result(AiAction.translate));
      await translation;
      expect(app.current, grammarSentence);
      expect(app.draft, 'I go yesterday.');
      fake.requests[1].$3.complete(result(AiAction.grammar));
      await grammar;
      await app.saveSettings(app.settings.withTranslationLanguage('日语'));
      expect(app.current, grammarSentence);
      app.switchAction(AiAction.translate);
      expect(app.current, isNull);
      expect(app.draft, '你好');
      final japanese = app.run(AiAction.translate);
      await flush();
      expect(app.current, isNot(originalTranslation));
      expect(fake.requests[2].$2.translationLanguage, '日语');
      fake.requests[2].$3.complete(result(AiAction.translate));
      await japanese;
      app.switchAction(AiAction.grammar);
      expect(app.current, grammarSentence);
    },
  );
  test('old records migrate without changing their semantics', () async {
    expect(
      ApiSettings.fromJson({'targetLanguage': 'English'}).translationLanguage,
      'English',
    );
    final old = Sentence.fromJson({
      'id': 'old',
      'text': 'hello',
      'targetLanguage': '简体中文',
      'level': '中级',
      'createdAt': '2026-01-01T00:00:00.000',
      'results': [],
    });
    expect(old.learningVersion, 1);
    expect(Sentence.fromJson(old.toJson()).learningVersion, 1);
    final app = AppController(storage: MemoryStorage(), gateway: FakeGateway());
    await app.initialize();
    app.history.add(old);
    app.open(old);
    final future = app.run(AiAction.translate);
    await flush();
    expect(app.current!.learningVersion, 3);
    expect(app.current, isNot(old));
    (app.gateway as FakeGateway).requests.single.$3.complete(
      result(AiAction.translate),
    );
    await future;
    expect(app.history, contains(old));
  });
  testWidgets(
    'three tabs keep their own input and only translation shows a language picker',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController(
        storage: MemoryStorage(),
        gateway: FakeGateway(),
      );
      await app.initialize();
      await tester.pumpWidget(SentraApp(controller: app));
      expect(find.text('翻译成'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('sentence-input')), '你好');
      await tester.tap(find.byKey(const Key('tab-grammar')));
      await tester.pumpAndSettle();
      expect(find.text('翻译成'), findsNothing);
      expect(app.draft, isEmpty);
      await tester.enterText(
        find.byKey(const Key('sentence-input')),
        'I go yesterday.',
      );
      await tester.tap(find.byKey(const Key('tab-improve')));
      await tester.pumpAndSettle();
      expect(find.text('翻译成'), findsNothing);
      expect(app.draft, isEmpty);
      await tester.tap(find.byKey(const Key('tab-translate')));
      await tester.pumpAndSettle();
      expect(app.draft, '你好');
      await tester.tap(find.byKey(const Key('tab-grammar')));
      await tester.pumpAndSettle();
      expect(app.draft, 'I go yesterday.');
      expect(tester.takeException(), isNull);
    },
  );
}
