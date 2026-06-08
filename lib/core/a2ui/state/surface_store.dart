import 'package:flutter/foundation.dart';

import '../message/a2ui_message.dart';
import 'surface.dart';

/// 受信ログの1エントリ（デモのログパネル表示用）。
class LogEntry {
  const LogEntry(this.kind, this.text);
  final LogKind kind;
  final String text;
}

enum LogKind { message, data, skip, error, event, info }

/// 複数サーフェスを保持し、A2UI メッセージを適用する状態ストア。
///
/// メッセージ適用ごとに [notifyListeners] するため、ストリーミングで
/// 届くメッセージを順次描画できる（progressive rendering）。
class SurfaceStore extends ChangeNotifier {
  final Map<String, Surface> _surfaces = {};
  String? _activeSurfaceId;
  final List<LogEntry> _log = [];

  Surface? get active =>
      _activeSurfaceId == null ? null : _surfaces[_activeSurfaceId];
  List<LogEntry> get log => List.unmodifiable(_log);

  void addLog(LogKind kind, String text) {
    _log.add(LogEntry(kind, text));
    notifyListeners();
  }

  void reset() {
    _surfaces.clear();
    _activeSurfaceId = null;
    _log.clear();
    notifyListeners();
  }

  /// ログは残したままサーフェスだけ破棄する（自己修正の再試行用）。
  void clearSurfaces() {
    _surfaces.clear();
    _activeSurfaceId = null;
    notifyListeners();
  }

  /// A2UI メッセージを1件適用する。
  void apply(A2uiMessage msg) {
    switch (msg) {
      case CreateSurface(:final surfaceId, :final catalogId):
        _surfaces[surfaceId] =
            Surface(surfaceId: surfaceId, catalogId: catalogId);
        _activeSurfaceId = surfaceId;
        _log.add(LogEntry(
            LogKind.message, 'createSurface  $surfaceId  ($catalogId)'));
      case UpdateComponents(:final surfaceId, :final components):
        final s = _surfaces[surfaceId];
        if (s != null) {
          s.upsertComponents(components);
          _log.add(LogEntry(LogKind.message,
              'updateComponents  $surfaceId  (+${components.length})'));
        }
      case UpdateDataModel(:final surfaceId, :final path, :final value):
        final s = _surfaces[surfaceId];
        if (s != null) {
          s.dataModel.set(path, value);
          _log.add(LogEntry(LogKind.data, 'updateDataModel  $path'));
        }
      case DeleteSurface(:final surfaceId):
        _surfaces.remove(surfaceId);
        if (_activeSurfaceId == surfaceId) _activeSurfaceId = null;
        _log.add(LogEntry(LogKind.message, 'deleteSurface  $surfaceId'));
    }
    notifyListeners();
  }

  /// ユーザー操作（TextField / ChoicePicker 等）による双方向バインド。
  void setData(String surfaceId, String path, dynamic value) {
    _surfaces[surfaceId]?.dataModel.set(path, value);
    notifyListeners();
  }
}
