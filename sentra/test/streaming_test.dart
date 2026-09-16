import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sentra/core/api.dart';
import 'package:sentra/core/models.dart';
import 'package:sentra/ui/results.dart';
import 'anthropic_test.dart' show fixtures, config;
import 'core_test.dart' show sentence, MemoryStorage;
import 'package:sentra/core/controller.dart';
import 'package:sentra/core/stream_preview.dart';
import 'package:sentra/main.dart';

class StreamClient extends http.BaseClient {
  StreamClient(this.bytes);
  final Stream<List<int>> bytes;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(jsonDecode((request as http.Request).body)['stream'], true);
    return http.StreamedResponse(
      bytes,
      200,
      headers: {'content-type': 'text/event-stream; charset=utf-8'},
    );
  }
}

String event(Object data) => 'data: ${jsonEncode(data)}\r\n\r\n';
void main() {
  test(
    'partial arrays and escaped strings stream without leaking metadata',
    () {
      expect(streamPreview('{"source_language":"中文","notes":["解释正'), '解释正');
      expect(streamPreview('{"notes":["包含 ] 和 \\"'), contains('包含 ]'));
      expect(streamPreview(r'{"notes":["第一条","第二条\u4f'), '第一条\n\n第二条');
      expect(
        streamPreview(
          r'{"grammar_points":[{"title":"时态","inflections":["go","wen',
        ),
        '时态\n\ngo\n\nwen',
      );
      expect(
        streamPreview(r'{"text":"quote: \"hi\" and \\'),
        'quote: "hi" and \\',
      );
      expect(
        streamPreview('{"source_language":"中文","translation_language":"英语"'),
        '',
      );
    },
  );
  for (final protocol in ApiProtocol.values) {
    test(
      '$protocol reports thinking before output without mixing it into JSON',
      () async {
        final bytes = StreamController<List<int>>();
        final thinking = Completer<void>();
        final phases = <AnalysisPhase>[];
        final previews = <String>[];
        final api = DirectAiGateway(
          clientFactory: () => StreamClient(bytes.stream),
        );
        final future = api.analyze(
          AiAction.translate,
          sentence(),
          ApiSettings(
            protocol: protocol,
            baseUrl: config.baseUrl,
            model: config.model,
            token: config.token,
          ),
          onPhase: (phase) {
            phases.add(phase);
            if (phase == AnalysisPhase.thinking && !thinking.isCompleted) {
              thinking.complete();
            }
          },
          onProgress: previews.add,
        );
        bytes.add(
          utf8.encode(
            event(
              protocol == ApiProtocol.anthropic
                  ? {
                      'type': 'content_block_delta',
                      'delta': {
                        'type': 'thinking_delta',
                        'thinking': 'internal reasoning',
                      },
                    }
                  : {
                      'choices': [
                        {
                          'delta': {'reasoning_content': 'internal reasoning'},
                        },
                      ],
                    },
            ),
          ),
        );
        await thinking.future;
        expect(previews, isEmpty);
        expect(phases, [AnalysisPhase.connecting, AnalysisPhase.thinking]);
        final json = jsonEncode(fixtures[AiAction.translate]);
        bytes.add(
          utf8.encode(
            event(
              protocol == ApiProtocol.anthropic
                  ? {
                      'type': 'content_block_delta',
                      'delta': {'type': 'text_delta', 'text': json},
                    }
                  : {
                      'choices': [
                        {
                          'delta': {'content': json},
                        },
                      ],
                    },
            ),
          ),
        );
        bytes.add(
          utf8.encode(
            protocol == ApiProtocol.anthropic
                ? event({'type': 'message_stop'})
                : 'data: [DONE]\n\n',
          ),
        );
        await bytes.close();
        await future;
        expect(phases.last, AnalysisPhase.receiving);
        expect(previews.single, json);
      },
    );
  }
  testWidgets(
    'mobile receives visible notes through gateway and controller before completion',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = StreamController<List<int>>();
      final store = MemoryStorage()..settings = config;
      final app = AppController(
        storage: store,
        gateway: DirectAiGateway(
          clientFactory: () => StreamClient(bytes.stream),
        ),
      );
      await app.initialize();
      await tester.pumpWidget(SentraApp(controller: app));
      await tester.enterText(
        find.byKey(const Key('sentence-input')),
        sentence().text,
      );
      await tester.ensureVisible(find.byKey(const Key('run-action')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('run-action')));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(app.busy(AiAction.translate), true);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      bytes.add(
        utf8.encode(
          event({
            'type': 'content_block_delta',
            'delta': {'type': 'thinking_delta', 'thinking': 'private'},
          }),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      expect(app.phase(AiAction.translate), AnalysisPhase.thinking);
      expect(find.text('模型正在思考…'), findsOneWidget);
      expect(find.text('模型正在思考…').hitTestable(), findsOneWidget);
      bytes.add(
        utf8.encode(
          event({
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': '{"notes":["逐段解释'},
          }),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      expect(app.busy(AiAction.translate), true);
      expect(app.current!.results, isEmpty);
      expect(find.text('逐段解释').hitTestable(), findsOneWidget);
      bytes.add(
        utf8.encode(
          event({
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': '继续出现'},
          }),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      expect(find.text('逐段解释继续出现').hitTestable(), findsOneWidget);
      final tail = jsonEncode({
        ...fixtures[AiAction.translate]!,
        'translation_language': '英语',
      }).substring(1);
      bytes.add(
        utf8.encode(
          event({
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': '"],$tail'},
          }),
        ),
      );
      bytes.add(utf8.encode(event({'type': 'message_stop'})));
      await tester.runAsync(() async {
        await bytes.close();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(app.busy(AiAction.translate), false);
      expect(app.current!.results[AiAction.translate], isNotNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  for (final protocol in ApiProtocol.values) {
    test(
      '$protocol delivers text before completion across split UTF-8 bytes',
      () async {
        final bytes = StreamController<List<int>>();
        final received = Completer<void>();
        final previews = <String>[];
        final api = DirectAiGateway(
          clientFactory: () => StreamClient(bytes.stream),
        );
        var finished = false;
        final future = api
            .analyze(
              AiAction.translate,
              sentence(),
              ApiSettings(
                protocol: protocol,
                baseUrl: config.baseUrl,
                model: config.model,
                token: config.token,
              ),
              onProgress: (text) {
                previews.add(text);
                if (!received.isCompleted) received.complete();
              },
            )
            .then((value) {
              finished = true;
              return value;
            });
        final json = jsonEncode(fixtures[AiAction.translate]);
        void emit(String text) {
          final data = protocol == ApiProtocol.anthropic
              ? {
                  'type': 'content_block_delta',
                  'delta': {'type': 'text_delta', 'text': text},
                }
              : {
                  'choices': [
                    {
                      'delta': {'content': text},
                      'finish_reason': null,
                    },
                  ],
                };
          for (final byte in utf8.encode(event(data))) {
            bytes.add([byte]);
          }
        }

        emit(json.substring(0, 30));
        await received.future;
        expect(finished, false);
        emit(json.substring(30));
        bytes.add(
          utf8.encode(
            protocol == ApiProtocol.anthropic
                ? event({'type': 'message_stop'})
                : 'data: [DONE]\n\n',
          ),
        );
        await bytes.close();
        expect((await future).data, fixtures[AiAction.translate]);
        expect(previews.last, json);
        expect(previews.length, 2);
      },
    );
  }
  for (final end in ['disconnect', 'error', 'max_tokens']) {
    test('rejects $end without a completed result', () async {
      final events =
          event({
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': '{"text":"部分'},
          }) +
          (end == 'error'
              ? event({
                  'type': 'error',
                  'error': {'type': 'overloaded_error'},
                })
              : end == 'max_tokens'
              ? event({
                  'type': 'message_delta',
                  'delta': {'stop_reason': 'max_tokens'},
                })
              : '');
      final api = DirectAiGateway(
        clientFactory: () => StreamClient(Stream.value(utf8.encode(events))),
      );
      await expectLater(
        api.analyze(AiAction.translate, sentence(), config),
        throwsA(isA<UserFacingException>()),
      );
    });
  }
  testWidgets('renders incomplete text without JSON syntax', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResultCard(
            action: AiAction.translate,
            result: null,
            loading: true,
            error: null,
            onRun: null,
            progress: '{"translations":[{"text":"你好',
          ),
        ),
      ),
    );
    expect(find.text('你好'), findsOneWidget);
    expect(find.text('正在生成…'), findsOneWidget);
  });
}
