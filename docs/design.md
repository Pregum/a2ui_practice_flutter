# オンデバイスLLM × A2UI デモ 設計ドキュメント

> 勉強会発表用 / 2026-06
> オンデバイス小型LLM（Gemma 3n / Qwen）に A2UI v0.9 JSON を生成させ、
> Flutter で実ウィジェットへ描画する **オフライン動作の A2UI デモ** の設計。

---

## 0. このデモで何を見せるか（1行）

**「クラウドに一切つながず、端末内のLLMが UI そのものを生成し、その場で操作可能な画面になる」** を実演する。

発表のキモは2つ:

1. **オフライン**（機内モードのままLLMが動く＝プライバシー/レイテンシ/オフライン耐性）
2. **A2UI**（LLMの出力が"文章"ではなく"操作可能なUI"になる＝Agent-to-UIの体験）

---

## 1. 全体アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                       Flutter App (Android)                   │
│                                                               │
│  ┌──────────────┐   prompt    ┌───────────────────────────┐  │
│  │  Demo Screen │ ──────────► │      LLM Layer (差替可)     │  │
│  │ (入力UI)     │             │  LlmBackend (interface)   │  │
│  │              │ ◄────────── │   ├ MockLlm (例を再生)     │  │
│  └──────┬───────┘  JSONL      │   └ FlutterGemmaLlm (実機) │  │
│         │          stream     └───────────────────────────┘  │
│         │                                                     │
│         ▼  (行ごと)                                           │
│  ┌──────────────────┐   messages   ┌──────────────────────┐  │
│  │  A2UI Parser     │ ───────────► │  Validator           │  │
│  │ (streaming JSONL)│              │ (root/参照/型 検査)   │  │
│  └──────────────────┘              └─────────┬────────────┘  │
│                                              │ OK / error     │
│                                              ▼                │
│  ┌──────────────────────────────┐   error → repair prompt    │
│  │  Surface Store (状態)         │ ──────► (LLMへ再投入)       │
│  │  ├ components (id→component)  │                            │
│  │  └ dataModel (JSON Pointer)  │                            │
│  └─────────────┬────────────────┘                            │
│                │ notify                                       │
│                ▼                                              │
│  ┌──────────────────────────────┐                            │
│  │  A2UI Renderer                │  root から木を解決して     │
│  │  component → Flutter Widget   │  実ウィジェットに描画       │
│  │  + データバインド + イベント   │  (progressive rendering)   │
│  └──────────────────────────────┘                            │
│                │ event (Button等)                            │
│                └───────► Action Dispatcher → 次のsurface生成  │
└─────────────────────────────────────────────────────────────┘
```

**設計の中心思想 = LLM とレンダラーを疎結合にする。**
重くて環境依存な LLM 側（数GBモデル・実機必須・初回ロード遅い）を `LlmBackend` インターフェースの裏に隠し、
デモで映えるレンダラー側はどの端末でも・Mock でも動くようにする。
→ 発表当日は「実機で実モデル」、開発・予備は「デスクトップで Mock」を切替えるだけ。

---

## 2. パッケージ構成

```
lib/
  main.dart
  app.dart                          # MaterialApp / DI 起点

  core/
    a2ui/
      message/
        a2ui_message.dart           # sealed: 4種のメッセージ
        create_surface.dart
        update_components.dart
        update_data_model.dart
        delete_surface.dart
      component/
        a2ui_component.dart         # id + type + props(Map)
        component_type.dart         # enum (basic 8種)
      parser/
        jsonl_stream_parser.dart    # token stream → 行 → message
        a2ui_decoder.dart           # JSON Map → A2uiMessage
      validation/
        a2ui_validator.dart         # root/参照/型/必須prop 検査
        validation_error.dart       # code/surfaceId/path/message
      state/
        surface.dart                # 1画面: components + dataModel
        surface_store.dart          # ChangeNotifier（複数surface保持）
        data_model.dart             # JSON Pointer get/set (RFC6901サブセット)

    llm/
      llm_backend.dart              # abstract: Stream<String> generate(...)
      mock_llm.dart                 # プロンプト例をそのままJSONLで流す
      flutter_gemma_llm.dart        # flutter_gemma 実装
      prompt/
        system_prompt.dart          # §1 のシステムプロンプト（定数）
        user_template.dart          # §2 差込テンプレート
        repair_prompt.dart          # §3 自己修正プロンプト

  ui/
    renderer/
      a2ui_renderer.dart            # surface → Widget（rootから再帰）
      component_builder.dart        # type別ビルダーの振分け
      builders/
        text_builder.dart
        image_builder.dart
        column_builder.dart
        row_builder.dart
        card_builder.dart
        button_builder.dart
        text_field_builder.dart
        choice_picker_builder.dart
      data_binding.dart             # {"path":"/.."} 解決ヘルパ
      action_dispatcher.dart        # event 受取り → ハンドラ
    screen/
      demo_screen.dart              # プロンプト入力 + surface描画 + ログ
```

---

## 3. A2UI プロトコル データモデル

### 3.1 メッセージ（4種・JSONL 1行1メッセージ）

```dart
sealed class A2uiMessage {
  final String version; // "v0.9"
}

class CreateSurface   { String surfaceId; String catalogId; }
class UpdateComponents { String surfaceId; List<A2uiComponent> components; }
class UpdateDataModel  { String surfaceId; String path; dynamic value; }
class DeleteSurface    { String surfaceId; }
```

判別ロジック: JSON オブジェクトのトップレベルキー（`createSurface` 等）ちょうど1つで分岐。

### 3.2 コンポーネント（隣接リスト = フラット配列 + id参照）

```dart
class A2uiComponent {
  String id;             // "root" が必ず1つ
  ComponentType type;    // Text/Image/Column/Row/Card/Button/TextField/ChoicePicker
  Map<String, dynamic> props; // 残りのフィールドをそのまま保持
}
```

親子は `props` 内の id 参照で表現:
- `Column/Row`: `"children": ["id1","id2"]`
- `Card`: `"child": "id"`
- `Button`: `"child": "<ラベルTextのid>"`

→ レンダラーは `Map<String, A2uiComponent>`（id→component）を引きながら木を再構築する。

### 3.3 データモデル（JSON Pointer）

- 動的値は props 内に `{"path":"/edit/style"}` の形で埋まる。
- 実データは `updateDataModel` が `path`(JSON Pointer) + `value` で別送。
- `data_model.dart` が RFC6901 サブセット（`/a/b/0` 程度）で get/set。

**値の解決ルール（レンダラー共通）:**
> ある prop の値が「`path` 1キーだけを持つ Map」なら dataModel から解決、
> それ以外はリテラルとして扱う。

---

## 4. コンポーネント → Flutter ウィジェット対応表（basic 8種）

| A2UI | props | Flutter | 備考 |
|---|---|---|---|
| `Text` | `text`, `variant`(h1/h2/caption…) | `Text` / `MarkdownBody` | variant→TextStyle。Markdown可なら `flutter_markdown` |
| `Image` | `url` | `Image.network` | プレースホルダ/エラー時フォールバック |
| `Column` | `children:[id…]` | `Column` | children を id解決して再帰描画 |
| `Row` | `children:[id…]` | `Row` | 同上。横溢れは `Wrap`/`SingleChildScrollView` も検討 |
| `Card` | `child:id` | `Card` | 単一子を囲む |
| `Button` | `child:id`, `variant`, `action.event` | `FilledButton`/`OutlinedButton` | variant→種別。押下で event 発火 |
| `TextField` | `label`, `value:{path}` | `TextField` | onChanged で dataModel に書戻し（双方向） |
| `ChoicePicker` | `variant:mutuallyExclusive`, `options:[{label,value}]`, `value:{path}` | `SegmentedButton`/`RadioListTile` | 選択値を dataModel に書戻し |

**双方向バインド**（TextField / ChoicePicker）:
ユーザー操作 → `path` の指す dataModel を更新 → Button の `action.context` から同 path を読んで event に同梱。

---

## 5. ストリーミング & progressive rendering

オンデバイス小型モデルは生成が遅い。これを**弱みではなく見せ場に変える**のが A2UI。

```
LLM token stream ──► [行バッファ] ──► 改行で確定 ──► JSON parse ──► message
                                                          │
                                  createSurface ──────────┼─► surface作成（空描画）
                                  updateComponents(root) ─┼─► 木を描画開始 ◄── ここで画面が"出る"
                                  updateComponents(...)  ─┼─► 追加分を埋める
                                  updateDataModel ────────┴─► 文言/値が"入る"
```

- パーサは**部分行を捨てない**: 改行が来るまでバッファし、完全な行だけ JSON 化。
- `SurfaceStore`（`ChangeNotifier`）が message ごとに notify → `AnimatedBuilder`/`ListenableBuilder` で再描画。
- root さえ来れば描画開始 → 「生成が遅い端末ほど progressive rendering が活きる」を実演できる。

---

## 6. バリデーション & 自己修正ループ

v0.9 は `prompt → generate → validate → (fail) → repair` 前提。

### 6.1 検査項目（`a2ui_validator.dart`）

| 失敗 | 検査 | 自己修正での指示 |
|---|---|---|
| root が無い | id=="root" のcomponentが1つ存在するか | 「id が root のコンポーネントを必ず1つ含める」 |
| 未定義idを参照 | children/child の参照先が全て定義済みか | 「children に書いた id は必ず定義する」 |
| カタログ外の型 | type が basic 8種に含まれるか | 「使えるコンポーネント一覧以外は禁止」 |
| 必須prop欠落 | 型ごとの必須フィールド有無 | 該当 path をエラーに含める |
| 余計な出力 | コードフェンス/前置き行が混在 | パーサが非JSON行をスキップ＋フラグ |

### 6.2 ループ

```
generate ──► parse ──► validate
                          │ OK    ──► render
                          │ FAIL  ──► repair_prompt(error) ──► generate（再）
                          └ リトライ上限2回で打止め → エラーUI表示
```

`validation_error.dart` は §3 のエラー形式（`code/surfaceId/path/message`）に対応。

---

## 7. LLM レイヤ（差替え可能）

```dart
abstract class LlmBackend {
  /// system+user を渡し、生成テキストを行/トークン単位でストリームする
  Stream<String> generate({required String system, required String user});
  Future<void> warmup();   // モデルロード（初回遅延を前倒し）
  bool get isReady;
}
```

### 7.1 MockLlm（開発・予備・デスクトップ）
- §1 のサンプル JSONL を一定間隔でチャンク送出（ストリーミングを模擬）。
- いくつかの要望→出力をテーブルで持ち、デモを LLM 無しで再現可能。

### 7.2 FlutterGemmaLlm（本番・Android実機）
- `flutter_gemma` で `.task`/`.gguf` モデルをロード。
- パラメータ: **temperature 0〜0.3**（構造安定優先）、topK 控えめ。
- 可能なら**制約付きデコード（GBNF / JSON grammar）**で構文を強制 → 壊れたJSONがほぼ消える（デモ安定の最大の効きどころ）。
- モデル候補: **Gemma 3n E2B/E4B**、または **Qwen2.5 0.5B/1.5B Instruct**。
- モデル配置: assets同梱は重いので、初回起動時に端末ストレージへDL or adb push 運用を想定。

---

## 8. 状態管理の方針

- 規模が小さいので **`ChangeNotifier` + `ListenableBuilder`** を基本線に推奨（依存ゼロ・発表で読みやすい）。
- Riverpod を使うなら `SurfaceStore` を `Notifier` 化。チームの既存方針があればそちらに合わせる。
- `SurfaceStore` の責務: surface群の保持 / messageの適用 / dataModelのget-set / notify。

---

## 9. イベント（Button action）

```
Button押下
  └─ action.event = { name, context }
       context 内の {"path":"/.."} を dataModel から解決
       └─ ActionDispatcher.dispatch(name, resolvedContext)
            ├ デモ: SnackBar/ログに表示（"generateVideo style=cinematic")
            └ 発展: name に応じて次の要望をLLMへ → 新surface生成（画面遷移の連鎖）
```

---

## 10. デモ画面（`demo_screen.dart`）構成

```
┌────────────────────────────┐
│  [要望入力欄] [生成ボタン]    │  ← 自然言語入力
├────────────────────────────┤
│                            │
│   生成された A2UI surface    │  ← レンダラー描画領域（progressive）
│                            │
├────────────────────────────┤
│  ▼ ログ (折りたたみ)         │  ← 受信JSONL / validation / event を可視化
└────────────────────────────┘
```

発表では下部ログを開いて「LLMが今こういうJSONを吐いている」を見せられると説得力が出る。

---

## 11. 実装マイルストーン（次セッション以降）

| # | 内容 | 完了条件 | 依存パッケージ |
|---|---|---|---|
| **M1** | A2UI モデル + パーサ + レンダラー + MockLlm | デスクトップで例の画面が描画・操作できる | （標準のみ） |
| **M2** | バリデーション + 自己修正ループ + dataModel双方向 | 不正JSONを投入→自己修正で復帰 | （標準のみ） |
| **M3** | flutter_gemma 統合（Android実機） | 機内モードで実モデルがJSONL生成→描画 | `flutter_gemma` |
| **M4**（発展） | 独自カタログ1種（EditStyleCard等） | 自社語彙のコンポーネントをLLMが組む | — |

> M1・M2 は LLM 不要で全部テスト可能（Mock）。**当日が実機トラブルでも Mock で完走できる**保険になる。

---

## 12. 主要リスクと対策

| リスク | 対策 |
|---|---|
| 実機モデルのロード遅延 / メモリ不足 | `warmup()` を起動時に。小型モデル(0.5B〜2B)優先。E2B等の量子化版 |
| 小型モデルがJSONを壊す | 制約付きデコード(GBNF) + temperature低 + パーサの堅牢化(部分行/非JSON無視) |
| children循環参照・深いネスト | 描画時に visited集合 + 深さ上限ガード |
| 当日ネットワーク/実機トラブル | MockLlm に即フォールバック（同一UI/同一フローで完走） |
| flutter_gemma の API/モデル形式差異 | M3着手時にバージョン固定し、対応モデル形式(.task等)を先に確定 |

---

## 13. 発表ストーリー（スライド対応）

1. 課題: LLM出力は"文章"止まり。操作可能UIにするには？ → **A2UI**
2. さらにクラウド依存をやめたい（プライバシー/オフライン/レイテンシ） → **オンデバイス**
3. デモ: 機内モードで自然言語 → 端末内LLM → JSONLストリーム → progressive描画 → 操作
4. 仕組み: 4種メッセージ / 隣接リスト / JSON Pointer / 自己修正ループ
5. 次の一手: basic カタログ → 自社デザインシステム(独自カタログ)に差替え

---

## 付録A. メッセージ JSON スキーマ（要約）

```jsonc
// createSurface
{"version":"v0.9","createSurface":{"surfaceId":"...","catalogId":"https://tomiees.com/catalog/basic"}}

// updateComponents（components はフラット配列・root必須）
{"version":"v0.9","updateComponents":{"surfaceId":"...","components":[
  {"id":"root","component":"Card","child":"col"},
  {"id":"col","component":"Column","children":["a","b"]},
  {"id":"a","component":"Text","text":"...","variant":"h2"}
]}}

// updateDataModel（path は JSON Pointer）
{"version":"v0.9","updateDataModel":{"surfaceId":"...","path":"/edit","value":{"style":"cinematic"}}}

// deleteSurface
{"version":"v0.9","deleteSurface":{"surfaceId":"..."}}
```

## 付録B. プロンプト資産の置き場所

- システムプロンプト → `lib/core/llm/prompt/system_prompt.dart`（§1 をそのまま定数化）
- 差込テンプレート → `user_template.dart`（§2）
- 自己修正 → `repair_prompt.dart`（§3）

→ プロンプトはコードと一緒にバージョン管理し、モデル差替え時の再現性を確保する。
