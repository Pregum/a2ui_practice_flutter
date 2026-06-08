import 'package:flutter/material.dart';

import '../../core/a2ui/parser/jsonl_stream_parser.dart';
import '../../core/a2ui/state/surface_store.dart';
import '../../core/llm/llm_backend.dart';
import '../../core/llm/mock_llm.dart';
import '../../core/llm/prompt/system_prompt.dart';
import '../renderer/a2ui_renderer.dart';

/// デモ画面。要望入力 → LLM 生成 → JSONL パース → 描画 → ログ可視化。
class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  final SurfaceStore _store = SurfaceStore();
  final LlmBackend _llm = MockLlm();
  final TextEditingController _input =
      TextEditingController(text: '問い合わせ #4821 の対応画面を出して');

  bool _generating = false;
  bool _showLog = true;

  @override
  void initState() {
    super.initState();
    _llm.warmup();
  }

  @override
  void dispose() {
    _input.dispose();
    _store.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    _store.reset();
    _store.addLog(LogKind.info, '▶ 生成開始（${_llm.name}）');

    final parser = JsonlStreamParser();
    try {
      final stream = _llm.generate(
        system: supportSystemPrompt,
        user: _input.text,
      );
      await for (final chunk in stream) {
        for (final line in parser.feed(chunk)) {
          _consume(line);
        }
      }
      for (final line in parser.flush()) {
        _consume(line);
      }
      _store.addLog(LogKind.info, '✔ 生成完了');
    } catch (e) {
      _store.addLog(LogKind.error, 'エラー: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('オンデバイスLLM × A2UI  —  サポートコンソール'),
        actions: [
          IconButton(
            tooltip: 'ログ表示',
            icon: Icon(_showLog ? Icons.terminal : Icons.terminal_outlined),
            onPressed: () => setState(() => _showLog = !_showLog),
          ),
        ],
      ),
      body: Column(
        children: [
          _inputBar(),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _surfaceArea()),
                if (_showLog) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(width: 360, child: _logPanel()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
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
    );
  }

  Widget _surfaceArea() {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final surface = _store.active;
        if (surface == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined,
                    size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text('「UI を生成」を押すと、端末内LLMが\nA2UI を吐いて画面が組み上がります',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: A2uiRenderer(
              surface: surface,
              store: _store,
              onEvent: _onEvent,
            ),
          ),
        );
      },
    );
  }

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
