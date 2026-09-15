import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentra/core/models.dart';
import 'package:sentra/core/storage.dart';

void main() {
  test(
    'browser storage restores settings and history across instances',
    () async {
      final storage = LocalStorage();
      final previousSettings = await storage.readSettings();
      final previousHistory = await storage.readHistory();
      try {
        const settings = ApiSettings(
          protocol: ApiProtocol.anthropic,
          baseUrl: 'https://gateway.example.com/v1',
          model: 'custom-model',
          token: 'test-session-token',
        );
        await storage.writeSettings(settings);
        final reopened = LocalStorage();
        expect((await reopened.readSettings()).toJson(), settings.toJson());
        final sentence = Sentence(
          id: 'web-test',
          text: '你好。',
          explanationLanguage: 'English',
          level: '初级',
          createdAt: DateTime(2026),
        );
        await storage.writeHistory([sentence]);
        expect((await reopened.readHistory()).single.text, '你好。');
        await storage.writeHistory([]);
        expect(await reopened.readHistory(), isEmpty);
        await storage.writeSettings(const ApiSettings());
        expect((await reopened.readSettings()).token, isEmpty);
      } finally {
        await storage.writeSettings(previousSettings);
        await storage.writeHistory(previousHistory);
      }
    },
    skip: !kIsWeb,
  );
}
