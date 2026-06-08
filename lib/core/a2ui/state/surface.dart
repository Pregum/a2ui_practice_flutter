import '../component/a2ui_component.dart';
import 'data_model.dart';

/// 1つの画面（サーフェス）。コンポーネント群（id→component）と
/// データモデルを保持する。
class Surface {
  Surface({required this.surfaceId, required this.catalogId});

  final String surfaceId;
  final String catalogId;

  /// id をキーにしたコンポーネント表（隣接リストの実体）。
  final Map<String, A2uiComponent> components = {};

  final DataModel dataModel = DataModel();

  /// root が到着しているか。描画開始の判定に使う（progressive rendering）。
  bool get hasRoot => components.containsKey('root');

  void upsertComponents(List<A2uiComponent> list) {
    for (final c in list) {
      components[c.id] = c;
    }
  }
}
