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

    test('JSON の途中に改行が入っても波括弧対応で復元する', () {
      // 小型モデルが1つの updateComponents を複数行に割って出すケース。
      final p = JsonlStreamParser();
      final results = <ParsedLine>[
        ...p.feed('{"version":"v0.9",\n'),
        ...p.feed('  "updateComponents":{"surfaceId":"s",\n'),
        ...p.feed('    "components":[{"id":"root","component":"Column",'
            '"children":[]}]}}\n'),
        ...p.flush(),
      ];
      expect(results.single.ok, isTrue);
    });

    test('同一行に複数オブジェクトが並んでも分割される', () {
      final p = JsonlStreamParser();
      final results = <ParsedLine>[
        ...p.feed('{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"c"}}'
            '{"version":"v0.9","deleteSurface":{"surfaceId":"s"}}'),
        ...p.flush(),
      ];
      expect(results.where((r) => r.ok).length, 2);
    });

    test('末尾の閉じ括弧転置を自動修復する（実機 Gemma の実例）', () {
      // Gemma 4 E2B が実機で出した壊れ方: 末尾が ]}} ではなく }]} になる。
      final p = JsonlStreamParser();
      final results = <ParsedLine>[
        ...p.feed('{"version":"v0.9","updateComponents":{"surfaceId":"s1",'
            '"components":[{"id":"root","component":"Column",'
            '"children":["a"]},{"id":"a","component":"QuickActions",'
            '"actions":[{"label":"確認","name":"view"}]}}]}\n'),
        ...p.flush(),
      ];
      expect(results.single.ok, isTrue);
      expect(results.single.note, '閉じ括弧を自動修復');
    });

    test('トークン切れで閉じ残した JSON は flush で補完される', () {
      final p = JsonlStreamParser();
      final results = <ParsedLine>[
        ...p.feed('{"version":"v0.9","createSurface":{"surfaceId":"s",'
            '"catalogId":"c"'),
        ...p.flush(),
      ];
      expect(results.single.ok, isTrue);
    });

    test('文字列内の波括弧と改行で誤分割しない', () {
      final p = JsonlStreamParser();
      final results = <ParsedLine>[
        ...p.feed('{"version":"v0.9","createSurface":'
            '{"surfaceId":"s{１}","catalogId":"c}"}}\n'),
        ...p.flush(),
      ];
      expect(results.single.ok, isTrue);
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
