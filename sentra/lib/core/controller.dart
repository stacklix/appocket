import 'package:flutter/foundation.dart';
import 'api.dart';
import 'models.dart';
import 'storage.dart';

class AppController extends ChangeNotifier {
  AppController({required this.storage, required this.gateway});
  final AppStorage storage;
  final AnalysisGateway gateway;
  ApiSettings settings = const ApiSettings();
  List<Sentence> history = [];
  AiAction activeAction = AiAction.translate;
  final Map<AiAction, Sentence?> _currentByAction = {};
  final Map<AiAction, String> _draftByAction = {};
  Sentence? get current => _currentByAction[activeAction];
  set current(Sentence? value) => _currentByAction[activeAction] = value;
  String get draft => _draftByAction[activeAction] ?? '';
  set draft(String value) => _draftByAction[activeAction] = value;
  void switchAction(AiAction action) {
    activeAction = action;
    notifyListeners();
  }

  bool initialized = false;
  bool historyAvailable = true;
  String? notice;
  final Set<String> _pending = {};
  final Set<String> _deleting = {};
  Future<void> _deletionQueue = Future.value();
  final Map<String, String> _errors = {};
  final Map<String, String> _progress = {};
  final Map<String, AnalysisPhase> _phases = {};
  AnalysisPhase? phase(AiAction action) =>
      current == null ? null : _phases[_key(current!.id, action)];
  String progress(AiAction action) =>
      current == null ? '' : _progress[_key(current!.id, action)] ?? '';
  String _key(String id, AiAction action) => '$id:${action.name}';
  bool busy(AiAction action) =>
      current != null && _pending.contains(_key(current!.id, action));
  String? error(AiAction action) =>
      current == null ? null : _errors[_key(current!.id, action)];

  Future<void> initialize() async {
    try {
      settings = await storage.readSettings();
    } catch (_) {
      notice = '无法读取连接设置，请重新配置。';
    }
    try {
      history = await storage.readHistory();
      historyAvailable = true;
    } catch (_) {
      historyAvailable = false;
      notice = '历史记录读取失败，已保护原文件。请重新启动后重试。';
    }
    initialized = true;
    notifyListeners();
  }

  void setDraft(String value) {
    draft = value;
    if (current?.text != value.trim()) current = null;
    notifyListeners();
  }

  void open(Sentence sentence) {
    current = sentence;
    draft = sentence.text;
    notifyListeners();
  }

  void newSentence() {
    current = null;
    draft = '';
    notifyListeners();
  }

  Future<void> saveSettings(ApiSettings value) async {
    await storage.writeSettings(value);
    settings = value;
    // Preferences invalidate only the affected tab's cache; keep each draft.
    for (final action in AiAction.values) {
      final sentence = _currentByAction[action];
      if (sentence != null &&
          (sentence.explanationLanguage != value.explanationLanguage ||
              sentence.level != value.level ||
              (action == AiAction.translate &&
                  sentence.translationLanguage != value.translationLanguage))) {
        _currentByAction[action] = null;
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await _deletionQueue;
    try {
      await storage.writeHistory(history);
    } catch (_) {
      notice = '结果已生成，但本机保存失败。请释放存储空间后重试保存。';
    }
  }

  Future<void> retrySave() async {
    notice = null;
    await _save();
    notifyListeners();
  }

  Future<void> run(AiAction action, {bool force = false}) async {
    if (draft.trim().isEmpty || !settings.ready || !historyAvailable) return;
    final text = draft.trim();
    if (text.length > 4000) {
      notice = '每次最多输入 4000 个字符。';
      notifyListeners();
      return;
    }
    if (current != null && current!.learningVersion < 3) current = null;
    current ??= history
        .where(
          (s) =>
              s.text == text &&
              s.learningVersion == 3 &&
              (action != AiAction.translate ||
                  s.translationLanguage == settings.translationLanguage) &&
              s.explanationLanguage == settings.explanationLanguage &&
              s.level == settings.level,
        )
        .firstOrNull;
    if (current == null) {
      final now = DateTime.now();
      current = Sentence(
        id: now.microsecondsSinceEpoch.toString(),
        text: text,
        translationLanguage: settings.translationLanguage,
        explanationLanguage: settings.explanationLanguage,
        level: settings.level,
        createdAt: now,
      );
      history.insert(0, current!);
    }
    final sentence = current!;
    final key = _key(sentence.id, action);
    if (_pending.contains(key) ||
        (!force && sentence.results.containsKey(action))) {
      return;
    }
    _pending.add(key);
    _errors.remove(key);
    _progress.remove(key);
    _phases[key] = AnalysisPhase.connecting;
    notifyListeners();
    final config = settings;
    await _save();
    try {
      final result = await gateway.analyze(
        action,
        sentence,
        config,
        onPhase: (phase) {
          if (history.contains(sentence) &&
              !_deleting.contains(sentence.id) &&
              _phases[key] != phase) {
            _phases[key] = phase;
            notifyListeners();
          }
        },
        onProgress: (text) {
          if (history.contains(sentence) && !_deleting.contains(sentence.id)) {
            _progress[key] = text;
            notifyListeners();
          }
        },
      );
      // A deleted sentence must not return when a late request completes.
      if (history.contains(sentence) && !_deleting.contains(sentence.id)) {
        sentence.results[action] = result;
        await _save();
      }
    } catch (e) {
      if (history.contains(sentence) && !_deleting.contains(sentence.id)) {
        _errors[key] = e is UserFacingException ? e.message : '请求失败，请重试。';
      }
    } finally {
      _pending.remove(key);
      _progress.remove(key);
      notifyListeners();
    }
  }

  Future<void> delete(Sentence sentence) {
    if (!_deleting.add(sentence.id)) return Future.value();
    final operation = _deletionQueue.then((_) => _delete(sentence));
    _deletionQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _delete(Sentence sentence) async {
    final updated = history.where((e) => e.id != sentence.id).toList();
    try {
      await storage.writeHistory(updated);
      history.remove(sentence);
      for (final action in AiAction.values) {
        if (_currentByAction[action] == sentence) {
          _currentByAction[action] = null;
          _draftByAction[action] = '';
        }
      }
      for (final action in AiAction.values) {
        _errors.remove(_key(sentence.id, action));
      }
    } catch (_) {
      notice = '删除失败，请稍后重试。';
    } finally {
      _deleting.remove(sentence.id);
    }
    notifyListeners();
  }
}
