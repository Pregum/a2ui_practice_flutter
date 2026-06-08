/// JSON Pointer (RFC6901 のサブセット) で読み書きできるデータストア。
///
/// 対応: `/a/b`, `/a/0`（配列インデックス）, `~0`→`~`, `~1`→`/`。
/// set 時は中間のオブジェクトを自動生成する。
class DataModel {
  final Map<String, dynamic> _root = {};

  Map<String, dynamic> get root => _root;

  static List<String> _tokens(String pointer) {
    if (pointer.isEmpty || pointer == '/') return const [];
    final raw = pointer.startsWith('/') ? pointer.substring(1) : pointer;
    return raw
        .split('/')
        .map((t) => t.replaceAll('~1', '/').replaceAll('~0', '~'))
        .toList();
  }

  /// pointer の指す値を返す。見つからなければ null。
  dynamic get(String pointer) {
    dynamic current = _root;
    for (final token in _tokens(pointer)) {
      if (current is Map) {
        current = current[token];
      } else if (current is List) {
        final i = int.tryParse(token);
        if (i == null || i < 0 || i >= current.length) return null;
        current = current[i];
      } else {
        return null;
      }
    }
    return current;
  }

  /// pointer に値を書き込む。中間ノードは Map として自動生成。
  void set(String pointer, dynamic value) {
    final tokens = _tokens(pointer);
    if (tokens.isEmpty) {
      if (value is Map<String, dynamic>) {
        _root
          ..clear()
          ..addAll(value);
      }
      return;
    }
    Map<String, dynamic> node = _root;
    for (var i = 0; i < tokens.length - 1; i++) {
      final t = tokens[i];
      final next = node[t];
      if (next is Map<String, dynamic>) {
        node = next;
      } else {
        final created = <String, dynamic>{};
        node[t] = created;
        node = created;
      }
    }
    node[tokens.last] = value;
  }
}
