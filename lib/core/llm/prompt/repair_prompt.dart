import '../../a2ui/validation/validation_error.dart';

/// 検証失敗時の自己修正プロンプト（§3 の形式）。
///
/// 検出エラーをモデルに返し、JSON のみで再生成させる。先頭エラーを
/// 構造化ブロックに、全件を箇条書きで添える。
String buildRepairPrompt(List<ValidationError> errors, String surfaceId) {
  final primary = errors.first;
  final list = errors.map((e) => '- [${e.code}] ${e.path}: ${e.message}').join('\n');
  return '''
直前の出力は A2UI スキーマ検証に失敗しました。以下を修正し、
JSON のみを再出力してください（説明は不要）。

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
- id が "root" のコンポーネントを必ず1つ含める。
- children / child に書いた id は必ず定義する。
- カタログ外のコンポーネントは使わない。
''';
}
