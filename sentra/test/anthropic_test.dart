import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sentra/core/api.dart';
import 'package:sentra/core/controller.dart';
import 'package:sentra/core/models.dart';
import 'package:sentra/ui/settings.dart';
import 'core_test.dart' show MemoryStorage, FakeGateway, sentence;

const config = ApiSettings(
  protocol: ApiProtocol.anthropic,
  baseUrl: 'https://gateway.example.com/v1',
  model: 'provider-model-alias',
  token: 'test-key',
);
final fixtures = <AiAction, Map<String, dynamic>>{
  AiAction.translate: {
    'source_language': '日语',
    'input_in_learning_language': true,
    'translation_language': '简体中文',
    'translations': [
      {'text': '点心不好吃。', 'type': 'direct'},
      {'text': '点心不好吃。', 'type': 'natural'},
    ],
    'notes': <String>[],
  },
  AiAction.grammar: {
    'source_language': '日语',
    'input_in_learning_language': true,
    'analysis_origin': 'original',
    'analysis_text': 'お菓子は美味しくなかったです',
    'correct': true,
    'summary': '语法正确',
    'corrections': [],
    'structure': [
      {'text': 'お菓子', 'part': '名词', 'role': '主题'},
    ],
    'grammar_points': [],
  },
  AiAction.improve: {
    'source_language': '日语',
    'input_in_learning_language': true,
    'reference_origin': 'original',
    'reference_text': 'お菓子は美味しくなかったです',
    'naturalness': '较自然',
    'alternatives': [
      {
        'text': 'あまり美味しくなかったです。',
        'style': 'natural',
        'translation': '不太好吃。',
        'explanation': '语气柔和。',
      },
    ],
  },
};
void main() {
  test('protocol migration, persistence and Anthropic URL forms', () {
    expect(
      ApiSettings.fromJson({'baseUrl': 'https://example.com/v1'}).protocol,
      ApiProtocol.openAi,
    );
    expect(
      ApiSettings.fromJson(config.toJson()).protocol,
      ApiProtocol.anthropic,
    );
    for (final base in [
      'https://gateway.example.com',
      'https://gateway.example.com/',
      'https://gateway.example.com/v1/',
      'https://gateway.example.com/v1/messages/',
    ]) {
      expect(
        ApiSettings(
          protocol: ApiProtocol.anthropic,
          baseUrl: base,
        ).endpoint.toString(),
        'https://gateway.example.com/v1/messages',
      );
    }
    for (final base in [
      'https://api.kimi.com/coding',
      'https://api.kimi.com/coding/',
      'https://api.kimi.com/coding/v1/',
      'https://api.kimi.com/coding/v1/messages/',
    ]) {
      expect(
        ApiSettings(
          protocol: ApiProtocol.anthropic,
          baseUrl: base,
        ).endpoint.toString(),
        'https://api.kimi.com/coding/v1/messages',
      );
    }
    expect(
      const ApiSettings(
        protocol: ApiProtocol.anthropic,
        baseUrl: 'https://example.com/proxy/v1',
      ).endpoint.path,
      '/proxy/v1/messages',
    );
    expect(
      const ApiSettings(
        protocol: ApiProtocol.anthropic,
        baseUrl: 'https://example.com/v1/chat/completions',
        model: 'm',
        token: 't',
      ).validationError,
      contains('不匹配'),
    );
    expect(
      const ApiSettings(
        baseUrl: 'https://example.com/v1/messages',
        model: 'm',
        token: 't',
      ).validationError,
      contains('不匹配'),
    );
  });
  for (final action in AiAction.values) {
    test(
      'Anthropic ${action.name} sends compatible headers/body to a custom gateway and joins text blocks',
      () async {
        final api = DirectAiGateway(
          clientFactory: () => MockClient((req) async {
            expect(
              req.url.toString(),
              'https://gateway.example.com/v1/messages',
            );
            expect(req.method, 'POST');
            expect(req.followRedirects, false);
            expect(req.headers['x-api-key'], 'test-key');
            expect(req.headers['anthropic-version'], '2023-06-01');
            expect(req.headers.containsKey('Authorization'), false);
            final body = jsonDecode(req.body);
            expect(body['system'], contains(DirectAiGateway.prompts[action]!));
            expect(body['model'], config.model);
            expect(body['max_tokens'], 4096);
            expect(body['stream'], true);
            expect(body['messages'], hasLength(1));
            expect(body['messages'][0]['role'], 'user');
            expect(
              jsonDecode(body['messages'][0]['content'])['text'],
              sentence().text,
            );
            final content = jsonEncode(fixtures[action]);
            final split = content.length ~/ 2;
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'stop_reason': 'end_turn',
                  'content': [
                    {'type': 'thinking', 'thinking': 'not part of the result'},
                    {'type': 'text', 'text': content.substring(0, split)},
                    {'type': 'text', 'text': content.substring(split)},
                  ],
                }),
              ),
              200,
            );
          }),
        );
        expect(
          (await api.analyze(action, sentence(), config)).data,
          fixtures[action],
        );
      },
    );
  }
  for (final reason in ['max_tokens', 'refusal']) {
    test('Anthropic $reason rejects even otherwise valid JSON', () async {
      final api = DirectAiGateway(
        clientFactory: () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'stop_reason': reason,
              'content': [
                {
                  'type': 'text',
                  'text': jsonEncode(fixtures[AiAction.translate]),
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await expectLater(
        api.analyze(AiAction.translate, sentence(), config),
        throwsA(
          isA<UserFacingException>().having(
            (e) => e.message,
            'message',
            contains(reason == 'max_tokens' ? '长度上限' : '未能分析'),
          ),
        ),
      );
    });
  }
  for (final payload in [
    {},
    {'content': []},
    {
      'content': [
        {'type': 'text', 'text': 1},
      ],
    },
    {
      'content': [
        {'type': 'tool_use'},
      ],
    },
  ]) {
    test('malformed Anthropic response fails safely: $payload', () async {
      final api = DirectAiGateway(
        clientFactory: () =>
            MockClient((_) async => http.Response(jsonEncode(payload), 200)),
      );
      await expectLater(
        api.analyze(AiAction.translate, sentence(), config),
        throwsA(isA<UserFacingException>()),
      );
    });
  }
  for (final status in [400, 401, 429, 529]) {
    test('Anthropic HTTP $status produces a safe error', () async {
      final api = DirectAiGateway(
        clientFactory: () => MockClient(
          (_) async => http.Response('private server details', status),
        ),
      );
      await expectLater(
        api.analyze(AiAction.translate, sentence(), config),
        throwsA(
          isA<UserFacingException>().having(
            (e) => e.message,
            'message',
            isNot(contains('private')),
          ),
        ),
      );
    });
  }
  testWidgets(
    'settings protocol selection is saved and retained when removing token',
    (tester) async {
      final store = MemoryStorage();
      final app = AppController(storage: store, gateway: FakeGateway());
      await app.initialize();
      await tester.pumpWidget(MaterialApp(home: SettingsPage(controller: app)));
      await tester.ensureVisible(find.byKey(const Key('api-protocol')));
      await tester.tap(find.byKey(const Key('api-protocol')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anthropic 兼容').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存设置'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      expect(store.settings.protocol, ApiProtocol.anthropic);
      // A fresh settings page must restore the selected protocol.
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: SettingsPage(controller: app),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Anthropic 兼容'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('移除已保存的 Token'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('移除已保存的 Token'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除已保存的 Token'));
      await tester.pumpAndSettle();
      expect(store.settings.token, isEmpty);
      expect(store.settings.protocol, ApiProtocol.anthropic);
      expect(tester.takeException(), null);
    },
  );
}
