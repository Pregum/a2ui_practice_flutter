import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a2ui_support_demo/core/a2ui/parser/jsonl_stream_parser.dart';
import 'package:a2ui_support_demo/core/a2ui/state/surface_store.dart';
import 'package:a2ui_support_demo/core/llm/mock_llm.dart';
import 'package:a2ui_support_demo/core/llm/prompt/system_prompt.dart';
import 'package:a2ui_support_demo/ui/renderer/a2ui_renderer.dart';

Future<SurfaceStore> _buildStore() async {
  final store = SurfaceStore();
  final llm = MockLlm(chunkSize: 9, delay: Duration.zero);
  final parser = JsonlStreamParser();
  await for (final chunk
      in llm.generate(system: supportSystemPrompt, user: '対応画面')) {
    for (final line in parser.feed(chunk)) {
      if (line.ok) store.apply(line.message!);
    }
  }
  for (final line in parser.flush()) {
    if (line.ok) store.apply(line.message!);
  }
  return store;
}

void main() {
  testWidgets('生成されたサポートコンソールが実ウィジェットに描画される',
      (WidgetTester tester) async {
    // 全コンポーネントが収まる広いビューポートにして、スクロール無しでタップする。
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Mock のストリーム遅延は実タイマー。testWidgets の fake-async では
    // pump しないと進まないため、runAsync 内で実時間を使って組み上げる。
    final store = (await tester.runAsync(_buildStore))!;
    String? firedEvent;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: A2uiRenderer(
          surface: store.active!,
          store: store,
          onEvent: (name, ctx) => firedEvent = name,
        ),
      ),
    ));
    // TextField のカーソル点滅で pumpAndSettle が settle しないため pump を使う。
    // _Appear のフェードイン（有限）を進めてから検証/タップする。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 専用カタログのコンポーネントが描画されている
    expect(find.text('請求額が二重になっている'), findsOneWidget); // InquiryHeader.subject
    expect(find.text('対応中'), findsOneWidget); // StatusBadge open
    expect(find.text('優先度: 高'), findsOneWidget); // PriorityTag high
    expect(find.text('関連ナレッジ候補'), findsOneWidget); // KnowledgeSuggestion
    expect(find.text('返信'), findsOneWidget); // ReplyBox

    // QuickActions のボタンを押すとイベントが発火する
    await tester.tap(find.text('解決済みにする'));
    await tester.pump();
    expect(firedEvent, 'resolve');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
