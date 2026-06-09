import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/a2ui/parser/jsonl_stream_parser.dart';
import '../../core/a2ui/state/surface_store.dart';
import '../../core/a2ui/validation/a2ui_validator.dart';
import '../../core/a2ui/validation/validation_error.dart';
import '../../core/llm/flutter_gemma_llm.dart';
import '../../core/llm/gemma_config.dart';
import '../../core/llm/llm_backend.dart';
import '../../core/llm/mock_llm.dart';
import '../../core/llm/prompt/repair_prompt.dart';
import '../../core/llm/prompt/system_prompt.dart';
import '../renderer/a2ui_renderer.dart';

/// プリセットの要望（チップで素早く切替）。
class _Preset {
  const _Preset(this.label, this.icon, this.prompt);
  final String label;
  final IconData icon;
  final String prompt;
}

const List<_Preset> _presets = [
  _Preset('請求の問い合わせ', Icons.receipt_long_outlined,
      '問い合わせ #4821（請求が二重）の対応画面を出して'),
  _Preset('解約の申し出', Icons.exit_to_app_outlined, '解約したいという問い合わせの対応画面を出して'),
  _Preset('ログイン障害', Icons.bug_report_outlined, 'ログインできない不具合の対応画面を出して'),
  _Preset('自己修正デモ', Icons.auto_fix_high_outlined, '自己修正デモ：壊れたUIを生成して'),
];

/// 生成速度プリセット（progressive rendering の演出用）。
class _Speed {
  const _Speed(this.label, this.delay);
  final String label;
  final Duration delay;
}

const List<_Speed> _speeds = [
  _Speed('遅い端末', Duration(milliseconds: 55)),
  _Speed('標準', Duration(milliseconds: 22)),
  _Speed('高速', Duration(milliseconds: 6)),
];

/// デモ画面。要望入力 → LLM 生成 → JSONL パース → 描画 → ログ可視化。
class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  static const int _maxRepairs = 2;

  final SurfaceStore _store = SurfaceStore();
  final MockLlm _mock = MockLlm();
  final A2uiValidator _validator = const A2uiValidator();
  final TextEditingController _input =
      TextEditingController(text: _presets.first.prompt);

  /// 現在のバックエンド（Mock ↔ 実機 Gemma を切替）。
  late LlmBackend _llm = _mock;
  FlutterGemmaLlm? _gemma;

  bool _generating = false;
  bool _showLog = true;
  int _speedIndex = 1; // 標準

  @override
  void initState() {
    super.initState();
    _mock.warmup();
  }

  @override
  void dispose() {
    _input.dispose();
    _store.dispose();
    super.dispose();
  }

  /// 生成 → 検証 →（失敗なら）自己修正 のループ。
  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    _store.reset();

    // 速度プリセットを Mock に反映（実機LLMでは無視される）。
    final llm = _llm;
    if (llm is MockLlm) llm.delay = _speeds[_speedIndex].delay;

    try {
      var prompt = _input.text;
      for (var attempt = 0; attempt <= _maxRepairs; attempt++) {
        if (attempt == 0) {
          _store.addLog(LogKind.info, '▶ 生成開始（端末内LLM: ${_llm.name}）');
        } else {
          _store.clearSurfaces();
          _store.addLog(LogKind.info, '↻ 自己修正 試行 $attempt / $_maxRepairs');
        }

        await _stream(prompt);

        // 検証
        final surface = _store.active;
        if (surface == null) {
          _store.addLog(LogKind.error, '✗ NO_SURFACE  サーフェスが生成されませんでした');
          return;
        }
        final List<ValidationError> errors = _validator.validate(surface);
        if (errors.isEmpty) {
          _store.addLog(LogKind.info, '✔ 検証OK・生成完了');
          return;
        }

        for (final e in errors) {
          _store.addLog(LogKind.error, '✗ ${e.code}  ${e.path}  ${e.message}');
        }
        if (attempt == _maxRepairs) {
          _store.addLog(LogKind.error, '⚠ 上限到達。自己修正を打ち切りました');
          return;
        }
        // repair プロンプトを次の入力にする
        prompt = buildRepairPrompt(errors, surface.surfaceId);
        _store.addLog(LogKind.skip, '→ repair プロンプトを LLM に差し戻し');
      }
    } catch (e) {
      _store.addLog(LogKind.error, 'エラー: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 1回ぶんの生成ストリームをパースして適用する。
  Future<void> _stream(String prompt) async {
    final parser = JsonlStreamParser();
    final stream = _llm.generate(system: supportSystemPrompt, user: prompt);
    await for (final chunk in stream) {
      for (final line in parser.feed(chunk)) {
        _consume(line);
      }
    }
    for (final line in parser.flush()) {
      _consume(line);
    }
  }

  void _consume(ParsedLine line) {
    if (line.ok) {
      _store.apply(line.message!);
    } else {
      _store.addLog(LogKind.skip, 'skip: ${line.note}  «${line.raw}»');
    }
  }

  void _onEvent(String name, Map<String, dynamic> ctx) {
    _store.addLog(LogKind.event, 'event: $name  $ctx');
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('イベント発火: $name  $ctx'),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ===== LLM バックエンド切替（Mock ↔ 実機 Gemma）=====
  void _useMock() => setState(() => _llm = _mock);

  Future<void> _useGemma() async {
    if (!GemmaConfig.isConfigured) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text(
              'HUGGINGFACE_TOKEN が未設定です。--dart-define=HUGGINGFACE_TOKEN=hf_xxx を付けて起動してください'),
        ));
      return;
    }
    final gemma = _gemma ??= FlutterGemmaLlm(
      modelUrl: GemmaConfig.modelUrl,
      hfToken: GemmaConfig.hfToken,
      displayName: GemmaConfig.displayName,
    );
    setState(() => _llm = gemma);
    if (gemma.isReady) return;

    final nav = Navigator.of(context, rootNavigator: true);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('オンデバイスLLMを準備中'),
        content: ValueListenableBuilder<String>(
          valueListenable: gemma.phase,
          builder: (_, phase, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: gemma.downloadProgress,
                builder: (_, p, _) =>
                    LinearProgressIndicator(value: p > 0 ? p / 100 : null),
              ),
              const SizedBox(height: 14),
              Text(phase),
              const SizedBox(height: 4),
              const Text('初回はモデルDL（数GB）で数分かかります',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    ));
    try {
      await gemma.warmup();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Gemma 初期化エラー: $e')));
        _useMock(); // 失敗時は Mock に戻す
      }
    } finally {
      nav.pop();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('A2UI サポートコンソール', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'ストリームログ',
            icon: Icon(_showLog ? Icons.terminal : Icons.terminal_outlined),
            onPressed: () => setState(() => _showLog = !_showLog),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _controlBar(),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 広い画面（デスクトップ）は左右分割、狭い画面（スマホ）は上下分割。
                final wide = constraints.maxWidth >= 720;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _surfaceArea()),
                      if (_showLog) ...[
                        const VerticalDivider(width: 1),
                        SizedBox(width: 360, child: _logPanel()),
                      ],
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(flex: 3, child: _surfaceArea()),
                    if (_showLog) ...[
                      const Divider(height: 1),
                      Expanded(flex: 2, child: _logPanel()),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ===== オフライン / 端末内バッジ =====
  Widget _offlineBadge() {
    Widget pill(IconData icon, String text, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withValues(alpha: 0.5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
            Text(text,
                style: TextStyle(
                    fontSize: 11.5, color: c, fontWeight: FontWeight.w600)),
          ]),
        );
    return Wrap(spacing: 6, runSpacing: 6, children: [
      pill(Icons.flight, 'オフライン', Colors.green),
      pill(Icons.smartphone, '端末内LLM: ${_llm.name}', Colors.blue),
    ]);
  }

  /// Mock ↔ 実機 Gemma の切替。
  Widget _backendToggle() {
    final usingGemma = _llm is FlutterGemmaLlm;
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(value: false, label: Text('Mock')),
        ButtonSegment(value: true, label: Text('Gemma')),
      ],
      selected: {usingGemma},
      onSelectionChanged: _generating
          ? null
          : (s) => s.first ? _useGemma() : _useMock(),
    );
  }

  // ===== 上部コントロール（入力 / プリセット / 速度）=====
  Widget _controlBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  onSubmitted: (_) => _generate(),
                  decoration: const InputDecoration(
                    labelText: '要望（自然言語）',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.chat_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_generating ? '生成中…' : 'UI を生成'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [_offlineBadge(), _backendToggle()],
          ),
          const SizedBox(height: 10),
          // プリセット要望 + 速度を一括で Wrap（狭い画面でも折り返してオーバーフローしない）
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final p in _presets)
                ActionChip(
                  avatar: Icon(p.icon, size: 16),
                  label: Text(p.label),
                  onPressed: _generating
                      ? null
                      : () {
                          _input.text = p.prompt;
                          _generate();
                        },
                ),
              _speedControl(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _speedControl() {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.speed, size: 16, color: Colors.grey.shade600),
      const SizedBox(width: 6),
      Text('速度', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      const SizedBox(width: 6),
      SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: [
          for (var i = 0; i < _speeds.length; i++)
            ButtonSegment(value: i, label: Text(_speeds[i].label)),
        ],
        selected: {_speedIndex},
        onSelectionChanged: _generating
            ? null
            : (s) => setState(() => _speedIndex = s.first),
      ),
    ]);
  }

  // ===== 生成された画面（端末枠で囲う）=====
  Widget _surfaceArea() {
    return Container(
      color: const Color(0xFFeef1f5),
      child: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final surface = _store.active;
          if (surface == null) return _emptyState();
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _deviceFrame(
                  child: A2uiRenderer(
                    surface: surface,
                    store: _store,
                    onEvent: _onEvent,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _deviceFrame({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFd5dae2), width: 8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ステータスバー風のヘッダ
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFf3f5f8),
            child: Row(
              children: [
                Icon(Icons.smartphone, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('端末画面 ・ A2UI レンダリング',
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ),
                const Spacer(),
                Icon(Icons.flight, size: 13, color: Colors.green.shade600),
                const SizedBox(width: 4),
                Text('オフライン',
                    style: TextStyle(
                        fontSize: 11.5, color: Colors.green.shade700)),
              ],
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          Text('プリセットを選ぶか「UI を生成」を押すと、\n'
              '端末内LLMが A2UI を吐いて画面が組み上がります',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.5)),
        ],
      ),
    );
  }

  // ===== ストリームログ =====
  Widget _logPanel() {
    return Container(
      color: const Color(0xFF0d1117),
      child: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final log = _store.log;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text('A2UI ストリーム ログ',
                    style: TextStyle(
                        color: Colors.grey.shade400,
                        fontFamily: 'monospace',
                        fontSize: 12)),
              ),
              const Divider(height: 1, color: Color(0xFF30363d)),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: log.length,
                  itemBuilder: (context, i) => _logLine(log[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _logLine(LogEntry e) {
    final color = switch (e.kind) {
      LogKind.message => const Color(0xFF58a6ff),
      LogKind.data => const Color(0xFF3fb950),
      LogKind.skip => const Color(0xFFd29922),
      LogKind.error => const Color(0xFFf85149),
      LogKind.event => const Color(0xFFf778ba),
      LogKind.info => const Color(0xFF8b949e),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        e.text,
        style: TextStyle(
            color: color, fontFamily: 'monospace', fontSize: 11.5, height: 1.4),
      ),
    );
  }
}
