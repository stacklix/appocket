import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sentra/core/api.dart';
import 'package:sentra/core/controller.dart';
import 'package:sentra/core/models.dart';
import 'package:sentra/core/storage.dart';

const config = ApiSettings(
  baseUrl: 'https://example.com/v1/',
  model: 'test-model',
  token: 'test-only-token',
);
final translation = {
  'source_language': '日语',
  'input_in_learning_language': true,
  'translation_language': '简体中文',
  'translations': [
    {'text': '点心不好吃。', 'type': 'direct'},
    {'text': '点心不好吃。', 'type': 'natural'},
  ],
  'notes': <String>[],
};
AnalysisResult result(AiAction action) => AnalysisResult(
  action: action,
  data: translation,
  model: 'test-model',
  createdAt: DateTime(2026),
);
Sentence sentence() => Sentence(
  id: '1',
  text: 'お菓子は美味しくなかったです',
  learningLanguage: '日语',
  explanationLanguage: '简体中文',
  level: '中级',
  createdAt: DateTime(2026),
);

class MemoryStorage implements AppStorage {
  ApiSettings settings = config;
  String snapshot = '[]';
  bool failWrite = false;
  @override
  Future<ApiSettings> readSettings() async => settings;
  @override
  Future<void> writeSettings(ApiSettings value) async {
    settings = value;
  }

  @override
  Future<List<Sentence>> readHistory() async =>
      (jsonDecode(snapshot) as List).map((e) => Sentence.fromJson(e)).toList();
  @override
  Future<void> writeHistory(List<Sentence> values) async {
    if (failWrite) throw Exception('disk full');
    snapshot = jsonEncode(values.map((s) => s.toJson()).toList());
  }
}

class FakeGateway implements AnalysisGateway {
  final requests = <(AiAction, Sentence, Completer<AnalysisResult>)>[];
  @override
  Future<AnalysisResult> analyze(
    AiAction action,
    Sentence s,
    ApiSettings settings, {
    void Function(String text)? onProgress,
    void Function(AnalysisPhase phase)? onPhase,
  }) {
    final c = Completer<AnalysisResult>();
    requests.add((action, s, c));
    return c.future;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);
void main() {
  test('concurrent deletions persist the final empty history', () async {
    final store = MemoryStorage();
    final app = AppController(storage: store, gateway: FakeGateway());
    await app.initialize();
    final first = sentence();
    final second = Sentence(
      id: '2',
      text: 'second',
      explanationLanguage: '简体中文',
      level: '中级',
      createdAt: DateTime.now(),
    );
    app.history = [first, second];
    await Future.wait([app.delete(first), app.delete(second)]);
    expect(app.history, isEmpty);
    expect(await store.readHistory(), isEmpty);
  });
  test('HTTPS validation and endpoint normalization', () {
    expect(
      config.endpoint.toString(),
      'https://example.com/v1/chat/completions',
    );
    expect(
      const ApiSettings(
        baseUrl: 'http://example.com',
        model: 'm',
        token: 't',
      ).ready,
      false,
    );
    expect(
      const ApiSettings(
        baseUrl: 'https://example.com/?key=t',
        model: 'm',
        token: 't',
      ).ready,
      false,
    );
    expect(
      const ApiSettings(
        baseUrl: 'https://example.com/chat/completions',
        model: 'm',
        token: 't',
      ).endpoint.path,
      '/chat/completions',
    );
  });
  test(
    'direct call sends only chosen action and parses UTF-8 fenced JSON',
    () async {
      final api = DirectAiGateway(
        clientFactory: () => MockClient((req) async {
          expect(req.url, config.endpoint);
          expect(req.headers['Authorization'], 'Bearer test-only-token');
          expect(req.followRedirects, false);
          final body = jsonDecode(req.body);
          expect(body['model'], 'test-model');
          expect(body['messages'][0]['content'], contains('Translate only'));
          expect(
            body['messages'][0]['content'],
            isNot(contains('Analyze grammatical correctness')),
          );
          expect(
            jsonDecode(body['messages'][1]['content'])['text'],
            sentence().text,
          );
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': '```json\n${jsonEncode(translation)}\n```',
                    },
                  },
                ],
              }),
            ),
            200,
          );
        }),
      );
      expect(
        (await api.analyze(AiAction.translate, sentence(), config)).data,
        translation,
      );
    },
  );
  for (final code in [401, 403, 404, 429, 500, 302]) {
    test('HTTP $code produces a safe user-facing error', () async {
      final api = DirectAiGateway(
        clientFactory: () => MockClient(
          (_) async => http.Response('secret provider detail', code),
        ),
      );
      await expectLater(
        api.analyze(AiAction.translate, sentence(), config),
        throwsA(
          isA<UserFacingException>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('secret')),
          ),
        ),
      );
    });
  }
  test('timeout and malformed responses are recoverable', () async {
    final api = DirectAiGateway(
      timeout: const Duration(milliseconds: 1),
      clientFactory: () => MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(
      api.analyze(AiAction.translate, sentence(), config),
      throwsA(isA<UserFacingException>()),
    );
    final malformed = DirectAiGateway(
      clientFactory: () => MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      malformed.analyze(AiAction.translate, sentence(), config),
      throwsA(isA<UserFacingException>()),
    );
  });
  test('separate schemas reject missing or invalid structure', () {
    expect(
      () => AnalysisResult.parse(
        AiAction.translate,
        '{"translations":[],"notes":[]}',
      ),
      throwsFormatException,
    );
    expect(
      () => AnalysisResult.parse(AiAction.grammar, '{"correct":true}'),
      throwsFormatException,
    );
    expect(
      () => AnalysisResult.parse(
        AiAction.improve,
        '{"naturalness":"natural","alternatives":[{"text":"hi"}]}',
      ),
      throwsFormatException,
    );
    final grammar = {
      'correct': false,
      'summary': '时态有误',
      'corrections': [
        {'original': '見ます', 'corrected': '見ました', 'explanation': '昨天为过去'},
      ],
      'structure': [
        {'text': '昨日', 'part': '名词', 'role': '时间'},
      ],
      'grammar_points': [
        {
          'title': '过去式',
          'explanation': 'ます变ました',
          'inflections': ['見ます', '見ました'],
        },
      ],
    };
    expect(
      AnalysisResult.parse(AiAction.grammar, jsonEncode(grammar)),
      grammar,
    );
  });
  test('independent requests, deduplication, caching and restore', () async {
    final store = MemoryStorage(), gateway = FakeGateway();
    final app = AppController(storage: store, gateway: gateway);
    await app.initialize();
    app.setDraft('hello');
    final one = app.run(AiAction.translate);
    await flush();
    final duplicate = app.run(AiAction.translate);
    expect(gateway.requests.length, 1);
    gateway.requests[0].$3.complete(result(AiAction.translate));
    await one;
    await duplicate;
    await app.run(AiAction.translate);
    expect(gateway.requests.length, 1);
    final two = app.run(AiAction.grammar);
    await flush();
    expect(app.current!.results.containsKey(AiAction.translate), true);
    gateway.requests[1].$3.completeError(const UserFacingException('网络失败'));
    await two;
    expect(app.error(AiAction.grammar), '网络失败');
    final restored = AppController(storage: store, gateway: FakeGateway());
    await restored.initialize();
    expect(
      restored.history.single.results[AiAction.translate]!.data,
      translation,
    );
    expect(store.snapshot, isNot(contains(config.token)));
  });
  test(
    'late response stays with original sentence; deleted requests stay deleted',
    () async {
      final store = MemoryStorage(), gateway = FakeGateway();
      final app = AppController(storage: store, gateway: gateway);
      await app.initialize();
      app.setDraft('first');
      final one = app.run(AiAction.translate);
      await flush();
      app.setDraft('second');
      final two = app.run(AiAction.translate);
      await flush();
      final second = app.current!;
      gateway.requests[0].$3.complete(result(AiAction.translate));
      await one;
      expect(app.current, second);
      expect(second.results, isEmpty);
      await app.delete(second);
      gateway.requests[1].$3.complete(result(AiAction.translate));
      await two;
      expect(app.history.length, 1);
      expect((jsonDecode(store.snapshot) as List).length, 1);
    },
  );
  test(
    'changing language creates a separate learning record; save failure is visible',
    () async {
      final store = MemoryStorage(), gateway = FakeGateway();
      final app = AppController(storage: store, gateway: gateway);
      await app.initialize();
      app.setDraft('hello');
      final one = app.run(AiAction.translate);
      await flush();
      gateway.requests[0].$3.complete(result(AiAction.translate));
      await one;
      await app.saveSettings(
        const ApiSettings(
          baseUrl: 'https://example.com',
          model: 'm',
          token: 't',
          explanationLanguage: '日本語',
        ),
      );
      expect(app.current, null);
      store.failWrite = true;
      final two = app.run(AiAction.translate);
      await flush();
      gateway.requests[1].$3.complete(result(AiAction.translate));
      await two;
      expect(app.history.length, 2);
      expect(app.notice, contains('保存失败'));
      store.failWrite = false;
      await app.retrySave();
      expect(app.notice, null);
    },
  );
}
