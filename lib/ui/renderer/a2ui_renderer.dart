import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/a2ui/component/a2ui_component.dart';
import '../../core/a2ui/state/surface.dart';
import '../../core/a2ui/state/surface_store.dart';
import 'data_binding.dart';

/// イベントハンドラ（Button/ReplyBox/QuickActions の発火先）。
typedef A2uiEventHandler = void Function(String name, Map<String, dynamic> ctx);

/// サーフェスを実 Flutter ウィジェット木に描画するレンダラー。
///
/// root から id 参照を辿って木を再構築する。未定義ID・循環参照・深いネストは
/// プレースホルダで安全に止める。
class A2uiRenderer extends StatelessWidget {
  const A2uiRenderer({
    super.key,
    required this.surface,
    required this.store,
    required this.onEvent,
  });

  final Surface surface;
  final SurfaceStore store;
  final A2uiEventHandler onEvent;

  @override
  Widget build(BuildContext context) {
    if (!surface.hasRoot) {
      return const _Hint('root 待ち… 画面を生成中');
    }
    final binding = DataBinding(surface.dataModel);
    // スクロールは呼び出し側に委ねる（端末枠側で SingleChildScrollView する）。
    return Padding(
      padding: const EdgeInsets.all(16),
      child: _build(context, 'root', binding, const {}, 0),
    );
  }

  Widget _build(BuildContext ctx, String id, DataBinding b, Set<String> seen,
      int depth) {
    if (depth > 64) return _error('ネストが深すぎます');
    if (seen.contains(id)) return _error('循環参照: $id');
    final c = surface.components[id];
    if (c == null) return _error('未定義のコンポーネント: $id');
    final v = {...seen, id};

    switch (c.type) {
      // ---- レイアウト ----
      case 'Column':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _gaps(
              c.childIds.map((cid) => _Appear(
                  key: ValueKey('ap_$cid'),
                  child: _build(ctx, cid, b, v, depth + 1))),
              vertical: true),
        );
      case 'Row':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: _gaps(
              c.childIds.map((cid) => Flexible(
                  child: _Appear(
                      key: ValueKey('ap_$cid'),
                      child: _build(ctx, cid, b, v, depth + 1)))),
              vertical: false),
        );
      case 'Card':
        final child = c.childId;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: child == null
                ? _error('Card に child がありません')
                : _build(ctx, child, b, v, depth + 1),
          ),
        );
      case 'Text':
        return _text(ctx, c, b);

      // ---- サポート専用カタログ ----
      case 'InquiryHeader':
        return _inquiryHeader(ctx, c, b);
      case 'CustomerProfileCard':
        return _profileCard(ctx, c, b);
      case 'ConversationThread':
        return _conversation(ctx, c, b);
      case 'StatusBadge':
        return _statusBadge(ctx, b.resolveString(c.props['status']));
      case 'PriorityTag':
        return _priorityTag(ctx, b.resolveString(c.props['priority']));
      case 'SlaIndicator':
        return _sla(ctx, c, b);
      case 'KnowledgeSuggestion':
        return _knowledge(ctx, c, b);
      case 'CannedResponsePicker':
        return _canned(ctx, c, b);
      case 'ReplyBox':
        return _replyBox(ctx, c, b);
      case 'QuickActions':
        return _quickActions(ctx, c, b);
      case 'Image':
        return _image(ctx, c, b);
      case 'SuggestionChips':
        return _suggestionChips(ctx, c, b);
      case 'RestTimer':
        return _RestTimer(
          key: ValueKey('timer_${c.id}'),
          seconds: (b.resolve(c.props['seconds']) as num?)?.toInt() ?? 300,
          label: b.resolveString(c.props['label']),
        );

      default:
        return _error('未知のコンポーネント: ${c.type}');
    }
  }

  // ============ レイアウト系 ============

  Widget _text(BuildContext ctx, A2uiComponent c, DataBinding b) {
    final t = Theme.of(ctx).textTheme;
    final variant = c.props['variant'] as String?;
    final style = switch (variant) {
      'h1' => t.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
      'h2' => t.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      'caption' => t.bodySmall?.copyWith(color: Colors.grey.shade600),
      _ => t.bodyMedium,
    };
    return Text(b.resolveString(c.props['text']), style: style);
  }

  // ============ サポート系 ============

  Widget _inquiryHeader(BuildContext ctx, A2uiComponent c, DataBinding b) {
    final t = Theme.of(ctx).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.resolveString(c.props['subject']),
                      style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('顧客: ${b.resolveString(c.props['customer'])}',
                      style: t.bodySmall?.copyWith(color: Colors.grey.shade600)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _statusBadge(ctx, b.resolveString(c.props['status'])),
                const SizedBox(height: 6),
                _priorityTag(ctx, b.resolveString(c.props['priority'])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCard(BuildContext ctx, A2uiComponent c, DataBinding b) {
    final t = Theme.of(ctx).textTheme;
    Widget kv(IconData icon, String v) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(v, style: t.bodySmall),
          ]),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 16,
                child: Text(b.resolveString(c.props['name']).characters.first),
              ),
              const SizedBox(width: 10),
              Text(b.resolveString(c.props['name']),
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 16, runSpacing: 2, children: [
              kv(Icons.workspace_premium_outlined,
                  'プラン: ${b.resolveString(c.props['plan'])}'),
              kv(Icons.event_outlined,
                  '登録: ${b.resolveString(c.props['since'])}'),
              kv(Icons.mail_outline, b.resolveString(c.props['email'])),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _conversation(BuildContext ctx, A2uiComponent c, DataBinding b) {
    final raw = b.resolve(c.props['messages']);
    final msgs = raw is List ? raw : const [];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('やり取り',
                style: Theme.of(ctx)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            for (final m in msgs.whereType<Map>()) _bubble(ctx, m),
          ],
        ),
      ),
    );
  }

  Widget _bubble(BuildContext ctx, Map m) {
    final isAgent = m['role'] == 'agent';
    final scheme = Theme.of(ctx).colorScheme;
    final bg = isAgent ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    return Align(
      alignment: isAgent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${m['text'] ?? ''}'),
            const SizedBox(height: 2),
            Text('${isAgent ? "担当" : "顧客"} ・ ${m['time'] ?? ''}',
                style: Theme.of(ctx)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey.shade600, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(BuildContext ctx, String status) {
    final (label, color) = switch (status) {
      'new' => ('新規', Colors.blue),
      'open' => ('対応中', Colors.orange),
      'pending' => ('保留', Colors.blueGrey),
      'solved' => ('解決済み', Colors.green),
      _ => (status.isEmpty ? '不明' : status, Colors.grey),
    };
    return _chip(label, color, filled: true);
  }

  Widget _priorityTag(BuildContext ctx, String priority) {
    final (label, color) = switch (priority) {
      'low' => ('優先度: 低', Colors.grey),
      'normal' => ('優先度: 中', Colors.blue),
      'high' => ('優先度: 高', Colors.orange),
      'urgent' => ('優先度: 緊急', Colors.red),
      _ => (priority.isEmpty ? '優先度: -' : priority, Colors.grey),
    };
    return _chip(label, color, filled: false);
  }

  Widget _sla(BuildContext ctx, A2uiComponent c, DataBinding b) {
    final level = b.resolveString(c.props['level']);
    final color = switch (level) {
      'over' => Colors.red,
      'warn' => Colors.orange,
      _ => Colors.green,
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.timer_outlined, size: 16, color: color),
      const SizedBox(width: 6),
      Text('SLA 残り ${b.resolveString(c.props['remaining'])}',
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _knowledge(BuildContext ctx, A2uiComponent c, DataBinding b) {
    final raw = b.resolve(c.props['items']);
    final items = raw is List ? raw : const [];
    return Card(
      margin: EdgeInsets.zero,
      color: Theme.of(ctx).colorScheme.tertiaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.lightbulb_outline, size: 18),
              const SizedBox(width: 6),
              Text('関連ナレッジ候補',
                  style: Theme.of(ctx)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            for (final item in items)
              InkWell(
                onTap: () => onEvent('openKnowledge', {'title': '$item'}),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    const Icon(Icons.article_outlined, size: 15),
                    const SizedBox(width: 6),
                    Expanded(child: Text('$item')),
                    const Icon(Icons.chevron_right, size: 16),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _canned(BuildContext ctx, A2uiComponent c, DataBinding b) {
    final path = b.pathOf(c.props['value']);
    final current = b.resolveString(c.props['value']);
    final options = (c.props['options'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('定型文',
            style: Theme.of(ctx)
                .textTheme
                .labelLarge
                ?.copyWith(color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options.whereType<Map>())
              ChoiceChip(
                label: Text('${o['label'] ?? ''}'),
                selected: current == '${o['value']}',
                onSelected: (_) {
                  if (path != null) {
                    store.setData(surface.surfaceId, path, '${o['value']}');
                  }
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _replyBox(BuildContext ctx, A2uiComponent c, DataBinding b) {
    final path = b.pathOf(c.props['value']);
    final value = b.resolveString(c.props['value']);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('返信',
                style: Theme.of(ctx)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            _BoundTextField(
              value: value,
              onChanged: (t) {
                if (path != null) store.setData(surface.surfaceId, path, t);
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                icon: const Icon(Icons.send, size: 18),
                label: const Text('送信'),
                onPressed: () {
                  final action = c.props['action'];
                  if (action is Map && action['event'] is Map) {
                    final ev = action['event'] as Map;
                    final ctxMap = b.resolveDeep(ev['context'] ?? {});
                    onEvent('${ev['name']}',
                        Map<String, dynamic>.from(ctxMap as Map));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActions(BuildContext ctx, A2uiComponent c, DataBinding b) {
    final actions = (c.props['actions'] as List?) ?? const [];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in actions.whereType<Map>())
          OutlinedButton(
            onPressed: () {
              final ctxMap = b.resolveDeep(a['context'] ?? {});
              onEvent('${a['name']}', Map<String, dynamic>.from(ctxMap as Map));
            },
            child: Text('${a['label'] ?? ''}'),
          ),
      ],
    );
  }

  // ============ マルチモーダル / 提案 ============

  /// 画像。asset（端末内）優先 → url → emoji ステッカーの順でフォールバック。
  /// オフライン前提なので、デモは asset / emoji を使う。
  Widget _image(BuildContext ctx, A2uiComponent c, DataBinding b) {
    final asset = b.resolveString(c.props['asset']);
    final url = b.resolveString(c.props['url']);
    final emoji = b.resolveString(c.props['emoji']);
    Widget inner;
    if (asset.isNotEmpty) {
      inner = Image.asset(asset,
          fit: BoxFit.cover, errorBuilder: (_, _, _) => _emojiTile('🖼️'));
    } else if (url.isNotEmpty) {
      inner = Image.network(url,
          fit: BoxFit.cover, errorBuilder: (_, _, _) => _emojiTile('🖼️'));
    } else {
      inner = _emojiTile(emoji.isEmpty ? '🖼️' : emoji);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(aspectRatio: 16 / 9, child: inner),
    );
  }

  Widget _emojiTile(String emoji) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFe8eefc), Color(0xFFf6e9ff)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 56))),
      );

  /// AI が出すタップ候補。タップで event を発火し、フローを次の surface へ進める。
  Widget _suggestionChips(BuildContext ctx, A2uiComponent c, DataBinding b) {
    final chips = (c.props['chips'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.auto_awesome, size: 16, color: Theme.of(ctx).colorScheme.primary),
          const SizedBox(width: 6),
          Text('AI 候補（タップで作成）',
              style: Theme.of(ctx)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final ch in chips.whereType<Map>())
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: Text('${ch['label'] ?? ''}'),
                onPressed: () {
                  final ctxMap = b.resolveDeep(ch['context'] ?? {});
                  onEvent('${ch['name']}',
                      Map<String, dynamic>.from(ctxMap as Map));
                },
              ),
          ],
        ),
      ],
    );
  }

  // ============ 小物 ============

  Widget _chip(String label, MaterialColor color, {required bool filled}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.shade100 : Colors.transparent,
        border: Border.all(color: color.shade400),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color.shade800,
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _error(String msg) => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.red.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.red),
          const SizedBox(width: 6),
          Flexible(child: Text(msg, style: const TextStyle(color: Colors.red))),
        ]),
      );

  List<Widget> _gaps(Iterable<Widget> children, {required bool vertical}) {
    final list = children.toList();
    final out = <Widget>[];
    for (var i = 0; i < list.length; i++) {
      out.add(list[i]);
      if (i != list.length - 1) {
        out.add(vertical
            ? const SizedBox(height: 10)
            : const SizedBox(width: 10));
      }
    }
    return out;
  }
}

/// バインド値（外部更新）と編集中のカーソルを両立させるテキスト入力。
class _BoundTextField extends StatefulWidget {
  const _BoundTextField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_BoundTextField> createState() => _BoundTextFieldState();
}

class _BoundTextFieldState extends State<_BoundTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  late String _lastExternal = widget.value;

  @override
  void didUpdateWidget(covariant _BoundTextField old) {
    super.didUpdateWidget(old);
    // 外部（LLM等）からの値変化のみ反映。ユーザー入力時は value==text なので無視。
    if (widget.value != _lastExternal && widget.value != _controller.text) {
      _controller.text = widget.value;
      _lastExternal = widget.value;
    } else {
      _lastExternal = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      minLines: 3,
      maxLines: 6,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        hintText: '返信を入力…',
      ),
      onChanged: widget.onChanged,
    );
  }
}

/// 休憩カウントダウン（proactive 仮眠UI 用）。実時間でカウントダウンする。
class _RestTimer extends StatefulWidget {
  const _RestTimer({super.key, required this.seconds, required this.label});
  final int seconds;
  final String label;

  @override
  State<_RestTimer> createState() => _RestTimerState();
}

class _RestTimerState extends State<_RestTimer> {
  late int _remaining = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remaining > 0) {
          _remaining--;
        } else {
          _timer?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _mmss {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final done = _remaining <= 0;
    final frac = widget.seconds == 0 ? 0.0 : _remaining / widget.seconds;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.secondaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: done ? 1 : frac,
                    strokeWidth: 5,
                  ),
                  Icon(done ? Icons.check : Icons.bedtime_outlined, size: 22),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label.isEmpty ? '休憩タイマー' : widget.label,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(done ? 'おつかれさまでした' : _mmss,
                      style: TextStyle(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontSize: done ? 18 : 30,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 初回マウント時に一度だけフェード+スライドで現れる。progressive rendering で
/// 「新しく届いたコンポーネントだけ」がアニメーションする（既存は再生しない）。
class _Appear extends StatefulWidget {
  const _Appear({super.key, required this.child});
  final Widget child;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// 描画前のヒント表示（root 到着までの一瞬）。
class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Flexible(
                child: Text(text, style: TextStyle(color: Colors.grey.shade600))),
          ],
        ),
      );
}
