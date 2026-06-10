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

/// トークンストリーム（LLM 出力）から A2UI メッセージを取り出す。
///
/// 基本は JSONL（1行1メッセージ）だが、小型モデルは1つの JSON の途中に
/// 改行を入れてくることがある（行ベースだと updateComponents 丸ごと取り
/// こぼし、root 不在で検証落ちする）。そのため行ではなく **波括弧の対応**
/// で1オブジェクトを確定する。文字列リテラル内の `{}` やエスケープは無視。
/// JSON 以外のテキスト（コードフェンスや前置き）は行単位でスキップする。
class JsonlStreamParser {
  String _buffer = '';

  /// チャンクを投入し、確定したオブジェクト/スキップ行の結果を返す。
  List<ParsedLine> feed(String chunk) {
    _buffer += chunk;
    return _drain();
  }

  /// ストリーム終端で呼び、バッファ残りを確定させる。
  List<ParsedLine> flush() {
    final results = _drain();
    final rest = _buffer.trim();
    _buffer = '';
    if (rest.isEmpty) return results;
    results.add(rest.startsWith('{')
        ? _parseObject(rest)
        : ParsedLine(raw: rest, note: '非JSON行をスキップ'));
    return results;
  }

  /// バッファから確定できるところまで取り出す。
  List<ParsedLine> _drain() {
    final results = <ParsedLine>[];
    while (true) {
      final text = _buffer;
      var i = 0;
      while (i < text.length && _isWhitespace(text.codeUnitAt(i))) {
        i++;
      }
      if (i >= text.length) {
        _buffer = '';
        break;
      }
      if (text[i] == '{') {
        final end = _scanObjectEnd(text, i);
        if (end == null) {
          // オブジェクト未完。次チャンクを待つ。
          _buffer = text.substring(i);
          break;
        }
        results.add(_parseObject(text.substring(i, end + 1)));
        _buffer = text.substring(end + 1);
        continue;
      }
      // 非JSONテキスト: 次の改行か '{' までを1行として読み飛ばす。
      final nl = text.indexOf('\n', i);
      final brace = text.indexOf('{', i);
      final int cut;
      if (brace != -1 && (nl == -1 || brace < nl)) {
        cut = brace;
      } else if (nl != -1) {
        cut = nl + 1;
      } else {
        break; // 行未確定。次チャンクを待つ（終端は flush が処理）。
      }
      final skipped = text.substring(i, cut).trim();
      if (skipped.isNotEmpty) {
        results.add(ParsedLine(raw: skipped, note: '非JSON行をスキップ'));
      }
      _buffer = text.substring(cut);
    }
    return results;
  }

  /// [start]（'{' の位置）から対応する閉じ括弧の位置を返す。未完なら null。
  int? _scanObjectEnd(String text, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (inString) {
        if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return null;
  }

  ParsedLine _parseObject(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return ParsedLine(raw: raw, note: 'オブジェクトではない');
      }
      return ParsedLine(raw: raw, message: A2uiMessage.fromJson(json));
    } on FormatException catch (e) {
      // 小型モデルは末尾の閉じ括弧を転置しがち（`}]}` を `]}}` 等）。
      // 開き括弧の構造から閉じ括弧を機械的に直して再パースを試みる。
      final repaired = _repairBrackets(raw);
      if (repaired != null) {
        try {
          final json = jsonDecode(repaired);
          if (json is Map<String, dynamic>) {
            return ParsedLine(
              raw: raw,
              message: A2uiMessage.fromJson(json),
              note: '閉じ括弧を自動修復',
            );
          }
        } on FormatException {
          // 修復不能。元のエラーで報告する。
        }
      }
      return ParsedLine(raw: raw, note: 'JSONパース失敗: ${e.message}');
    }
  }

  /// 閉じ括弧のミスを開き括弧スタックに合わせて修復する。
  ///
  /// - 合わない閉じ括弧（`}` ↔ `]` の転置）は期待される方へ置換。
  /// - 末尾の閉じ残し（トークン切れ）は補完。
  /// - 余分な閉じ括弧が現れたら修復不能として null。
  /// 変更が無い場合も null（再パースの意味がない）。
  String? _repairBrackets(String raw) {
    final out = StringBuffer();
    final stack = <String>[];
    var inString = false;
    var escaped = false;
    var changed = false;
    for (var i = 0; i < raw.length; i++) {
      var c = raw[i];
      if (escaped) {
        escaped = false;
        out.write(c);
        continue;
      }
      if (inString) {
        if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        out.write(c);
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{' || c == '[') {
        stack.add(c);
      } else if (c == '}' || c == ']') {
        if (stack.isEmpty) return null;
        final expect = stack.removeLast() == '{' ? '}' : ']';
        if (c != expect) {
          c = expect;
          changed = true;
        }
      }
      out.write(c);
    }
    while (stack.isNotEmpty) {
      out.write(stack.removeLast() == '{' ? '}' : ']');
      changed = true;
    }
    return changed ? out.toString() : null;
  }

  bool _isWhitespace(int c) => c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d;
}
