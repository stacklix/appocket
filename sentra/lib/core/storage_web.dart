import 'dart:convert';
import 'package:web/web.dart' as web;
import 'models.dart';
import 'storage_contract.dart';

// Web has no Keychain: credentials stay in tab-scoped sessionStorage.
// History is durable browser-local data, separate from credentials.
class LocalStorage implements AppStorage {
  static const _settingsKey = 'sentra.settings.v1';
  static const _historyKey = 'sentra.sentences.v1';

  @override
  Future<ApiSettings> readSettings() async {
    final value = web.window.sessionStorage.getItem(_settingsKey);
    return value == null
        ? const ApiSettings()
        : ApiSettings.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  @override
  Future<void> writeSettings(ApiSettings settings) async {
    web.window.sessionStorage.setItem(
      _settingsKey,
      jsonEncode(settings.toJson()),
    );
  }

  @override
  Future<List<Sentence>> readHistory() async {
    final value = web.window.localStorage.getItem(_historyKey);
    if (value == null) return [];
    return (jsonDecode(value) as List)
        .map((e) => Sentence.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> writeHistory(List<Sentence> sentences) async {
    // setItem atomically replaces this value, or throws on quota/access failure.
    web.window.localStorage.setItem(
      _historyKey,
      jsonEncode(sentences.map((s) => s.toJson()).toList()),
    );
  }
}
