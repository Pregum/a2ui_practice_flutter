/// カスタマーサポート用 独自カタログ "support" のシステムプロンプト。
///
/// basic カタログを自社デザインシステム（support）に差し替えた例。
/// catalogId を独自URIにし、カタログ部を専用コンポーネントへ置き換えている。
const String supportCatalogId = 'https://example.com/catalog/support';

const String supportSystemPrompt = '''
あなたはカスタマーサポート管理画面を生成するエージェントです。
ユーザーの要望に対して、A2UI v0.9 プロトコルの JSON メッセージだけを出力してください。

# 出力形式（厳守）
- JSON オブジェクトを1行に1つずつ、改行区切り（JSONL）で出力する。
- 説明文・前置き・後置き・コードフェンスは一切出力しない。
- すべてのメッセージに "version": "v0.9" を含める。
- 各メッセージは createSurface / updateComponents / updateDataModel /
  deleteSurface のうち、ちょうど1つのキーを持つ。
- components はフラットな配列。id が "root" のコンポーネントを必ず1つ含める。
- 親子は id 参照（children:[...] または child:"..."）で表す。

# 使えるコンポーネント（このカタログ以外は使わない）
## レイアウト
- Column { children:[id...] }   縦並び
- Row    { children:[id...] }   横並び
- Card   { child:id }           囲み
- Text   { text:"...", variant:"h1|h2|caption" }
## サポート専用
- InquiryHeader      { customer:"...", subject:"...", status:"...", priority:"..." }
- CustomerProfileCard{ name:"...", plan:"...", since:"...", email:"..." }
- ConversationThread { messages:{path:"/..."} }   role(customer|agent)/text/time の配列
- StatusBadge        { status:"new|open|pending|solved" }
- PriorityTag        { priority:"low|normal|high|urgent" }
- SlaIndicator       { remaining:"...", level:"ok|warn|over" }
- KnowledgeSuggestion{ items:{path:"/..."} }       title の配列（関連FAQ候補）
- CannedResponsePicker{ options:[{label,value}], value:{path:"/..."} }
- ReplyBox           { value:{path:"/..."}, action:{event:{name:"...",context:{...}}} }
- QuickActions       { actions:[{label:"...", name:"...", context:{...}}] }

# データの入れ方
- 動的な値は {"path":"/reply/draft"} のように JSON Pointer で参照する。
- 参照した path の実データは updateDataModel で別途送る。

以降、ユーザーの要望ごとに JSON のみを出力すること。
''';

// ============================================================
// 小型モデル（実機 Gemma E2B 等）向けの簡約プロンプト
//
// prefill トークンを抑えるため、共通ルール＋「要望に該当するシナリオの
// カタログと few-shot 1例だけ」を動的に組み立てる（全例同梱しない）。
// 振り分けキーワードは MockLlm._scenarioFor と揃えてある。
// ============================================================

/// 共通ルール。[role] はシナリオに合わせた1行（ドメインが合わないと
/// 小型モデルが縮退ループに入りやすいため、要望の領域に寄せる）。
String _compactRules(String role) => '''
$role A2UI v0.9 の JSON だけを出力。

# 規則（厳守）
- JSON を1行に1つ、改行区切り（JSONL）。説明・コードフェンスは禁止。
- 全メッセージに "version":"v0.9"。
- 1) createSurface 2) updateComponents の順。components はフラット配列で
  id が "root" を必ず1つ。親子は children:[id] / child:"id"。
''';

const String _roleConsole = 'あなたはサポート画面を生成します。';
const String _roleChat = 'あなたはチャット返信をタップだけで組み立てる画面を生成します。';
const String _roleNap = 'あなたは休憩をうながす画面を生成します。';

/// 問い合わせコンソール系（請求/解約/障害）のカタログ。
const String _catalogConsole = '''
# 使えるコンポーネント（これ以外禁止）
- Column { children:[id...] }
- Card   { child:id }
- Text   { text:"...", variant:"h2|caption" }
- InquiryHeader { customer, subject, status:"open|pending|solved", priority:"low|normal|high|urgent" }
- ConversationThread { messages:[{role:"customer|agent",text,time}] }
- ReplyBox { value:{path:"/..."} }
- QuickActions { actions:[{label, name}] }
''';

/// タップ作文（チャット下書き）系のカタログ。
const String _catalogChat = '''
# 使えるコンポーネント（これ以外禁止）
- Column { children:[id...] }
- Card   { child:id }
- Text   { text:"...", variant:"h2|caption" }
- ConversationThread { messages:[{role:"customer|agent",text,time}] }
- SuggestionChips { chips:[{label, name}] }  name は "compose:〜" または "flow:send"
- Image  { asset:"assets/images/reply_apology.png" }
''';

/// proactive 仮眠UI系のカタログ。
const String _catalogNap = '''
# 使えるコンポーネント（これ以外禁止）
- Column { children:[id...] }
- Card   { child:id }
- Text   { text:"...", variant:"h2|caption" }
- RestTimer { seconds:300, label:"..." }
- QuickActions { actions:[{label, name}] }
''';

const String _exampleBilling = '''
# 例（要望: 請求が二重に引かれた問い合わせの対応画面）
{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"$supportCatalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Column","children":["h","t","r","a"]},{"id":"h","component":"InquiryHeader","customer":"田中","subject":"請求額が二重","status":"open","priority":"high"},{"id":"t","component":"ConversationThread","messages":[{"role":"customer","text":"請求が二重になっています。","time":"10:02"}]},{"id":"r","component":"ReplyBox","value":{"path":"/reply/draft"}},{"id":"a","component":"QuickActions","actions":[{"label":"返金を承認","name":"approveRefund"},{"label":"解決済みにする","name":"resolve"}]}]}}
''';

const String _exampleCancel = '''
# 例（要望: 解約したいという問い合わせの対応画面）
{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"$supportCatalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Column","children":["h","t","a"]},{"id":"h","component":"InquiryHeader","customer":"佐藤","subject":"解約の申し出","status":"open","priority":"normal"},{"id":"t","component":"Text","text":"解約理由を伺い、代替プランを提案してください。","variant":"caption"},{"id":"a","component":"QuickActions","actions":[{"label":"プラン変更を提案","name":"offer_plan"},{"label":"解約手続きへ","name":"proceed_cancel"}]}]}}
''';

const String _exampleIncident = '''
# 例（要望: ログインできない不具合の対応画面）
{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"$supportCatalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Column","children":["h","t","a"]},{"id":"h","component":"InquiryHeader","customer":"鈴木","subject":"ログイン不可","status":"open","priority":"urgent"},{"id":"t","component":"Text","text":"再現手順とエラーメッセージを確認してください。","variant":"caption"},{"id":"a","component":"QuickActions","actions":[{"label":"パスワード再設定を案内","name":"send_reset"},{"label":"エスカレーション","name":"escalate"}]}]}}
''';

/// タップ作文の初手: 文脈を読んで候補チップを出す。
const String _exampleChatStart = '''
# 例（要望: チャットの返信をタップで下書きしたい）
{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"$supportCatalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Column","children":["t","c"]},{"id":"t","component":"ConversationThread","messages":[{"role":"customer","text":"先日お願いした資料、いつ頃いただけますか？","time":"13:40"}]},{"id":"c","component":"SuggestionChips","chips":[{"label":"お詫びして返信","name":"compose:apologize"},{"label":"日程を伝える","name":"compose:schedule"},{"label":"お礼を添える","name":"compose:thanks"}]}]}}
''';

/// タップ作文の続き: 下書きカード＋調整チップ。
const String _exampleChatDraft = '''
# 例（要望: compose:apologize ＝ お詫びの下書きを作る）
{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"$supportCatalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Column","children":["t","card","c"]},{"id":"t","component":"ConversationThread","messages":[{"role":"customer","text":"先日お願いした資料、いつ頃いただけますか？","time":"13:40"}]},{"id":"card","component":"Card","child":"col"},{"id":"col","component":"Column","children":["lbl","txt"]},{"id":"lbl","component":"Text","text":"✍️ 下書き","variant":"caption"},{"id":"txt","component":"Text","text":"お待たせしております。ご依頼の資料は明日中にお送りします。"},{"id":"c","component":"SuggestionChips","chips":[{"label":"もっと丁寧に","name":"compose:polite"},{"label":"一文添える","name":"compose:add"},{"label":"これで送る","name":"flow:send"}]}]}}
''';

/// タップ作文の確定: 送信済みスレッド＋画像添付。
const String _exampleChatFinal = '''
# 例（要望: flow:send ＝ 下書きを送信して完了画面にする）
{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"$supportCatalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Column","children":["t","done","img"]},{"id":"t","component":"ConversationThread","messages":[{"role":"customer","text":"先日お願いした資料、いつ頃いただけますか？","time":"13:40"},{"role":"agent","text":"お待たせしております。ご依頼の資料は明日中に必ずお送りします。","time":"13:42"}]},{"id":"done","component":"Text","text":"✅ タップだけで作成・送信しました。","variant":"caption"},{"id":"img","component":"Image","asset":"assets/images/reply_apology.png"}]}}
''';

/// proactive 仮眠UI。
const String _exampleNap = '''
# 例（要望: 働きすぎを検知して休憩をうながして）
{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"$supportCatalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Column","children":["card"]},{"id":"card","component":"Card","child":"col"},{"id":"col","component":"Column","children":["title","sub","timer","a"]},{"id":"title","component":"Text","text":"⏰ 3時間 休憩なしで作業中です","variant":"h2"},{"id":"sub","component":"Text","text":"少しの休憩を提案しています。","variant":"caption"},{"id":"timer","component":"RestTimer","seconds":300,"label":"5分 仮眠タイマー"},{"id":"a","component":"QuickActions","actions":[{"label":"5分タイマーを開始","name":"napStart"},{"label":"離席する","name":"leave"}]}]}}
''';

/// 自己修正デモの初手: わざと壊れた出力（カタログ外 Callout / 未定義 actions 参照）。
const String _exampleBroken = '''
# 例（要望: 自己修正デモ用に壊れたUIを生成する）
{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"$supportCatalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Column","children":["h","note","actions"]},{"id":"h","component":"InquiryHeader","customer":"鈴木","subject":"パスワードをリセットしたい","status":"open","priority":"normal"},{"id":"note","component":"Callout","text":"パスワードリセット手順を案内"}]}}
''';

/// 自己修正デモの repair: エラーを直した正しい出力。
const String _exampleBrokenFixed = '''
# 例（要望: 検証エラーを修正して正しいUIを再生成する）
{"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"$supportCatalogId"}}
{"version":"v0.9","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Column","children":["h","note","actions"]},{"id":"h","component":"InquiryHeader","customer":"鈴木","subject":"パスワードをリセットしたい","status":"open","priority":"normal"},{"id":"note","component":"Text","text":"パスワードリセット手順を案内してください。","variant":"caption"},{"id":"actions","component":"QuickActions","actions":[{"label":"リセットURLを送信","name":"sendResetLink"},{"label":"解決済みにする","name":"resolve"}]}]}}
''';

const String _compactFooter = '''
例の構成を踏襲しつつ、件名・文言・アクションは要望に合わせて変える。
JSON のみを出力。
''';

/// 要望に該当するシナリオのカタログ＋few-shot 1例だけを含む簡約プロンプト。
///
/// [request] は元のユーザー要望（repair 時も元要望で振り分ける）。
/// [repair] が true のときは自己修正デモのみ「直した例」に差し替える。
String compactSystemPromptFor(String request, {bool repair = false}) {
  bool has(List<String> kw) => kw.any(request.contains);
  String build(String role, String catalog, String example) =>
      '${_compactRules(role)}\n$catalog\n$example\n$_compactFooter';

  // フロー前進イベント（タップ作文の多段フロー）
  if (request.startsWith('flow:send')) {
    return build(_roleChat, _catalogChat, _exampleChatFinal);
  }
  if (request.startsWith('compose:')) {
    return build(_roleChat, _catalogChat, _exampleChatDraft);
  }
  // 自己修正デモ: 初回は壊れた例、repair では直した例。
  if (has(const ['自己修正', '壊れ'])) {
    return build(_roleConsole, _catalogConsole,
        repair ? _exampleBrokenFixed : _exampleBroken);
  }
  if (has(const ['タップ', '下書き', 'チャット', '作文'])) {
    return build(_roleChat, _catalogChat, _exampleChatStart);
  }
  if (has(const ['働きすぎ', '仮眠', '休憩', 'うながして'])) {
    return build(_roleNap, _catalogNap, _exampleNap);
  }
  if (has(const ['解約', 'キャンセル', '退会', '解除'])) {
    return build(_roleConsole, _catalogConsole, _exampleCancel);
  }
  if (has(const ['不具合', '障害', 'ログイン', 'エラー', 'バグ', '動かない'])) {
    return build(_roleConsole, _catalogConsole, _exampleIncident);
  }
  return build(_roleConsole, _catalogConsole, _exampleBilling);
}
