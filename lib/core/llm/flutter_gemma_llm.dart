import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'llm_backend.dart';

/// 実機オンデバイス推論バックエンド（Gemma 3n / Gemma 4 等）。
///
/// `flutter_gemma` 経由でモデルをロードし、A2UI JSONL をストリーム生成する。
/// モデルは gated（ライセンス同意が必要）なので、初回は HuggingFace から
/// ダウンロードする（`--dart-define` でトークンとURLを渡す）。
///
/// 実行例:
/// ```
/// flutter run -d <device> \
///   --dart-define=HUGGINGFACE_TOKEN=hf_xxx \
///   --dart-define=GEMMA_MODEL_URL=https://huggingface.co/.../gemma-3n-E2B-it.task
/// ```
class FlutterGemmaLlm implements LlmBackend {
  FlutterGemmaLlm({
    required this.modelUrl,
    this.hfToken,
    this.displayName = 'Gemma 4 E2B',
    this.maxTokens = 2048,
    this.temperature = 0.2,
    this.topK = 1,
  });

  final String modelUrl;
  final String? hfToken;
  final String displayName;
  final int maxTokens;
  final double temperature;
  final int topK;

  InferenceModel? _model;
  bool _ready = false;

  /// 0..100 のダウンロード進捗（UI 表示用）。
  final ValueNotifier<double> downloadProgress = ValueNotifier<double>(0);

  /// 状態テキスト（"初期化中" / "モデルDL中" / "準備完了" など）。
  final ValueNotifier<String> phase = ValueNotifier<String>('未初期化');

  @override
  String get name => displayName;

  @override
  bool get isReady => _ready;

  /// モデルの取得（必要なら HF からDL）とロード。3GB級なので初回は数分かかる。
  @override
  Future<void> warmup() async {
    if (_ready) return;
    phase.value = '初期化中';
    await FlutterGemma.initialize(huggingFaceToken: hfToken);

    phase.value = 'モデル取得中';
    // 拡張子でファイル種別を判定（.litertlm は LiteRT-LM FFI、.task は MediaPipe）。
    final fileType = modelUrl.endsWith('.litertlm')
        ? ModelFileType.litertlm
        : (modelUrl.endsWith('.bin') || modelUrl.endsWith('.tflite'))
            ? ModelFileType.binary
            : ModelFileType.task;
    // Gemma 4 はネイティブ function-calling トークン対応の専用 ModelType。
    await FlutterGemma.installModel(modelType: ModelType.gemma4, fileType: fileType)
        .fromNetwork(modelUrl, token: hfToken)
        .withProgress((p) {
      downloadProgress.value = p.toDouble();
      phase.value = 'モデルDL中 ${p.toStringAsFixed(0)}%';
    }).install(); // 既にインストール済みならDLをスキップして active 化

    phase.value = 'モデルロード中';
    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.gpu,
    );
    _ready = true;
    phase.value = '準備完了';
  }

  @override
  Stream<String> generate({
    required String system,
    required String user,
  }) async* {
    if (_model == null) await warmup();
    final session = await _model!.createSession(
      temperature: temperature,
      topK: topK,
      systemInstruction: system,
    );
    try {
      await session.addQueryChunk(Message.text(text: user, isUser: true));
      yield* session.getResponseAsync();
    } finally {
      await session.close();
    }
  }
}
