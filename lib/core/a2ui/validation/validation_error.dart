/// A2UI スキーマ検証エラー。§3 の自己修正プロンプトに渡す形式に対応する
/// （code / surfaceId / path / message）。
class ValidationError {
  const ValidationError({
    required this.code,
    required this.surfaceId,
    required this.path,
    required this.message,
  });

  /// 失敗種別（例: MISSING_ROOT / UNDEFINED_REF / UNKNOWN_COMPONENT）。
  final String code;
  final String surfaceId;

  /// 失敗したフィールドの JSON Pointer 風パス（例: /components/note）。
  final String path;
  final String message;

  @override
  String toString() => '$code @ $path: $message';
}
