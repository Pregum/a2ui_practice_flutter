import 'package:flutter_test/flutter_test.dart';

import 'package:a2ui_support_demo/core/a2ui/component/a2ui_component.dart';
import 'package:a2ui_support_demo/core/a2ui/parser/jsonl_stream_parser.dart';
import 'package:a2ui_support_demo/core/a2ui/state/surface.dart';
import 'package:a2ui_support_demo/core/a2ui/state/surface_store.dart';
import 'package:a2ui_support_demo/core/a2ui/validation/a2ui_validator.dart';
import 'package:a2ui_support_demo/core/llm/mock_llm.dart';
import 'package:a2ui_support_demo/core/llm/prompt/repair_prompt.dart';
import 'package:a2ui_support_demo/core/llm/prompt/system_prompt.dart';

/// Mock の出力を流し込んで active サーフェスを得る。
Future<Surface> _render(String prompt) async {
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
  return store.active!;
}

void main() {
  const validator = A2uiValidator();

  test('正常なサーフェスは検証を通る', () async {
    final errors = validator.validate(await _render('請求の問い合わせ'));
    expect(errors, isEmpty);
  });

  test('root が無いと MISSING_ROOT', () {
    final s = Surface(surfaceId: 's', catalogId: 'c')
      ..upsertComponents([
        const A2uiComponent(id: 'x', type: 'Text', props: {'text': 'hi'}),
      ]);
    final errors = validator.validate(s);
    expect(errors.map((e) => e.code), contains('MISSING_ROOT'));
  });

  test('壊れたデモ出力はカタログ外と未定義参照を検出する', () async {
    final errors = validator.validate(await _render('自己修正デモ'));
    final codes = errors.map((e) => e.code).toSet();
    expect(codes, contains('UNKNOWN_COMPONENT')); // note: Callout
    expect(codes, contains('UNDEFINED_REF')); // root → actions 未定義
  });

  test('自己修正ループ: 壊れた出力 → repair → 検証OK', () async {
    // 1回目: 壊れた出力
    final broken = await _render('自己修正デモ');
    final errors = validator.validate(broken);
    expect(errors, isNotEmpty);

    // repair プロンプトを生成して再投入
    final repairPrompt = buildRepairPrompt(errors, broken.surfaceId);
    final fixed = await _render(repairPrompt);

    // 2回目: 検証を通る
    expect(validator.validate(fixed), isEmpty);
    expect(fixed.components.containsKey('actions'), isTrue);
    expect(fixed.components['note']!.type, 'Text');
  });
}
