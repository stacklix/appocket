import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../main.dart';
import 'results.dart';
import 'settings.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final input = TextEditingController();
  final focus = FocusNode();
  final actionScroll = ScrollController();
  final resultAnchor = GlobalKey();
  bool showHistory = false;
  bool savingTarget = false;
  String search = '';
  AppController get app => widget.controller;
  AiAction get action => app.activeAction;
  String get explanationLanguage =>
      app.current?.explanationLanguage ?? app.settings.explanationLanguage;
  String get targetLanguage => app.current?.learningVersion == 3
      ? app.current!.translationLanguage
      : app.settings.translationLanguage;
  @override
  void initState() {
    super.initState();
    input.text = app.draft;
    app.addListener(sync);
  }

  void sync() {
    if (input.text != app.draft) {
      input.value = TextEditingValue(
        text: app.draft,
        selection: TextSelection.collapsed(offset: app.draft.length),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    app.removeListener(sync);
    input.dispose();
    focus.dispose();
    actionScroll.dispose();
    super.dispose();
  }

  bool get desktop =>
      MediaQuery.sizeOf(context).width >= 900 ||
      (!kIsWeb &&
          const {
            TargetPlatform.macOS,
            TargetPlatform.windows,
            TargetPlatform.linux,
          }.contains(defaultTargetPlatform));
  void settings() {
    if (desktop) {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 600,
            height: 640,
            child: SettingsPage(controller: app, compact: true),
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => SettingsPage(controller: app)),
      );
    }
  }

  void selectAction(int index) {
    focus.unfocus();
    setState(() => showHistory = false);
    app.switchAction(AiAction.values[index]);
  }

  void submitShortcut() {
    if (input.value.composing.isValid && !input.value.composing.isCollapsed) {
      return;
    }
    if (!showHistory &&
        app.draft.trim().isNotEmpty &&
        !app.busy(action) &&
        app.historyAvailable) {
      run();
    }
  }

  void run({bool force = false}) {
    focus.unfocus();
    if (!app.settings.ready) {
      settings();
      return;
    }
    final requestedAction = action;
    app.run(action, force: force);
    // Bring the result into view once; never pull the reader on every chunk.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          action == requestedAction &&
          !showHistory &&
          actionScroll.hasClients) {
        final target = resultAnchor.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            alignment: 0.1,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else {
          actionScroll.animateTo(
            actionScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  Future<void> changeTarget(String value) async {
    setState(() => savingTarget = true);
    try {
      await app.saveSettings(app.settings.withTranslationLanguage(value));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('目标语言保存失败，请重试。')));
      }
    } finally {
      if (mounted) setState(() => savingTarget = false);
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, meta: true):
          submitShortcut,
      const SingleActivator(LogicalKeyboardKey.enter, control: true):
          submitShortcut,
      const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () =>
          selectAction(0),
      const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () =>
          selectAction(1),
      const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () =>
          selectAction(2),
      const SingleActivator(LogicalKeyboardKey.comma, meta: true): settings,
    },
    child: Focus(
      autofocus: true,
      child: desktop ? desktopPage() : mobilePage(),
    ),
  );

  Widget desktopPage() => Scaffold(
    body: SafeArea(
      child: Row(
        children: [
          Container(
            key: const Key('desktop-sidebar'),
            width: 164,
            decoration: const BoxDecoration(
              color: Color(0xFFEEF1E8),
              border: Border(right: BorderSide(color: Color(0xFFE0E5DA))),
            ),
            padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 0, 20),
                    child: Text(
                      'sentra',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final a in AiAction.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        key: Key('desktop-${a.name}'),
                        selected: !showHistory && action == a,
                        selectedTileColor: const Color(0xFFDDE7D5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: Icon(switch (a) {
                          AiAction.translate => Icons.translate_rounded,
                          AiAction.grammar => Icons.account_tree_outlined,
                          AiAction.improve => Icons.auto_awesome_outlined,
                        }, size: 20),
                        title: Text(
                          a.label,
                          style: const TextStyle(fontSize: 14),
                        ),
                        onTap: () => selectAction(a.index),
                      ),
                    ),
                  const Divider(),
                  ListTile(
                    selected: showHistory,
                    selectedTileColor: const Color(0xFFDDE7D5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: const Icon(Icons.history_rounded, size: 20),
                    title: const Text('学习记录', style: TextStyle(fontSize: 14)),
                    onTap: () {
                      focus.unfocus();
                      setState(() => showHistory = true);
                    },
                  ),
                  const Spacer(),
                  ListTile(
                    horizontalTitleGap: 8,
                    minLeadingWidth: 20,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    leading: const Icon(Icons.tune_rounded, size: 20),
                    title: const Text('连接与偏好', style: TextStyle(fontSize: 12)),
                    onTap: settings,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '⌘ 1 / 2 / 3 切换工具',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: !app.initialized
                ? const Center(child: CircularProgressIndicator())
                : showHistory
                ? Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: historyPage(),
                    ),
                  )
                : desktopWorkspace(),
          ),
        ],
      ),
    ),
  );

  Widget desktopWorkspace() {
    if (MediaQuery.sizeOf(context).width < 1100) return actionPage();
    final hasResult =
        app.busy(action) ||
        app.error(action) != null ||
        app.current?.results[action] != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...headingWidgets(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    key: PageStorageKey('desktop-input-${action.name}'),
                    children: [
                      ...inputWidgets(),
                      const SizedBox(height: 10),
                      const Text(
                        'Enter 提交 · Shift+Enter 换行',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (hasResult) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: ListView(
                      key: PageStorageKey('desktop-result-${action.name}'),
                      children: resultWidgets(),
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget mobilePage() => Scaffold(
    appBar: AppBar(
      leading: showHistory
          ? IconButton(
              tooltip: '返回',
              onPressed: () => setState(() => showHistory = false),
              icon: const Icon(Icons.arrow_back),
            )
          : null,
      title: Text(
        showHistory ? '学习记录' : 'sentra',
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
      ),
      actions: [
        if (!showHistory)
          IconButton(
            tooltip: '学习记录',
            onPressed: () {
              focus.unfocus();
              setState(() => showHistory = true);
            },
            icon: const Icon(Icons.history_rounded),
          ),
        IconButton(
          tooltip: '连接与偏好',
          onPressed: settings,
          icon: const Icon(Icons.tune_rounded),
        ),
        const SizedBox(width: 10),
      ],
    ),
    body: !app.initialized
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: showHistory ? historyPage() : actionPage(),
              ),
            ),
          ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: action.index,
      onDestinationSelected: (value) {
        focus.unfocus();
        setState(() => showHistory = false);
        app.switchAction(AiAction.values[value]);
      },
      backgroundColor: paper,
      indicatorColor: const Color(0xFFE0E9D9),
      destinations: const [
        NavigationDestination(
          key: Key('tab-translate'),
          icon: Icon(Icons.translate_rounded),
          label: '翻译',
        ),
        NavigationDestination(
          key: Key('tab-grammar'),
          icon: Icon(Icons.account_tree_outlined),
          label: '语法',
        ),
        NavigationDestination(
          key: Key('tab-improve'),
          icon: Icon(Icons.auto_awesome_outlined),
          label: '更地道',
        ),
      ],
    ),
  );
  Widget actionPage() => ListView(
    controller: actionScroll,
    key: PageStorageKey(action),
    padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    children: [...headingWidgets(), ...inputWidgets(), ...resultWidgets()],
  );
  Widget targetPicker() => DropdownButtonFormField<String>(
    key: ValueKey('translation-target-$targetLanguage'),
    initialValue: targetLanguage,
    isExpanded: true,
    decoration: InputDecoration(
      isDense: desktop,
      contentPadding: desktop
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
          : null,
    ),
    items: {
      ...translationLanguages,
      targetLanguage,
    }.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
    onChanged: savingTarget ? null : (value) => changeTarget(value!),
  );

  List<Widget> headingWidgets() => desktop
      ? [
          Row(
            children: [
              Text(
                action == AiAction.grammar ? '语法分析' : action.label,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              if (action == AiAction.translate) ...[
                const Text('翻译成', style: TextStyle(fontSize: 12, color: muted)),
                const SizedBox(width: 8),
                SizedBox(width: 170, child: targetPicker()),
              ],
            ],
          ),
          const SizedBox(height: 16),
        ]
      : [
          Text(
            action.english,
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.7,
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            switch (action) {
              AiAction.translate => '让意思，跨越语言。',
              AiAction.grammar => '读懂句子的结构。',
              AiAction.improve => '找到更自然的说法。',
            },
            style: const TextStyle(
              fontSize: 30,
              height: 1.35,
              fontWeight: FontWeight.w500,
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 12),
          Text(switch (action) {
            AiAction.translate => '选择目标语言，先看直译，再看更地道的说法。',
            AiAction.grammar => '先检查并指出语法错误，再分析句子结构。',
            AiAction.improve => '保留原文语言和含义，比较不同语气与场景。',
          }, style: const TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 24),
        ];
  List<Widget> inputWidgets() => [
    if (app.notice != null)
      Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBD2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(app.notice!),
            if (app.historyAvailable)
              TextButton(onPressed: app.retrySave, child: const Text('重试保存')),
          ],
        ),
      ),
    if (action == AiAction.translate && !desktop) ...[
      const Text('翻译成', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      targetPicker(),
      const SizedBox(height: 20),
    ],
    Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(desktop ? 12 : 24),
        border: Border.all(color: const Color(0xFFDCE3D5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              desktop ? 14 : 20,
              desktop ? 12 : 18,
              desktop ? 14 : 20,
              0,
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              children: [
                const Text(
                  '原文 · 请求时识别语言',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                Text(
                  '解释：$explanationLanguage',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Focus(
            onKeyEvent: (_, event) {
              final enter =
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter;
              if (!enter || HardwareKeyboard.instance.isShiftPressed) {
                return KeyEventResult.ignored;
              }
              if (input.value.composing.isValid &&
                  !input.value.composing.isCollapsed) {
                return KeyEventResult.skipRemainingHandlers;
              }
              if (event is KeyDownEvent) submitShortcut();
              return KeyEventResult.handled;
            },
            child: TextField(
              key: const Key('sentence-input'),
              controller: input,
              focusNode: focus,
              onChanged: app.setDraft,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submitShortcut(),
              minLines: 4,
              maxLines: 8,
              maxLength: 4000,
              style: TextStyle(
                fontSize: desktop ? 16 : 22,
                height: desktop ? 1.5 : 1.65,
                color: ink,
              ),
              decoration: InputDecoration(
                hintText: switch (action) {
                  AiAction.translate => '输入要翻译的原文…',
                  AiAction.grammar => '输入要检查语法的句子…',
                  AiAction.improve => '输入想说得更自然的句子…',
                },
                hintStyle: const TextStyle(color: Color(0xFFAFB6AC)),
                fillColor: Colors.transparent,
                counterText: '',
                contentPadding: EdgeInsets.all(desktop ? 14 : 20),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              desktop ? 14 : 20,
              0,
              8,
              desktop ? 4 : 10,
            ),
            child: Row(
              children: [
                Text(
                  '${input.text.length} / 4000',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => app.setDraft(
                    action == AiAction.translate
                        ? '你好，很高兴认识你。'
                        : 'I go to the cinema yesterday.',
                  ),
                  child: const Text('试试例句'),
                ),
                IconButton(
                  tooltip: '清空当前输入',
                  onPressed: app.draft.isEmpty ? null : app.newSentence,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: desktop ? 156 : double.infinity,
        child: FilledButton.icon(
          key: const Key('run-action'),
          onPressed:
              app.draft.trim().isEmpty ||
                  app.busy(action) ||
                  !app.historyAvailable
              ? null
              : () => run(),
          icon: app.busy(action)
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.arrow_forward_rounded),
          label: Padding(
            padding: EdgeInsets.symmetric(vertical: desktop ? 6 : 14),
            child: Text(
              app.busy(action)
                  ? switch (action) {
                      AiAction.translate => '正在翻译…',
                      AiAction.grammar => '正在分析…',
                      AiAction.improve => '正在优化…',
                    }
                  : switch (action) {
                      AiAction.translate => '开始翻译',
                      AiAction.grammar => '检查并分析',
                      AiAction.improve => '优化表达',
                    },
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    ),
    if (!app.settings.ready)
      TextButton(onPressed: settings, child: const Text('连接你的 AI，开始使用')),
  ];
  List<Widget> resultWidgets() => [
    SizedBox(
      height: desktop ? (MediaQuery.sizeOf(context).width < 1100 ? 12 : 0) : 28,
    ),
    if (app.current != null && app.current!.learningVersion < 3)
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          '旧版记录 · 新请求将使用当前 Tab 的规则。',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ),
    ResultCard(
      key: resultAnchor,
      compact: desktop,
      action: action,
      result: app.current?.results[action],
      loading: app.busy(action),
      progress: app.progress(action),
      phase: app.phase(action),
      error: app.error(action),
      onRun: app.draft.trim().isEmpty || !app.historyAvailable
          ? null
          : () => run(force: true),
    ),
    const Text(
      '由 AI 辅助理解，具体表达仍需结合语境。',
      textAlign: TextAlign.center,
      style: TextStyle(color: muted, fontSize: 11),
    ),
  ];
  Widget historyPage() {
    final items = app.history
        .where((s) => s.text.toLowerCase().contains(search.toLowerCase()))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          '学过的每一句，\n都在这里。',
          style: TextStyle(
            fontSize: 30,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${app.history.length} 个句子 · 仅保存在本机',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 24),
        TextField(
          onChanged: (s) => setState(() => search = s),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '搜索句子',
          ),
        ),
        const SizedBox(height: 20),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                Icon(Icons.bookmark_border_rounded, size: 40, color: muted),
                SizedBox(height: 16),
                Text('还没有匹配的学习记录', style: TextStyle(color: muted)),
              ],
            ),
          ),
        for (final s in items)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
              title: Text(s.text, maxLines: 3, overflow: TextOverflow.ellipsis),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.results.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final a in AiAction.values)
                            if (s.results.containsKey(a))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF1E8),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  a.label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: ink,
                                  ),
                                ),
                              ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      '${s.createdAt.year}.${s.createdAt.month.toString().padLeft(2, '0')}.${s.createdAt.day.toString().padLeft(2, '0')} · ${s.learningVersion < 3 ? '旧版记录' : '解释：${s.explanationLanguage}'}',
                      style: const TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
              ),
              onTap: () {
                app.switchAction(
                  s.results.keys.firstOrNull ?? AiAction.translate,
                );
                app.open(s);
                setState(() => showHistory = false);
              },
              trailing: IconButton(
                tooltip: '删除句子',
                icon: const Icon(Icons.delete_outline, color: muted, size: 20),
                onPressed: () => app.delete(s),
              ),
            ),
          ),
      ],
    );
  }
}
