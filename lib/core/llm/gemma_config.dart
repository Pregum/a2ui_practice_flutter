/// 実機 Gemma の設定。トークンとモデルURLは `--dart-define` で渡す
/// （gated モデルなので、事前に HuggingFace 上で Gemma のライセンス同意が必要）。
///
/// ```
/// flutter run -d <device> \
///   --dart-define=HUGGINGFACE_TOKEN=hf_xxx \
///   --dart-define=GEMMA_MODEL_URL=https://huggingface.co/.../gemma-3n-E2B-it.task
/// ```
class GemmaConfig {
  /// HuggingFace アクセストークン（gated モデルのDLに必要）。
  static const String hfToken = String.fromEnvironment('HUGGINGFACE_TOKEN');

  /// モデルファイルURL（.litertlm / LiteRT-LM、4-bit 量子化推奨）。
  /// Gemma 4 E2B を既定にする。実URL/ファイル名は配布元で変わり得るので、
  /// ライセンス同意の上 dart-define で上書きすること（下記は要確認のプレースホルダ）。
  static const String modelUrl = String.fromEnvironment(
    'GEMMA_MODEL_URL',
    defaultValue:
        'https://huggingface.co/litert-community/Gemma4-E2B-IT/resolve/main/gemma-4-E2B-it-int4.litertlm',
  );

  /// 表示名（badge 等）。
  static const String displayName = String.fromEnvironment(
    'GEMMA_DISPLAY_NAME',
    defaultValue: 'Gemma 4 E2B',
  );

  /// トークンが設定されていれば実機 Gemma を試せる。
  static bool get isConfigured => hfToken.isNotEmpty;
}
