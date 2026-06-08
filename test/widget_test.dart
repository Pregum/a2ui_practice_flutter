import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a2ui_support_demo/main.dart';

void main() {
  testWidgets('デモ画面が起動し、生成ボタンが表示される', (WidgetTester tester) async {
    await tester.pumpWidget(const A2uiSupportDemoApp());
    expect(find.text('UI を生成'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    // warmup() の遅延タイマーを消化してから終了する
    await tester.pump(const Duration(milliseconds: 200));
  });
}
