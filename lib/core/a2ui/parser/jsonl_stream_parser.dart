import 'dart:convert';

import '../message/a2ui_message.dart';

/// 1行のパース結果。message が null の場合は [note] にスキップ/失敗理由が入る。
class ParsedLine {
  const ParsedLine({required this.raw, this.message, this.note});
  final String raw;
  final A2uiMessage? message;
  final String? note;

  bool get ok => message != null;
}

/// トークンストリーム（LLM 出力）を行単位で確定し、A2UI メッセージへ変換する。
///
/// - 改行が来るまで部分行をバッファし、完全な行だけを JSON 化する。
/// - コードフェンス（```）や前置き等の非JSON行はスキップして [note] に記録。
class JsonlStreamParser {
  final StringBuffer _buffer = StringBuffer();

  /// チャンクを投入し、確定した行ぶんの結果を返す。
  List<ParsedLine> feed(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString();
    final results = <ParsedLine>[];

    var start = 0;
    int nl;
    while ((nl = text.indexOf('\n', start)) != -1) {
      final line = text.substring(start, nl);
      start = nl + 1;
      final parsed = _parseLine(line);
      if (parsed != null) results.add(parsed);
    }

    // 未確定の末尾はバッファに残す。
    _buffer
      ..clear()
      ..write(text.substring(start));
    return results;
  }

  /// ストリーム終端で呼び、バッファ残りを確定させる。
  List<ParsedLine> flush() {
    final rest = _buffer.toString();
    _buffer.clear();
    final parsed = _parseLine(rest);
    return parsed == null ? const [] : [parsed];
  }

  ParsedLine? _parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    // コードフェンスや明らかな非JSON行はスキップ。
    if (trimmed.startsWith('```') || !trimmed.startsWith('{')) {
      return ParsedLine(raw: trimmed, note: '非JSON行をスキップ');
    }
    try {
      final json = jsonDecode(trimmed);
      if (json is! Map<String, dynamic>) {
        return ParsedLine(raw: trimmed, note: 'オブジェクトではない');
      }
      return ParsedLine(raw: trimmed, message: A2uiMessage.fromJson(json));
    } on FormatException catch (e) {
      return ParsedLine(raw: trimmed, note: 'JSONパース失敗: ${e.message}');
    }
  }
}
