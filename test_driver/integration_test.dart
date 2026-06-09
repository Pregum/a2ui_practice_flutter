import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// スクリーンショットをホスト側 screenshots/ に書き出すドライバ。
/// 実行: flutter drive \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/app_screenshots_test.dart -d DEVICE_ID
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('screenshots/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
