/// A2UI コンポーネント（隣接リストの1ノード）。
///
/// `components` はフラットな配列で送られ、親子関係は id 参照で表す。
/// id・component 以外のフィールドは [props] にそのまま保持する。
class A2uiComponent {
  const A2uiComponent({
    required this.id,
    required this.type,
    required this.props,
  });

  /// 一意なID。サーフェス内にちょうど1つ "root" が存在する想定。
  final String id;

  /// コンポーネント種別（例: "Text", "InquiryHeader"）。JSON の "component" フィールド。
  final String type;

  /// id・component を除いた残りのフィールド。
  final Map<String, dynamic> props;

  factory A2uiComponent.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final type = json['component'];
    if (id is! String || type is! String) {
      throw const FormatException('component には id と component(型) が必須です');
    }
    final props = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('component');
    return A2uiComponent(id: id, type: type, props: props);
  }

  /// children（配列）を返す。無ければ空。
  List<String> get childIds {
    final c = props['children'];
    if (c is List) return c.whereType<String>().toList();
    return const [];
  }

  /// 単一の child を返す。無ければ null。
  String? get childId => props['child'] is String ? props['child'] as String : null;
}
