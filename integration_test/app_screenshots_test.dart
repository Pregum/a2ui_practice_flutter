import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:a2ui_support_demo/main.dart' as app;

/// 実機でアプリを操作し、各状態のスクリーンショットを撮る。
/// 手作業のタップに頼らず Flutter の finder で操作するため再現性が高い。
///
/// 注意: TextField のカーソル点滅で pumpAndSettle が settle しないため、
/// pump + 実時間 delay でフレームを進める。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('スライド用スクリーンショットを撮る', (tester) async {
    app.main();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
    }

    // 生成（ストリーム＋遅延）と _Appear アニメの完了まで、実際にフレームを
    // 回す（pump ループ）。Future.delayed だけだと描画が進まず opacity0 のまま。
    Future<void> shoot(String name) async {
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 200)); // 約10秒ぶん
      }
      await binding.takeScreenshot(name);
    }

    Future<void> tapText(String t) async {
      await tester.tap(find.text(t).first);
      await tester.pump(const Duration(milliseconds: 400));
    }

    // タップして数秒ぶんフレームを回す（生成完了を待つ・撮影はしない）。
    Future<void> tapThenWait(String t, {int frames = 22}) async {
      await tester.tap(find.text(t).first);
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    // ログを畳んで「生成された画面」をすっきり見せる。
    await tester.tap(find.byTooltip('ストリームログ'));
    await tester.pump(const Duration(milliseconds: 300));

    await tapText('請求の問い合わせ');
    await shoot('01-billing');

    await tapText('ログイン障害');
    await shoot('02-incident');

    // 自己修正デモ（ログを開いてループを見せる）
    await tester.tap(find.byTooltip('ストリームログ'));
    await tester.pump(const Duration(milliseconds: 300));
    await tapText('自己修正デモ');
    await shoot('03-selfheal');

    // ④ タップ作文（多段フロー → テキスト＋画像のマルチモーダル）
    await tester.tap(find.byTooltip('ストリームログ')); // ログを畳む
    await tester.pump(const Duration(milliseconds: 300));
    await tapThenWait('タップ作文'); // step0（候補チップ）
    await tapThenWait('お詫びして返信'); // 下書き
    await tapThenWait('これで送る'); // 確定（テキスト＋画像）
    await shoot('04-compose');

    // ⑤ proactive 仮眠UI
    await tapThenWait('働きすぎ検知');
    await shoot('05-nap');
  }, timeout: const Timeout(Duration(seconds: 300)));
}
