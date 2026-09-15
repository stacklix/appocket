import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../core/controller.dart';
import '../core/models.dart';
import '../main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.compact = false,
  });
  final AppController controller;
  final bool compact;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController url, model, token;
  late String language, level;
  late ApiProtocol protocol;
  bool obscured = true, saving = false;
  String? error;
  bool get compact => widget.compact;
  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    url = TextEditingController(text: s.baseUrl);
    model = TextEditingController(text: s.model);
    token = TextEditingController(text: s.token);
    protocol = s.protocol;
    language = s.explanationLanguage;
    level = s.level;
  }

  @override
  void dispose() {
    url.dispose();
    model.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final config = ApiSettings(
      protocol: protocol,
      baseUrl: url.text.trim(),
      model: model.text.trim(),
      token: token.text.trim(),
      translationLanguage: widget.controller.settings.translationLanguage,
      explanationLanguage: language,
      level: level,
    );
    final hasConnection =
        url.text.trim().isNotEmpty ||
        model.text.trim().isNotEmpty ||
        token.text.trim().isNotEmpty;
    final issue = hasConnection ? config.validationError : null;
    if (issue != null) {
      setState(() => error = issue);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.saveSettings(config);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          error = '安全存储写入失败，请重试。';
          saving = false;
        });
      }
    }
  }

  Widget field(
    String label,
    TextEditingController controller,
    String hint, {
    bool secret = false,
  }) => Padding(
    padding: EdgeInsets.only(bottom: compact ? 10 : 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        SizedBox(height: compact ? 4 : 8),
        TextField(
          controller: controller,
          style: TextStyle(fontSize: compact ? 14 : 17),
          obscureText: secret && obscured,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: secret
              ? TextInputType.visiblePassword
              : TextInputType.url,
          decoration: InputDecoration(
            isDense: compact,
            contentPadding: compact
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 11)
                : null,
            hintText: hint,
            suffixIcon: secret
                ? IconButton(
                    tooltip: obscured ? '显示 Token' : '隐藏 Token',
                    onPressed: () => setState(() => obscured = !obscured),
                    icon: Icon(
                      obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  )
                : null,
          ),
        ),
      ],
    ),
  );
  Widget saveButton() => FilledButton(
    onPressed: saving ? null : save,
    child: Padding(
      padding: EdgeInsets.all(compact ? 6 : 14),
      child: Text(saving ? '保存中…' : '保存设置'),
    ),
  );
  Widget removeButton() => TextButton(
    onPressed: saving
        ? null
        : () async {
            setState(() {
              saving = true;
              error = null;
            });
            try {
              await widget.controller.saveSettings(
                ApiSettings(
                  protocol: protocol,
                  baseUrl: url.text.trim(),
                  model: model.text.trim(),
                  translationLanguage:
                      widget.controller.settings.translationLanguage,
                  explanationLanguage: language,
                  level: level,
                ),
              );
              if (mounted) {
                token.clear();
                setState(() => saving = false);
              }
            } catch (_) {
              if (mounted) {
                setState(() {
                  saving = false;
                  error = '移除失败，请重试。';
                });
              }
            }
          },
    child: const Text('移除已保存的 Token'),
  );
  Widget languageField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('解释语言', style: TextStyle(fontWeight: FontWeight.w600)),
      SizedBox(height: compact ? 4 : 8),
      DropdownButtonFormField<String>(
        key: const Key('explanation-language'),
        initialValue: language,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: compact,
          contentPadding: compact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
              : null,
        ),
        style: TextStyle(fontSize: compact ? 14 : 17, color: ink),
        items: [
          '简体中文',
          '繁體中文',
          'English',
          '日本語',
        ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) => setState(() => language = v!),
      ),
    ],
  );
  Widget levelField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('学习水平', style: TextStyle(fontWeight: FontWeight.w600)),
      SizedBox(height: compact ? 4 : 8),
      DropdownButtonFormField<String>(
        initialValue: level,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: compact,
          contentPadding: compact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
              : null,
        ),
        style: TextStyle(fontSize: compact ? 14 : 17, color: ink),
        items: [
          '初级',
          '中级',
          '高级',
        ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) => setState(() => level = v!),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: compact ? 48 : null,
      automaticallyImplyLeading: !compact,
      title: Text(
        '连接与偏好',
        style: compact
            ? const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)
            : null,
      ),
      actions: compact
          ? [
              IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ]
          : null,
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              compact ? 20 : 24,
              compact ? 8 : 24,
              compact ? 20 : 24,
              compact ? 16 : 24,
            ),
            children: [
              if (!compact) ...[
                const Icon(Icons.tune_rounded, size: 38, color: ink),
                const SizedBox(height: 16),
                const Text(
                  '你的模型，你的学习空间。',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
              ],
              const Text(
                kIsWeb
                    ? '无需注册。句子直接发送给你配置的模型服务商。历史保存在当前浏览器，Token 仅保存在当前标签页会话中。服务商需允许此网页来源的跨域请求（CORS）。'
                    : '句子直连模型服务商，历史保存在本机，Token 保存在系统钥匙串。',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              SizedBox(height: compact ? 12 : 28),
              const Text('接口协议', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: compact ? 4 : 8),
              DropdownButtonFormField<ApiProtocol>(
                key: const Key('api-protocol'),
                initialValue: protocol,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: compact,
                  contentPadding: compact
                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                      : null,
                ),
                style: TextStyle(fontSize: compact ? 14 : 17, color: ink),
                items: ApiProtocol.values
                    .map(
                      (p) => DropdownMenuItem(value: p, child: Text(p.label)),
                    )
                    .toList(),
                onChanged: saving
                    ? null
                    : (p) => setState(() {
                        protocol = p!;
                        error = null;
                      }),
              ),
              SizedBox(height: compact ? 10 : 20),
              field('API Base URL', url, 'https://your-provider.com/v1'),
              Padding(
                padding: EdgeInsets.only(bottom: compact ? 10 : 20),
                child: Text(
                  protocol == ApiProtocol.anthropic
                      ? '填写服务商的基础地址，自动补齐 /v1/messages；也支持以 /v1 结尾或完整接口地址。模型名称和 Access Token 均使用该服务商提供的值。'
                      : '使用支持 Chat Completions 的 OpenAI 兼容服务；地址可包含 /v1，App 会追加 /chat/completions。',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
              field('模型名称', model, '填写服务商提供的模型 ID'),
              field('Access Token', token, '输入你的 API Token', secret: true),
              if (compact)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: languageField()),
                    const SizedBox(width: 12),
                    Expanded(child: levelField()),
                  ],
                )
              else ...[
                languageField(),
                const SizedBox(height: 20),
                levelField(),
              ],
              SizedBox(height: compact ? 14 : 24),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              if (compact)
                Row(children: [removeButton(), const Spacer(), saveButton()])
              else ...[
                saveButton(),
                const SizedBox(height: 16),
                removeButton(),
              ],
              const SizedBox(height: 12),
              const Text(
                '首次使用请从服务商获取 API Token。请求费用由服务商收取；更换模型后，已保存的结果仍可查看。',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
