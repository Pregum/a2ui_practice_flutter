/// LLM バックエンドの抽象インターフェース。
///
/// 重く環境依存な実機推論（flutter_gemma）と、軽量な Mock を差し替え可能にする。
/// 出力はトークン/チャンク単位でストリームし、progressive rendering を活かす。
abstract class LlmBackend {
  /// system + user プロンプトを渡し、生成テキストをチャンク列としてストリームする。
  Stream<String> generate({required String system, required String user});

  /// モデルロード等の初期化（初回遅延を起動時に前倒しする）。
  Future<void> warmup();

  /// 生成可能な状態か。
  bool get isReady;

  /// 表示用の名前（例: "Mock", "Gemma 3n E2B"）。
  String get name;
}
