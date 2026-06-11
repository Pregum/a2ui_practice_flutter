import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'llm_backend.dart';

/// 実機オンデバイス推論バックエンド（Gemma 4 E2B 等）。
///
/// `flutter_gemma` 経由でモデルをロードし、A2UI JSONL をストリーム生成する。
/// 既定モデル（Gemma 4 E2B / LiteRT-LM）は認証不要で DL でき、`modelPath` に
/// ファイルがあれば fromFile で読んで DL を回避する（使い回し）。
/// gated モデルを使う時だけ `--dart-define=HUGGINGFACE_TOKEN=hf_xxx` を渡す。
class FlutterGemmaLlm implements LlmBackend {
  FlutterGemmaLlm({
    required this.modelUrl,
    this.modelPath,
    this.hfToken,
    this.displayName = 'Gemma 4 E2B',
    this.maxTokens = 2048,
    this.temperature = 0.2,
    this.topK = 1,
  });

  final String modelUrl;

  /// ローカルにモデルがあればこのパスから fromFile で読む（DLを回避）。
  final String? modelPath;
  final String? hfToken;
  final String displayName;
  final int maxTokens;
  final double temperature;
  final int topK;

  InferenceModel? _model;
  bool _ready = false;
  bool _usedOnce = false;

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

    // 拡張子でファイル種別を判定（.litertlm は LiteRT-LM FFI、.task は MediaPipe）。
    final ext = (modelPath?.isNotEmpty ?? false) ? modelPath! : modelUrl;
    final fileType = ext.endsWith('.litertlm')
        ? ModelFileType.litertlm
        : (ext.endsWith('.bin') || ext.endsWith('.tflite'))
            ? ModelFileType.binary
            : ModelFileType.task;

    final builder =
        FlutterGemma.installModel(modelType: ModelType.gemma4, fileType: fileType);
    // ローカルにモデルがあれば fromFile（DL回避・使い回し）、無ければ HF からDL。
    if (modelPath != null && File(modelPath!).existsSync()) {
      phase.value = 'ローカルモデル読込';
      await builder.fromFile(modelPath!).install();
    } else {
      phase.value = 'モデル取得中';
      await builder.fromNetwork(modelUrl, token: hfToken).withProgress((p) {
        downloadProgress.value = p.toDouble();
        phase.value = 'モデルDL中 ${p.toStringAsFixed(0)}%';
      }).install();
    }

    phase.value = 'モデルロード中';
    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.gpu,
    );
    _ready = true;
    phase.value = '準備完了';
  }

  /// エンジンを作り直して「1回目」の状態に戻す。
  ///
  /// LiteRT-LM（flutter_gemma 0.16.5 時点）はエンジン作成後の最初のセッション
  /// だけが正常で、2セッション目以降は出力が最初のトークンから縮退ループに
  /// なる（Pixel 6a 実機で再現。プロンプト内容には依存しない）。
  /// モデルファイルは OS のページキャッシュに乗っているため再作成は数秒で済む。
  Future<void> _recreateEngine() async {
    phase.value = 'エンジン再初期化中';
    await _model?.close();
    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.gpu,
    );
    phase.value = '準備完了';
  }

  @override
  Stream<String> generate({
    required String system,
    required String user,
  }) async* {
    if (_model == null) await warmup();
    if (_usedOnce) await _recreateEngine();
    _usedOnce = true;
    final session = await _model!.createSession(
      temperature: temperature,
      topK: topK,
      systemInstruction: system,
    );
    var completed = false;
    try {
      await session.addQueryChunk(Message.text(text: user, isUser: true));
      yield* session.getResponseAsync();
      completed = true;
    } finally {
      // 途中キャンセル（暴走ガード等）の時だけ native の decode を明示停止する。
      // 正常完了後に stopGeneration() を呼ぶと engine 側に CancelProcess が残り、
      // 以降のセッションが最初のトークンから縮退ループになる（実機で確認）。
      if (!completed) {
        try {
          await session.stopGeneration();
        } catch (_) {/* 停止済みなら失敗してよい */}
      }
      await session.close();
    }
  }
}
