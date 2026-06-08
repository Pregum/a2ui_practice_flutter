import 'llm_backend.dart';

/// 開発・予備・デスクトップ用の Mock。実機LLMの代わりに、用意済みの
/// サポート対応コンソールの JSONL をチャンク分割でストリーム再生する。
///
/// 本物のトークン生成を模擬するため、小さなチャンク + 遅延で送出する。
/// → パーサの部分行処理と progressive rendering をそのまま検証できる。
/// 要望のキーワードでシナリオ（請求 / 解約 / 障害）を切り替える。
class MockLlm implements LlmBackend {
  MockLlm({this.chunkSize = 18, this.delay = const Duration(milliseconds: 24)});

  final int chunkSize;

  /// チャンク間の遅延。デモの「生成速度スライダー」から動的に変更できる。
  Duration delay;

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

  /// 要望のキーワードでシナリオを選ぶ。
  List<String> _scenarioFor(String user) {
    bool has(List<String> kw) => kw.any(user.contains);
    if (has(const ['解約', 'キャンセル', '退会', '解除'])) return _cancelConsole;
    if (has(const ['不具合', '障害', 'ログインできない', 'エラー', 'バグ', '動かない'])) {
      return _incidentConsole;
    }
    return _billingConsole;
  }
}

/// シナリオ①：請求の二重課金（status=open / priority=high）
const List<String> _billingConsole = [
  '{"version":"v0.9","createSurface":{"surfaceId":"billing_console","catalogId":"https://example.com/catalog/support"}}',
  '{"version":"v0.9","updateComponents":{"surfaceId":"billing_console","components":['
      '{"id":"root","component":"Column","children":["header","profile","thread"]},'
      '{"id":"header","component":"InquiryHeader","customer":"田中 太郎","subject":"請求額が二重になっている","status":"open","priority":"high"},'
      '{"id":"profile","component":"CustomerProfileCard","name":"田中 太郎","plan":"Business","since":"2023-04","email":"tanaka@example.com"},'
      '{"id":"thread","component":"ConversationThread","messages":{"path":"/conversation/messages"}}'
      ']}}',
  '{"version":"v0.9","updateDataModel":{"surfaceId":"billing_console","path":"/conversation/messages","value":['
      '{"role":"customer","text":"先月から請求額が二重になっています。確認してください。","time":"10:02"},'
      '{"role":"agent","text":"ご連絡ありがとうございます。確認いたします。","time":"10:15"},'
      '{"role":"customer","text":"急ぎで対応をお願いします。","time":"10:31"}'
      ']}}',
  '{"version":"v0.9","updateComponents":{"surfaceId":"billing_console","components":['
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
  '{"version":"v0.9","updateDataModel":{"surfaceId":"billing_console","path":"/knowledge/items","value":['
      '"二重請求が発生した場合の調査手順","返金ポリシー（FAQ）","請求サイクルの変更方法"]}}',
  '{"version":"v0.9","updateDataModel":{"surfaceId":"billing_console","path":"/reply","value":{'
      '"draft":"田中様\\n\\nこの度はご不便をおかけし申し訳ございません。二重請求の件、確認したところ決済システムの重複登録が原因でした。本日中に重複分を返金いたします。",'
      '"canned":"dup_billing"}}}',
];

/// シナリオ②：解約の申し出（status=open / priority=normal / リテンション）
const List<String> _cancelConsole = [
  '{"version":"v0.9","createSurface":{"surfaceId":"cancel_console","catalogId":"https://example.com/catalog/support"}}',
  '{"version":"v0.9","updateComponents":{"surfaceId":"cancel_console","components":['
      '{"id":"root","component":"Column","children":["header","profile","thread"]},'
      '{"id":"header","component":"InquiryHeader","customer":"佐藤 花子","subject":"サービスを解約したい","status":"open","priority":"normal"},'
      '{"id":"profile","component":"CustomerProfileCard","name":"佐藤 花子","plan":"Pro","since":"2021-09","email":"sato@example.com"},'
      '{"id":"thread","component":"ConversationThread","messages":{"path":"/conversation/messages"}}'
      ']}}',
  '{"version":"v0.9","updateDataModel":{"surfaceId":"cancel_console","path":"/conversation/messages","value":['
      '{"role":"customer","text":"もう使わないので解約したいです。","time":"14:20"},'
      '{"role":"agent","text":"ご利用ありがとうございました。差し支えなければ理由を伺えますか？","time":"14:25"},'
      '{"role":"customer","text":"他社に乗り換えるためです。","time":"14:28"}'
      ']}}',
  '{"version":"v0.9","updateComponents":{"surfaceId":"cancel_console","components":['
      '{"id":"root","component":"Column","children":["header","profile","thread","knowledge","canned","reply","actions"]},'
      '{"id":"knowledge","component":"KnowledgeSuggestion","items":{"path":"/knowledge/items"}},'
      '{"id":"canned","component":"CannedResponsePicker","value":{"path":"/reply/canned"},"options":['
      '{"label":"継続割引を提案","value":"retention_offer"},'
      '{"label":"解約手続きを案内","value":"cancel_flow"},'
      '{"label":"データ移行を案内","value":"data_export"}]},'
      '{"id":"reply","component":"ReplyBox","value":{"path":"/reply/draft"},"action":{"event":{"name":"sendReply","context":{"draft":{"path":"/reply/draft"}}}}},'
      '{"id":"actions","component":"QuickActions","actions":['
      '{"label":"継続割引を適用","name":"applyDiscount"},'
      '{"label":"解約を確定","name":"confirmCancel"},'
      '{"label":"保留にする","name":"hold"}]}'
      ']}}',
  '{"version":"v0.9","updateDataModel":{"surfaceId":"cancel_console","path":"/knowledge/items","value":['
      '"解約フローと注意点","リテンション（引き止め）オファー一覧","データエクスポート手順"]}}',
  '{"version":"v0.9","updateDataModel":{"surfaceId":"cancel_console","path":"/reply","value":{'
      '"draft":"佐藤様\\n\\nこれまでご利用いただきありがとうございます。乗り換えをご検討とのこと、もしよろしければ次回更新分を20%割引でご提供できます。引き続きご検討いただけますでしょうか。",'
      '"canned":"retention_offer"}}}',
];

/// シナリオ③：ログイン障害（status=open / priority=urgent / SLA超過）
const List<String> _incidentConsole = [
  '{"version":"v0.9","createSurface":{"surfaceId":"incident_console","catalogId":"https://example.com/catalog/support"}}',
  '{"version":"v0.9","updateComponents":{"surfaceId":"incident_console","components":['
      '{"id":"root","component":"Column","children":["header","sla","profile","thread"]},'
      '{"id":"header","component":"InquiryHeader","customer":"山田商事（株）","subject":"管理画面にログインできない","status":"open","priority":"urgent"},'
      '{"id":"sla","component":"SlaIndicator","remaining":"超過 0:45","level":"over"},'
      '{"id":"profile","component":"CustomerProfileCard","name":"山田 太郎","plan":"Enterprise","since":"2019-02","email":"yamada@example.co.jp"},'
      '{"id":"thread","component":"ConversationThread","messages":{"path":"/conversation/messages"}}'
      ']}}',
  '{"version":"v0.9","updateDataModel":{"surfaceId":"incident_console","path":"/conversation/messages","value":['
      '{"role":"customer","text":"朝からログインできず業務が止まっています。至急対応をお願いします。","time":"09:05"},'
      '{"role":"agent","text":"ご不便をおかけしております。状況を確認いたします。","time":"09:08"}'
      ']}}',
  '{"version":"v0.9","updateComponents":{"surfaceId":"incident_console","components":['
      '{"id":"root","component":"Column","children":["header","sla","profile","thread","knowledge","canned","reply","actions"]},'
      '{"id":"knowledge","component":"KnowledgeSuggestion","items":{"path":"/knowledge/items"}},'
      '{"id":"canned","component":"CannedResponsePicker","value":{"path":"/reply/canned"},"options":['
      '{"label":"障害調査開始の連絡","value":"incident_ack"},'
      '{"label":"回避策の案内","value":"workaround"},'
      '{"label":"復旧見込みの連絡","value":"eta"}]},'
      '{"id":"reply","component":"ReplyBox","value":{"path":"/reply/draft"},"action":{"event":{"name":"sendReply","context":{"draft":{"path":"/reply/draft"}}}}},'
      '{"id":"actions","component":"QuickActions","actions":['
      '{"label":"インシデント起票","name":"createIncident"},'
      '{"label":"緊急エスカレーション","name":"escalate"},'
      '{"label":"ステータスページ更新","name":"updateStatus"}]}'
      ']}}',
  '{"version":"v0.9","updateDataModel":{"surfaceId":"incident_console","path":"/knowledge/items","value":['
      '"ログイン障害の一次切り分け","認証基盤の稼働状況ページ","緊急エスカレーション手順"]}}',
  '{"version":"v0.9","updateDataModel":{"surfaceId":"incident_console","path":"/reply","value":{'
      '"draft":"山田様\\n\\nご不便をおかけし申し訳ございません。現在ログイン障害を調査しております。回避策として、シークレットウィンドウでの再ログインをお試しください。復旧見込みは追ってご連絡いたします。",'
      '"canned":"incident_ack"}}}',
];
