import '../component/a2ui_component.dart';

/// A2UI v0.9 のメッセージ（JSONL 1行 = 1メッセージ）。
///
/// 各メッセージは createSurface / updateComponents / updateDataModel /
/// deleteSurface のうち、ちょうど1つのキーを持つ。
sealed class A2uiMessage {
  const A2uiMessage({required this.version});

  final String version;

  /// JSON Map から該当するメッセージを生成する。判別できなければ
  /// [FormatException] を投げる。
  static A2uiMessage fromJson(Map<String, dynamic> json) {
    final version = (json['version'] as String?) ?? 'v0.9';
    if (json['createSurface'] case final Map<String, dynamic> m) {
      return CreateSurface(
        version: version,
        surfaceId: m['surfaceId'] as String,
        catalogId: m['catalogId'] as String? ?? '',
      );
    }
    if (json['updateComponents'] case final Map<String, dynamic> m) {
      final raw = (m['components'] as List?) ?? const [];
      return UpdateComponents(
        version: version,
        surfaceId: m['surfaceId'] as String,
        components: raw
            .whereType<Map<String, dynamic>>()
            .map(A2uiComponent.fromJson)
            .toList(),
      );
    }
    if (json['updateDataModel'] case final Map<String, dynamic> m) {
      return UpdateDataModel(
        version: version,
        surfaceId: m['surfaceId'] as String,
        path: m['path'] as String,
        value: m['value'],
      );
    }
    if (json['deleteSurface'] case final Map<String, dynamic> m) {
      return DeleteSurface(
        version: version,
        surfaceId: m['surfaceId'] as String,
      );
    }
    throw const FormatException('A2UI メッセージのキーが見つかりません');
  }
}

/// 画面を作る。最初に1回。
class CreateSurface extends A2uiMessage {
  const CreateSurface({
    required super.version,
    required this.surfaceId,
    required this.catalogId,
  });

  final String surfaceId;
  final String catalogId;
}

/// コンポーネントを置く（フラット配列・root 必須）。
class UpdateComponents extends A2uiMessage {
  const UpdateComponents({
    required super.version,
    required this.surfaceId,
    required this.components,
  });

  final String surfaceId;
  final List<A2uiComponent> components;
}

/// 表示データを入れる（path は JSON Pointer）。
class UpdateDataModel extends A2uiMessage {
  const UpdateDataModel({
    required super.version,
    required this.surfaceId,
    required this.path,
    required this.value,
  });

  final String surfaceId;
  final String path;
  final dynamic value;
}

/// 画面を消す。
class DeleteSurface extends A2uiMessage {
  const DeleteSurface({
    required super.version,
    required this.surfaceId,
  });

  final String surfaceId;
}
