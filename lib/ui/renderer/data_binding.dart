import '../../core/a2ui/state/data_model.dart';

/// データバインド解決。
///
/// 規則: ある値が「`path` 1キーだけを持つ Map」なら dataModel から解決、
/// それ以外はリテラルとして扱う。
class DataBinding {
  const DataBinding(this._model);
  final DataModel _model;

  bool _isPathRef(dynamic v) =>
      v is Map && v.length == 1 && v.containsKey('path') && v['path'] is String;

  /// 1階層の解決。path 参照なら dataModel から取得、リテラルならそのまま。
  dynamic resolve(dynamic value) {
    if (_isPathRef(value)) return _model.get(value['path'] as String);
    return value;
  }

  /// String として解決（null は空文字）。
  String resolveString(dynamic value) {
    final r = resolve(value);
    return r?.toString() ?? '';
  }

  /// ネストした構造を再帰的に解決（action.context などイベント送出用）。
  dynamic resolveDeep(dynamic value) {
    if (_isPathRef(value)) return _model.get(value['path'] as String);
    if (value is Map) {
      return value.map((k, v) => MapEntry(k, resolveDeep(v)));
    }
    if (value is List) return value.map(resolveDeep).toList();
    return value;
  }

  /// path 参照の path 文字列を返す（双方向バインドの書き戻し先に使う）。
  String? pathOf(dynamic value) =>
      _isPathRef(value) ? value['path'] as String : null;
}
