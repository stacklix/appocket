import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/models.dart';
import '../core/api.dart';
import '../core/stream_preview.dart';
import '../main.dart';

class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.action,
    required this.result,
    required this.loading,
    this.progress = '',
    this.phase,
    this.compact = false,
    required this.error,
    required this.onRun,
  });
  final AiAction action;
  final AnalysisResult? result;
  final bool loading;
  final bool compact;
  final String progress;
  final AnalysisPhase? phase;
  final String? error;
  final VoidCallback? onRun;
  @override
  Widget build(BuildContext context) {
    if (result == null && !loading && error == null) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 12 : 24),
        border: Border.all(color: const Color(0xFFE5E9E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  action.label,
                  style: TextStyle(
                    fontSize: compact ? 16 : 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (result != null)
                const Icon(
                  Icons.check_circle,
                  size: 19,
                  color: Color(0xFF5D8161),
                )
              else
                const Text(
                  '请求失败',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: Color(0xFFAD4F3D))),
            TextButton(
              onPressed: loading ? null : onRun,
              child: const Text('重试'),
            ),
          ],
          if (loading) ...[
            Text(switch (phase) {
              AnalysisPhase.thinking => '模型正在思考…',
              AnalysisPhase.receiving => '正在接收内容…',
              AnalysisPhase.nonStreaming => '服务正在返回完整结果…',
              AnalysisPhase.connecting => '正在等待模型响应…',
              null => '正在生成…',
            }, style: const TextStyle(color: muted)),
            if (partialResult(progress).isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._content(partialResult(progress)),
            ],
          ],
          if (result != null && !loading) ...[
            if (phase == AnalysisPhase.nonStreaming)
              const Text(
                '服务返回了完整响应，未逐段发送内容。',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            if (result!.schemaVersion < 3)
              const Text(
                '旧版结果 · 使用生成时的分析规则',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ..._content(result!.data),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    result!.model,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: _copyText(result!)),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('结果已复制')));
                    }
                  },
                  child: const Text('复制'),
                ),
                TextButton(
                  onPressed: loading ? null : onRun,
                  child: const Text('重新生成'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _copyText(AnalysisResult r) {
    final d = r.data;
    switch (r.action) {
      case AiAction.translate:
        return [
          if (d['translation_language'] is String)
            '${d['source_language'] ?? ''} → ${d['translation_language']}',
          ...(d['translations'] as List).map(
            (v) => '${_label(v['type'])}：${v['text']}',
          ),
          ...(d['notes'] as List),
        ].join('\n\n');
      case AiAction.grammar:
        return [
          if (d['analysis_text'] is String)
            '${d['analysis_origin'] == 'translation' ? '分析对象（根据原意生成的译文）' : '分析对象（用户原句）'}：${d['analysis_text']}',
          d['summary'],
          ...(d['corrections'] as List).map(
            (v) => '${v['original']} → ${v['corrected']}\n${v['explanation']}',
          ),
          ...(d['structure'] as List).map(
            (v) => '${v['text']} · ${v['part']} · ${v['role']}',
          ),
          ...(d['grammar_points'] as List).map(
            (v) =>
                '${v['title']}\n${v['explanation']}\n${(v['inflections'] as List).join(' → ')}',
          ),
        ].join('\n\n');
      case AiAction.improve:
        return [
          if (d['reference_text'] is String)
            '${d['reference_origin'] == 'translation' ? '参考译文' : '原句'}：${d['reference_text']}',
          if (d['input_in_learning_language'] != false) d['naturalness'],
          ...(d['alternatives'] as List).map(
            (v) =>
                '${_label(v['style'])}：${v['text']}\n${v['translation']}\n${v['explanation']}',
          ),
        ].join('\n\n');
    }
  }

  String _label(String value) =>
      const {
        '': '表达',
        'direct': '直译',
        'natural': '更地道的说法',
        'contextual': '根据语境',
        'conversational': '更口语',
        'polite': '更委婉 / 礼貌',
        'formal': '更正式',
      }[value] ??
      value;
  Widget _caption(String text) => Padding(
    padding: EdgeInsets.only(top: compact ? 10 : 16, bottom: compact ? 4 : 7),
    child: Text(
      text,
      style: const TextStyle(
        color: muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  Widget _copyCaption(String label, String text) => Row(
    children: [
      Expanded(child: _caption(label)),
      Builder(
        builder: (context) => IconButton(
          tooltip: '复制$label',
          onPressed: text.isEmpty
              ? null
              : () async {
                  try {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('文本已复制')));
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('复制失败，请重试')));
                    }
                  }
                },
          icon: const Icon(Icons.copy_outlined, size: 18),
        ),
      ),
    ],
  );

  List<Widget> _content(Map<String, dynamic> raw) {
    // Normalize only the presentation snapshot; missing fields stay empty.
    final d = <String, dynamic>{...raw};
    for (final field in ['summary', 'naturalness']) {
      d[field] = raw[field] is String ? raw[field] : '';
    }
    for (final field in [
      'translations',
      'corrections',
      'structure',
      'grammar_points',
      'alternatives',
    ]) {
      d[field] = [
        for (final item in (raw[field] is List ? raw[field] as List : const []))
          if (item is Map)
            <String, dynamic>{
              for (final key in [
                'type',
                'style',
                'text',
                'original',
                'corrected',
                'explanation',
                'part',
                'role',
                'title',
                'translation',
              ])
                key: item[key] is String ? item[key] : '',
              'inflections': item['inflections'] is List
                  ? (item['inflections'] as List).whereType<String>().toList()
                  : <String>[],
            },
      ];
    }
    d['notes'] = raw['notes'] is List
        ? (raw['notes'] as List).whereType<String>().toList()
        : <String>[];
    switch (action) {
      case AiAction.translate:
        return [
          if (d['translation_language'] is String)
            Text(
              '${d['source_language'] ?? ''} → ${d['translation_language']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          for (final v in d['translations']) ...[
            _copyCaption(_label(v['type'] as String), v['text'] as String),
            Text(
              v['text'] as String,
              style: TextStyle(fontSize: compact ? 17 : 21, height: 1.5),
            ),
          ],
          for (final note in d['notes'])
            Padding(
              padding: EdgeInsets.only(top: compact ? 10 : 18),
              child: Text(note as String),
            ),
        ];
      case AiAction.grammar:
        return [
          if (d['analysis_text'] is String) ...[
            _caption(
              d['analysis_origin'] == 'translation'
                  ? '分析对象 · 根据原意生成的译文'
                  : '分析对象 · 用户原句',
            ),
            Text(
              d['analysis_text'] as String,
              style: const TextStyle(fontSize: 19, height: 1.5),
            ),
            if (d['analysis_origin'] == 'translation')
              const Text(
                '以下解释针对生成的译文，不是对输入原文的纠错。',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            const SizedBox(height: 16),
          ],
          if (d['correct'] == false) ...[
            Text(
              '发现语法错误 · ${(d['corrections'] as List).length} 处',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          if ((d['summary'] as String).isNotEmpty) Text(d['summary'] as String),
          for (final v in d['corrections']) ...[
            _caption('错误与修改'),
            Text(
              '原文：${v['original']}',
              style: const TextStyle(color: Color(0xFFAD4F3D)),
            ),
            Text(
              '改为：${v['corrected']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(v['explanation'] as String),
          ],
          _caption('句子结构'),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(2.3),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder.all(color: const Color(0xFFE3E7DD)),
            children: [
              TableRow(
                decoration: const BoxDecoration(color: paper),
                children: [
                  for (final label in ['原文', '词性', '句中作用'])
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: muted,
                        ),
                      ),
                    ),
                ],
              ),
              for (final v in d['structure'])
                TableRow(
                  children: [
                    for (final field in ['text', 'part', 'role'])
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        child: Text(
                          v[field] as String,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            fontWeight: field == 'text'
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          for (final v in d['grammar_points']) ...[
            _caption(v['title'] as String),
            Text(v['explanation'] as String),
            if ((v['inflections'] as List).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  (v['inflections'] as List).join('\n↓\n'),
                  style: const TextStyle(height: 1.7),
                ),
              ),
          ],
        ];
      case AiAction.improve:
        return [
          if (d['reference_text'] is String) ...[
            _caption(
              d['reference_origin'] == 'translation' ? '参考译文 · 根据原意生成' : '原句',
            ),
            Text(
              d['reference_text'] as String,
              style: const TextStyle(fontSize: 19, height: 1.5),
            ),
            const SizedBox(height: 12),
          ],
          if (d['input_in_learning_language'] == false)
            const Text('根据你想表达的意思，给出不同场景的说法。')
          else
            Text(
              d['naturalness'] == '' ? '' : '自然度：${d['naturalness']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          for (final v in d['alternatives']) ...[
            _copyCaption(_label(v['style'] as String), v['text'] as String),
            Text(
              v['text'] as String,
              style: const TextStyle(fontSize: 19, height: 1.5),
            ),
            Text(
              v['translation'] as String,
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 8),
            Text(v['explanation'] as String),
          ],
        ];
    }
  }
}
