import '../../a2ui/validation/validation_error.dart';

/// 検証失敗時の自己修正プロンプト（§3 の形式）。
///
/// 検出エラーをモデルに返し、JSON のみで再生成させる。先頭エラーを
/// 構造化ブロックに、全件を箇条書きで添える。
///
/// [request] は元のユーザー要望。実機 LLM はセッションごとに記憶がなく
/// 「直前の出力」を見ていないため、何のUIを作り直すのかを必ず伝える。
String buildRepairPrompt(
  List<ValidationError> errors,
  String surfaceId, {
  String? request,
}) {
  final primary = errors.first;
  final list = errors.map((e) => '- [${e.code}] ${e.path}: ${e.message}').join('\n');
  final requestBlock =
      request == null ? '' : '\n元の要望（このUIを正しく作り直す）:\n$request\n';
  return '''
直前の出力は A2UI スキーマ検証に失敗しました。以下を修正し、
JSON のみを再出力してください（説明は不要）。
$requestBlock
error:
{
  "code": "VALIDATION_FAILED",
  "surfaceId": "$surfaceId",
  "path": "${primary.path}",
  "message": "${primary.message}"
}

検出された問題:
$list

修正の指針:
- createSurface → updateComponents の順に、要望に合う画面を丸ごと再出力する。
- id が "root" のコンポーネントを必ず1つ含める。
- children / child に書いた id は必ず定義する。
- カタログ外のコンポーネントは使わない。
''';
}
