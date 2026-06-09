/// 実機 Gemma の設定。
///
/// 既定は **Gemma 4 E2B（LiteRT-LM, 認証不要）**。公式 LiteRT コミュニティ配布で
/// gated ではないため、トークン無しでそのままダウンロードできる。
/// 別モデル/別端末最適化版を使う場合だけ `--dart-define` で上書きする。
///
/// ```
/// flutter run -d <device>                       # 既定 Gemma 4 E2B でOK（token不要）
/// flutter run -d <device> \                      # 上書きする場合
///   --dart-define=GEMMA_MODEL_URL=https://huggingface.co/.../model.litertlm \
///   --dart-define=HUGGINGFACE_TOKEN=hf_xxx       # gated モデルを使う時だけ
/// ```
class GemmaConfig {
  /// HuggingFace アクセストークン（gated モデルを使う時だけ必要。既定は空でOK）。
  static const String hfToken = String.fromEnvironment('HUGGINGFACE_TOKEN');

  /// モデルファイルURL（.litertlm）。既定は Gemma 4 E2B（2.4GB・認証不要・
  /// 汎用ビルド。Pixel 等の端末別最適化版もあるが汎用版が安全）。
  static const String modelUrl = String.fromEnvironment(
    'GEMMA_MODEL_URL',
    defaultValue:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
  );

  /// ローカルのモデルファイルパス（あれば DL せず fromFile で読む＝使い回し）。
  /// 既定はアプリの外部 files ディレクトリ（権限不要・再インストールでも残る）。
  /// ここに `adb push` しておけば二度とダウンロードしない。
  static const String modelPath = String.fromEnvironment(
    'GEMMA_MODEL_PATH',
    defaultValue:
        '/storage/emulated/0/Android/data/com.xtone.a2ui_support_demo/files/gemma-4-E2B-it.litertlm',
  );

  /// 表示名（badge 等）。
  static const String displayName = String.fromEnvironment(
    'GEMMA_DISPLAY_NAME',
    defaultValue: 'Gemma 4 E2B',
  );

  /// トークンは空文字なら未指定として扱う（非 gated モデルでは不要）。
  static String? get tokenOrNull => hfToken.isEmpty ? null : hfToken;

  /// モデルURLがあれば実機 Gemma を試せる（既定URLがあるので常に true）。
  static bool get isConfigured => modelUrl.isNotEmpty;
}
