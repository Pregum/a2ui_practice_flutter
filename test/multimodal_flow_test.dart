import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a2ui_support_demo/core/a2ui/parser/jsonl_stream_parser.dart';
import 'package:a2ui_support_demo/core/a2ui/state/surface.dart';
import 'package:a2ui_support_demo/core/a2ui/state/surface_store.dart';
import 'package:a2ui_support_demo/core/a2ui/validation/a2ui_validator.dart';
import 'package:a2ui_support_demo/core/llm/mock_llm.dart';
import 'package:a2ui_support_demo/core/llm/prompt/system_prompt.dart';
import 'package:a2ui_support_demo/ui/renderer/a2ui_renderer.dart';

Future<SurfaceStore> _storeFor(String prompt) async {
  final store = SurfaceStore();
  final llm = MockLlm(chunkSize: 64, delay: Duration.zero);
  final parser = JsonlStreamParser();
  await for (final chunk
      in llm.generate(system: supportSystemPrompt, user: prompt)) {
    for (final line in parser.feed(chunk)) {
      if (line.ok) store.apply(line.message!);
    }
  }
  for (final line in parser.flush()) {
    if (line.ok) store.apply(line.message!);
  }
  return store;
}

Future<Surface> _render(String prompt) async => (await _storeFor(prompt)).active!;

void main() {
  const validator = A2uiValidator();

  test('タップ作文フローと仮眠のシナリオ分岐', () async {
    expect((await _render('返信を下書きしたい')).surfaceId, 'chat_compose');
    expect((await _render('compose:apologize')).surfaceId, 'chat_compose');
    expect((await _render('compose:polite')).surfaceId, 'chat_compose');
    expect((await _render('flow:send')).surfaceId, 'chat_compose');
    expect((await _render('働きすぎを検知して')).surfaceId, 'wellbeing');
  });

  test('新シナリオが全て検証を通る（未定義参照・カタログ外なし）', () async {
    for (final p in const [
      '下書き',
      'compose:apologize',
      'compose:polite',
      'flow:send',
      '働きすぎ',
    ]) {
      expect(validator.validate(await _render(p)), isEmpty, reason: p);
    }
  });

  testWidgets('候補チップが描画され、タップでイベントが発火する', (tester) async {
    final store = (await tester.runAsync(() => _storeFor('タップで下書き')))!;
    String? fired;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: A2uiRenderer(
          surface: store.active!,
          store: store,
          onEvent: (name, _) => fired = name,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('AI 候補（タップで作成）'), findsOneWidget);
    expect(find.text('お詫びして返信'), findsOneWidget);

    await tester.tap(find.text('お詫びして返信'));
    await tester.pump();
    expect(fired, 'compose:apologize');
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('仮眠UIにカウントダウンタイマーが描画される', (tester) async {
    final store = (await tester.runAsync(() => _storeFor('働きすぎ')))!;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: A2uiRenderer(
          surface: store.active!,
          store: store,
          onEvent: (_, _) {},
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('5分 仮眠タイマー'), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget); // RestTimer 初期表示
  }, timeout: const Timeout(Duration(seconds: 60)));
}
