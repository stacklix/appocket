import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentra/core/controller.dart';
import 'package:sentra/main.dart';
import 'package:sentra/core/models.dart';
import 'package:sentra/ui/results.dart';
import 'core_test.dart' show MemoryStorage, FakeGateway;

void main() {
  testWidgets('all result structures render on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = <AiAction, Map<String, dynamic>>{
      AiAction.translate: {
        'translations': [
          {'text': '点心不太好吃。', 'type': 'natural'},
        ],
        'notes': ['需要结合上下文。'],
      },
      AiAction.grammar: {
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
      },
      AiAction.improve: {
        'naturalness': '较自然',
        'alternatives': [
          {
            'text': 'あまり美味しくなかったです。',
            'style': 'natural',
            'translation': '不太好吃。',
            'explanation': '语气更加柔和。',
          },
        ],
      },
    };
    for (final action in AiAction.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResultCard(
                action: action,
                result: AnalysisResult(
                  action: action,
                  data: data[action]!,
                  model: 'a-long-model-name-for-layout',
                  createdAt: DateTime.now(),
                ),
                loading: false,
                error: null,
                onRun: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('重新生成'), findsOneWidget);
      expect(tester.takeException(), null);
    }
  });
  testWidgets(
    'small iPhone input and independent actions render without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeGateway();
      final app = AppController(storage: MemoryStorage(), gateway: gateway);
      await app.initialize();
      await tester.pumpWidget(SentraApp(controller: app));
      expect(find.text('让意思，跨越语言。'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('sentence-input')),
        '昨日映画を見ます。',
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('run-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run-action')));
      await tester.pump();
      expect(gateway.requests.length, 1);
      expect(tester.takeException(), null);
      await tester.tap(find.byTooltip('连接与偏好'));
      await tester.pumpAndSettle();
      expect(find.text('API Base URL'), findsOneWidget);
      expect(find.text('Access Token'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
}
