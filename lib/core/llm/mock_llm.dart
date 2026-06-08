import 'llm_backend.dart';

/// 開発・予備・デスクトップ用の Mock。実機LLMの代わりに、用意済みの
/// サポート対応コンソールの JSONL をチャンク分割でストリーム再生する。
///
/// 本物のトークン生成を模擬するため、小さなチャンク + 遅延で送出する。
/// → パーサの部分行処理と progressive rendering をそのまま検証できる。
class MockLlm implements LlmBackend {
  MockLlm({this.chunkSize = 18, this.delay = const Duration(milliseconds: 24)});

  final int chunkSize;
  final Duration delay;
  bool _ready = false;

  @override
  String get name => 'Mock';

  @override
  bool get isReady => _ready;

  @override
  Future<void> warmup() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _ready = true;
  }

  @override
  Stream<String> generate({
    required String system,
    required String user,
  }) async* {
    final jsonl = _scenarioFor(user).join('\n');
    for (var i = 0; i < jsonl.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, jsonl.length);
      yield jsonl.substring(i, end);
      await Future<void>.delayed(delay);
    }
  }

  /// 要望に応じたシナリオ。今はサポート対応コンソールの1本。
  List<String> _scenarioFor(String user) => _supportConsole;
}

/// 「問い合わせの対応画面を出して」想定の JSONL（1要素 = 1行）。
const List<String> _supportConsole = [
  // 1) 画面を作る
  '{"version":"v0.9","createSurface":{"surfaceId":"support_console","catalogId":"https://xtone.example/catalog/support"}}',

  // 2) まず骨格 + 見出し（root が来た時点で描画開始 = progressive）
  '{"version":"v0.9","updateComponents":{"surfaceId":"support_console","components":['
      '{"id":"root","component":"Column","children":["header","profile","thread"]},'
      '{"id":"header","component":"InquiryHeader","customer":"田中 太郎","subject":"請求額が二重になっている","status":"open","priority":"high"},'
      '{"id":"profile","component":"CustomerProfileCard","name":"田中 太郎","plan":"Business","since":"2023-04","email":"tanaka@example.com"},'
      '{"id":"thread","component":"ConversationThread","messages":{"path":"/conversation/messages"}}'
      ']}}',

  // 3) 会話データ
  '{"version":"v0.9","updateDataModel":{"surfaceId":"support_console","path":"/conversation/messages","value":['
      '{"role":"customer","text":"先月から請求額が二重になっています。確認してください。","time":"10:02"},'
      '{"role":"agent","text":"ご連絡ありがとうございます。確認いたします。","time":"10:15"},'
      '{"role":"customer","text":"急ぎで対応をお願いします。","time":"10:31"}'
      ']}}',

  // 4) 残りのUI（ナレッジ候補・定型文・返信欄・クイック操作）を追加
  '{"version":"v0.9","updateComponents":{"surfaceId":"support_console","components":['
      '{"id":"root","component":"Column","children":["header","profile","thread","knowledge","canned","reply","actions"]},'
      '{"id":"knowledge","component":"KnowledgeSuggestion","items":{"path":"/knowledge/items"}},'
      '{"id":"canned","component":"CannedResponsePicker","value":{"path":"/reply/canned"},"options":['
      '{"label":"二重請求の謝罪+調査開始","value":"dup_billing"},'
      '{"label":"返金手続き案内","value":"refund"},'
      '{"label":"エスカレーション連絡","value":"escalate"}]},'
      '{"id":"reply","component":"ReplyBox","value":{"path":"/reply/draft"},"action":{"event":{"name":"sendReply","context":{"draft":{"path":"/reply/draft"}}}}},'
      '{"id":"actions","component":"QuickActions","actions":['
      '{"label":"返金を承認","name":"approveRefund"},'
      '{"label":"エスカレーション","name":"escalate"},'
      '{"label":"解決済みにする","name":"resolve"}]}'
      ']}}',

  // 5) ナレッジ候補・返信ドラフトのデータ
  '{"version":"v0.9","updateDataModel":{"surfaceId":"support_console","path":"/knowledge/items","value":['
      '"二重請求が発生した場合の調査手順",'
      '"返金ポリシー（FAQ）",'
      '"請求サイクルの変更方法"]}}',
  '{"version":"v0.9","updateDataModel":{"surfaceId":"support_console","path":"/reply","value":{'
      '"draft":"田中様\\n\\nこの度はご不便をおかけし申し訳ございません。二重請求の件、確認したところ決済システムの重複登録が原因でした。本日中に重複分を返金いたします。",'
      '"canned":"dup_billing"}}}',
];
