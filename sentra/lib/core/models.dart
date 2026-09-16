import 'dart:convert';

enum AiAction {
  translate('翻译', 'TRANSLATE', '将原文翻译成你选择的语言'),
  grammar('语法', 'GRAMMAR', '直接检查原句，理解句子结构与语法'),
  improve('更地道', 'NATURAL', '保留原文语言，让表达更自然');

  const AiAction(this.label, this.english, this.question);
  final String label;
  final String english;
  final String question;
}

enum ApiProtocol {
  openAi('OpenAI 兼容'),
  anthropic('Anthropic 兼容');

  const ApiProtocol(this.label);
  final String label;
}

class ApiSettings {
  const ApiSettings({
    this.protocol = ApiProtocol.openAi,
    this.baseUrl = '',
    this.model = '',
    this.token = '',
    this.translationLanguage = '英语',
    this.explanationLanguage = '简体中文',
    this.level = '中级',
  });
  final ApiProtocol protocol;
  final String baseUrl,
      model,
      token,
      translationLanguage,
      explanationLanguage,
      level;
  bool get ready => validationError == null;
  String? get validationError {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return '请填写有效的 HTTPS API Base URL，不要包含查询参数或账号密码。';
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if ((protocol == ApiProtocol.anthropic &&
            path.endsWith('/chat/completions')) ||
        (protocol == ApiProtocol.openAi && path.endsWith('/messages'))) {
      return '接口地址与所选协议不匹配，请修改地址或协议。';
    }
    if (model.trim().isEmpty) return '请填写模型名称。';
    if (token.trim().isEmpty) return '请填写 Access Token。';
    return null;
  }

  Uri get endpoint {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (protocol == ApiProtocol.anthropic) {
      if (base.endsWith('/messages')) return Uri.parse(base);
      return Uri.parse(
        base.endsWith('/v1') ? '$base/messages' : '$base/v1/messages',
      );
    }
    return Uri.parse(
      base.endsWith('/chat/completions') ? base : '$base/chat/completions',
    );
  }

  ApiSettings withTranslationLanguage(String value) => ApiSettings(
    protocol: protocol,
    baseUrl: baseUrl,
    model: model,
    token: token,
    translationLanguage: value,
    explanationLanguage: explanationLanguage,
    level: level,
  );

  Map<String, dynamic> toJson() => {
    'protocol': protocol.name,
    'baseUrl': baseUrl,
    'model': model,
    'token': token,
    'translationLanguage': translationLanguage,
    'explanationLanguage': explanationLanguage,
    'level': level,
  };
  factory ApiSettings.fromJson(Map<String, dynamic> j) => ApiSettings(
    protocol: j['protocol'] == null
        ? ApiProtocol.openAi
        : ApiProtocol.values.byName(j['protocol'] as String),
    baseUrl: j['baseUrl'] as String? ?? '',
    model: j['model'] as String? ?? '',
    token: j['token'] as String? ?? '',
    translationLanguage:
        j['translationLanguage'] as String? ??
        j['targetLanguage'] as String? ??
        '简体中文',
    explanationLanguage:
        j['explanationLanguage'] as String? ??
        j['targetLanguage'] as String? ??
        '简体中文',
    level: j['level'] as String? ?? '中级',
  );
}

// Each action has its own contract. Validate before persisting or rendering.
class AnalysisResult {
  AnalysisResult({
    required this.action,
    required this.data,
    required this.model,
    required this.createdAt,
    this.schemaVersion = 1,
  });
  final int schemaVersion;
  final AiAction action;
  final Map<String, dynamic> data;
  final String model;
  final DateTime createdAt;
  static Map<String, dynamic> parse(
    AiAction action,
    String content, {
    bool requireContext = false,
    int schemaVersion = 3,
  }) {
    var text = content.trim();
    if (text.startsWith('```')) {
      text = text
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }
    final raw = jsonDecode(text);
    if (raw is! Map<String, dynamic>) throw const FormatException('需要 JSON 对象');
    void string(Map<String, dynamic> item, String key) {
      if (item[key] is! String || (item[key] as String).trim().isEmpty) {
        throw FormatException('缺少字段 $key');
      }
    }

    void strings(Map<String, dynamic> item, String key) {
      if (item[key] is! List || (item[key] as List).any((e) => e is! String)) {
        throw FormatException('无效字段 $key');
      }
    }

    void objects(
      String key,
      List<String> keys, {
      bool nonempty = false,
      String? listKey,
    }) {
      final list = raw[key];
      if (list is! List || (nonempty && list.isEmpty)) {
        throw FormatException('无效字段 $key');
      }
      for (final item in list) {
        if (item is! Map<String, dynamic>) throw FormatException('无效字段 $key');
        for (final field in keys) {
          string(item, field);
        }
        if (listKey != null) strings(item, listKey);
      }
    }

    if (requireContext) {
      string(raw, 'source_language');
      if (schemaVersion == 2 && raw['input_in_learning_language'] is! bool) {
        throw const FormatException('缺少输入语言判断');
      }
      if (action == AiAction.translate) {
        string(raw, 'translation_language');
      } else {
        final prefix = action == AiAction.grammar ? 'analysis' : 'reference';
        string(raw, '${prefix}_text');
        final expected =
            schemaVersion >= 3 || raw['input_in_learning_language'] == true
            ? 'original'
            : 'translation';
        if (raw['${prefix}_origin'] != expected) {
          throw const FormatException('分析对象来源不一致');
        }
        if (action == AiAction.grammar &&
            expected == 'translation' &&
            (raw['correct'] != true ||
                raw['corrections'] is! List ||
                (raw['corrections'] as List).isNotEmpty)) {
          throw const FormatException('译文分析不能当作用户原文纠错');
        }
      }
    }
    switch (action) {
      case AiAction.translate:
        objects('translations', ['text', 'type'], nonempty: true);
        strings(raw, 'notes');
      case AiAction.grammar:
        if (raw['correct'] is! bool) throw const FormatException('缺少正确性判断');
        string(raw, 'summary');
        objects('corrections', [
          'original',
          'corrected',
          'explanation',
        ], nonempty: raw['correct'] == false);
        if (requireContext &&
            raw['correct'] == true &&
            (raw['corrections'] as List).isNotEmpty) {
          throw const FormatException('正确性判断与纠错列表不一致');
        }
        objects('structure', ['text', 'part', 'role'], nonempty: true);
        objects('grammar_points', [
          'title',
          'explanation',
        ], listKey: 'inflections');
      case AiAction.improve:
        string(raw, 'naturalness');
        objects('alternatives', [
          'text',
          'style',
          'translation',
          'explanation',
        ], nonempty: true);
    }
    return raw;
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'action': action.name,
    'data': data,
    'model': model,
    'createdAt': createdAt.toIso8601String(),
  };
  factory AnalysisResult.fromJson(Map<String, dynamic> j) {
    final action = AiAction.values.byName(j['action'] as String);
    return AnalysisResult(
      action: action,
      data: parse(
        action,
        jsonEncode(j['data']),
        requireContext: (j['schemaVersion'] as int? ?? 1) >= 2,
        schemaVersion: j['schemaVersion'] as int? ?? 1,
      ),
      schemaVersion: j['schemaVersion'] as int? ?? 1,
      model: j['model'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
    );
  }
}

class Sentence {
  Sentence({
    required this.id,
    required this.text,
    this.learningLanguage = '英语',
    this.learningVersion = 3,
    this.translationLanguage = '简体中文',
    required this.explanationLanguage,
    required this.level,
    required this.createdAt,
    Map<AiAction, AnalysisResult>? results,
  }) : results = results ?? {};
  final int learningVersion;
  final String id,
      text,
      learningLanguage,
      translationLanguage,
      explanationLanguage,
      level;
  final DateTime createdAt;
  final Map<AiAction, AnalysisResult> results;
  Map<String, dynamic> toJson() => {
    'learningVersion': learningVersion,
    'translationLanguage': translationLanguage,
    'id': id,
    'text': text,
    'learningLanguage': learningLanguage,
    'explanationLanguage': explanationLanguage,
    'level': level,
    'createdAt': createdAt.toIso8601String(),
    'results': results.values.map((e) => e.toJson()).toList(),
  };
  factory Sentence.fromJson(Map<String, dynamic> j) {
    final results = (j['results'] as List).map(
      (e) => AnalysisResult.fromJson(e as Map<String, dynamic>),
    );
    return Sentence(
      id: j['id'] as String,
      text: j['text'] as String,
      learningVersion: j['learningVersion'] as int? ?? 1,
      translationLanguage:
          j['translationLanguage'] as String? ??
          j['targetLanguage'] as String? ??
          '简体中文',
      learningLanguage: j['learningLanguage'] as String? ?? '英语',
      explanationLanguage:
          (j['explanationLanguage'] ?? j['targetLanguage']) as String,
      level: j['level'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      results: {for (final r in results) r.action: r},
    );
  }
}

// Normalize UI labels and model-returned language codes for direction checks.
String languageCode(String value) => switch (value.trim().toLowerCase()) {
  '英语' || 'english' || 'en' || 'en-us' || 'en-gb' => 'en',
  '简体中文' ||
  '繁體中文' ||
  '中文' ||
  'chinese' ||
  'zh' ||
  'zh-cn' ||
  'zh-tw' ||
  'zh-hans' ||
  'zh-hant' => 'zh',
  '日语' || '日本語' || 'japanese' || 'ja' => 'ja',
  '韩语' || '한국어' || 'korean' || 'ko' => 'ko',
  '法语' || 'french' || 'fr' => 'fr',
  '德语' || 'german' || 'de' => 'de',
  '西班牙语' || 'spanish' || 'es' => 'es',
  '意大利语' || 'italian' || 'it' => 'it',
  '葡萄牙语' || 'portuguese' || 'pt' => 'pt',
  '俄语' || 'russian' || 'ru' => 'ru',
  '希腊语' || 'greek' || 'el' || 'el-gr' || 'ελληνικά' => 'el',
  '阿拉伯语' || 'arabic' || 'ar' => 'ar',
  '泰语' || 'thai' || 'th' => 'th',
  '越南语' || 'vietnamese' || 'vi' => 'vi',
  _ => value.trim().toLowerCase(),
};

const translationLanguages = ['英语', '日语', '俄语', '希腊语'];
