# On-Device LLM × A2UI — Flutter デモ

**クラウドに一切つながず、端末内の小型LLMが「UI そのもの」を生成して操作可能にする** Flutter デモ。

LLM の出力を *文章* ではなく **A2UI v0.9 プロトコルの JSON（操作可能なUI記述）** として受け取り、
その場で実 Flutter ウィジェットに描画します。題材は **カスタマーサポート対応コンソール**。

> 勉強会発表用に作成。オンデバイス推論（[`flutter_gemma`](https://pub.dev/packages/flutter_gemma) /
> Gemma 3n・Qwen 等）への差し替えを前提に、LLM とレンダラーを疎結合に設計しています。

---

## 何がうれしいか

| | |
|---|---|
| ✈️ **オフライン** | 機内モードのまま動く（プライバシー / 低レイテンシ / オフライン耐性） |
| 🧩 **A2UI** | LLM の出力が *操作可能なUI* になる（Agent-to-UI） |
| ⚡ **progressive rendering** | `root` が届いた時点で描画開始。生成が遅い端末ほど体感が活きる |
| 🔌 **差し替え可能なLLM** | `MockLlm`（どの端末でも即動く）↔ 実機推論をインターフェースで切替 |

## デモの流れ

```
自然言語の要望 → 端末内LLM → A2UI JSONL（ストリーム）→ パース → 検証 → 描画 → 操作
```

プリセット要望（請求の問い合わせ / 解約の申し出 / ログイン障害）をワンタップで切り替えると、
要望ごとに異なるサポート対応画面が組み上がります。

## 動かし方

```bash
flutter pub get
flutter run -d macos      # デスクトップで Mock LLM 動作（実機・モデル不要）
flutter test              # コア + レンダラーのテスト
```

> 現状の LLM は `MockLlm`（用意済みシナリオの JSONL を再生）。実機オンデバイス推論
> （`flutter_gemma`）は `FlutterGemmaLlm` として後続で実装予定（→ [ロードマップ](#ロードマップ)）。

発表スライド（外部依存なし・オフライン動作の単体HTML）:

```bash
open docs/slides.html
```

## アーキテクチャ

![architecture](docs/architecture.svg)

中心思想は **LLM とレンダラーを疎結合に**すること。重く環境依存な LLM 側を
`LlmBackend` インターフェースの裏に隠し、レンダラー側はどの端末でも・Mock でも動かせます。

詳細は [`docs/design.md`](docs/design.md)、図のソースは [`docs/architecture.drawio`](docs/architecture.drawio)。

### ディレクトリ構成

```
lib/
  core/a2ui/        A2UI コア（LLM 非依存）
    message/        4種メッセージ（createSurface / updateComponents / updateDataModel / deleteSurface）
    component/      コンポーネント（隣接リスト = フラット配列 + id 参照）
    parser/         streaming JSONL パーサ（部分行を確定・非JSON行をスキップ）
    state/          JSON Pointer データモデル / Surface / SurfaceStore
  core/llm/         LlmBackend（差替可）+ MockLlm + プロンプト資産
  ui/renderer/      隣接リスト → Flutter ウィジェット木（循環参照・未定義ID・深さガード）
  ui/screen/        デモ画面（入力 / プリセット / 生成速度 / progressive描画 / ログ）
docs/               設計ドキュメント・発表スライド・アーキテクチャ図
test/               DataModel / パーサ / Mock統合 / レンダラー描画
```

## A2UI プロトコル（v0.9・要約）

- **JSONL**（1行 = 1メッセージ）。各メッセージはトップレベルキー1つで判別。
- コンポーネントは **フラット配列**で、親子は **id 参照**（隣接リスト）。`root` が必ず1つ。
- 動的値は **JSON Pointer**（`{"path":"/reply/draft"}`）で参照し、`updateDataModel` で実データを別送。

```jsonc
{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"https://example.com/catalog/support"}}
{"version":"v0.9","updateComponents":{"surfaceId":"s","components":[
  {"id":"root","component":"Column","children":["header","reply"]},
  {"id":"header","component":"InquiryHeader","customer":"…","subject":"…","status":"open","priority":"high"},
  {"id":"reply","component":"ReplyBox","value":{"path":"/reply/draft"}}
]}}
{"version":"v0.9","updateDataModel":{"surfaceId":"s","path":"/reply/draft","value":"…"}}
```

### カタログ（`support`）

basic カタログを「自社デザインシステム」に差し替えた例。`catalogId` を独自URIにし、
コンポーネント定義を専用のものへ置き換えています。

- レイアウト: `Column` / `Row` / `Card` / `Text`
- サポート専用: `InquiryHeader` / `CustomerProfileCard` / `ConversationThread` /
  `StatusBadge` / `PriorityTag` / `SlaIndicator` / `KnowledgeSuggestion` /
  `CannedResponsePicker` / `ReplyBox` / `QuickActions`

## ロードマップ

- [x] A2UI コア（メッセージ / 隣接リスト / streaming パーサ / JSON Pointer）
- [x] レンダラー + `support` 独自カタログ + `MockLlm`（macOS で動作）
- [x] プリセット要望 / 複数シナリオ / progressive 演出 / オフライン演出
- [ ] **実機オンデバイス推論**（`flutter_gemma`・Android・機内モード実演）
- [ ] Validator + 自己修正ループ（不正JSON → repair プロンプト）
- [ ] 制約付きデコード（GBNF）で小型モデルの JSON 破綻を抑制

## ライセンス / 補足

- A2UI は v0.9（draft）。本リポジトリはプロトコルの**一例の実装**です。
- 登場する顧客名・ドメイン（`example.com` 等）はすべてダミーです。
