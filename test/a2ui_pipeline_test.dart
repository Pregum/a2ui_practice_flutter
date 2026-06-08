import 'package:flutter_test/flutter_test.dart';

import 'package:a2ui_support_demo/core/a2ui/parser/jsonl_stream_parser.dart';
import 'package:a2ui_support_demo/core/a2ui/state/data_model.dart';
import 'package:a2ui_support_demo/core/a2ui/state/surface_store.dart';
import 'package:a2ui_support_demo/core/llm/mock_llm.dart';
import 'package:a2ui_support_demo/core/llm/prompt/system_prompt.dart';

void main() {
  group('DataModel (JSON Pointer)', () {
    test('set/get で入れ子を読み書きできる', () {
      final m = DataModel();
      m.set('/reply/draft', 'こんにちは');
      expect(m.get('/reply/draft'), 'こんにちは');
      expect(m.get('/reply'), {'draft': 'こんにちは'});
    });

    test('配列インデックスを辿れる', () {
      final m = DataModel();
      m.set('/items', ['a', 'b', 'c']);
      expect(m.get('/items/1'), 'b');
      expect(m.get('/items/9'), isNull);
    });
  });

  group('JsonlStreamParser', () {
    test('チャンク分割された行を確定して復元する', () {
      final p = JsonlStreamParser();
      final results = <ParsedLine>[];
      const jsonl =
          '{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"c"}}\n'
          '{"version":"v0.9","deleteSurface":{"surfaceId":"s"}}\n';
      // 5文字ずつ流し込む
      for (var i = 0; i < jsonl.length; i += 5) {
        final end = (i + 5).clamp(0, jsonl.length);
        results.addAll(p.feed(jsonl.substring(i, end)));
      }
      results.addAll(p.flush());
      expect(results.where((r) => r.ok).length, 2);
    });

    test('コードフェンス行はスキップされる', () {
      final p = JsonlStreamParser();
      final r = p.feed('```json\n');
      expect(r.single.ok, isFalse);
    });
  });

  group('Mock → パーサ → ストア の統合', () {
    test('サポートコンソールが描画可能な状態まで組み上がる', () async {
      final store = SurfaceStore();
      final llm = MockLlm(
          chunkSize: 7, delay: Duration.zero); // 高速・細切れでパーサを酷使
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

      final surface = store.active!;
      expect(surface.surfaceId, 'billing_console'); // '対応画面'→請求シナリオ(既定)
      expect(surface.hasRoot, isTrue);
      // root の children が最終的な7要素に更新されている
      expect(surface.components['root']!.childIds, contains('reply'));
      // データモデルにナレッジ候補と返信ドラフトが入っている
      expect(surface.dataModel.get('/knowledge/items'), isA<List>());
      expect(surface.dataModel.get('/reply/draft'), isNotEmpty);
      // 全コンポーネントが定義済み（未定義ID参照なし）
      for (final id in surface.components['root']!.childIds) {
        expect(surface.components.containsKey(id), isTrue, reason: '未定義: $id');
      }
    });

    test('キーワードでシナリオが切り替わる', () async {
      Future<String> surfaceIdFor(String prompt) async {
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
        return store.active!.surfaceId;
      }

      expect(await surfaceIdFor('解約したい'), 'cancel_console');
      expect(await surfaceIdFor('ログインできない不具合'), 'incident_console');
      expect(await surfaceIdFor('請求について'), 'billing_console');
    });
  });
}
