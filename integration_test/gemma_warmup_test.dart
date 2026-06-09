import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:a2ui_support_demo/core/llm/flutter_gemma_llm.dart';
import 'package:a2ui_support_demo/core/llm/gemma_config.dart';
import 'package:a2ui_support_demo/core/llm/prompt/system_prompt.dart';

/// 実機 Gemma を実際にダウンロード→ロード→1件生成して確認する。
/// 実行: flutter test integration_test/gemma_warmup_test.dart -d <device>
/// 初回は 2.4GB のDLで数分かかる（端末を点灯したまま）。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Gemma をDL・ロードして A2UI を1件生成する', (tester) async {
    final gemma = FlutterGemmaLlm(
      modelUrl: GemmaConfig.modelUrl,
      hfToken: GemmaConfig.tokenOrNull,
      displayName: GemmaConfig.displayName,
    );
    gemma.phase.addListener(() {
      debugPrint('[GEMMA] ${gemma.phase.value}  ${gemma.downloadProgress.value}%');
    });

    await tester.runAsync(() async {
      debugPrint('[GEMMA] URL=${GemmaConfig.modelUrl}');
      await gemma.warmup();
      debugPrint('[GEMMA] ready=${gemma.isReady}. 生成テスト開始…');

      final buf = StringBuffer();
      await for (final t in gemma.generate(
        system: supportSystemPromptCompact,
        user: '請求の問い合わせ #4821 の対応画面を出して',
      )) {
        buf.write(t);
        if (buf.length > 600) break;
      }
      debugPrint('[GEMMA OUTPUT >>>] ${buf.toString()}');
      debugPrint('[GEMMA OUTPUT <<<]');
    });

    expect(gemma.isReady, isTrue);
  }, timeout: const Timeout(Duration(minutes: 25)));
}
