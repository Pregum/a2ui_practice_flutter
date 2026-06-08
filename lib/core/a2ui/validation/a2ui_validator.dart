import '../state/surface.dart';
import 'validation_error.dart';

/// support カタログで使えるコンポーネント名（これ以外はカタログ外）。
const Set<String> supportCatalogComponents = {
  // レイアウト
  'Column', 'Row', 'Card', 'Text',
  // サポート専用
  'InquiryHeader', 'CustomerProfileCard', 'ConversationThread',
  'StatusBadge', 'PriorityTag', 'SlaIndicator', 'KnowledgeSuggestion',
  'CannedResponsePicker', 'ReplyBox', 'QuickActions',
};

/// A2UI サーフェスのスキーマ検証。
///
/// 検査項目（設計ドキュメントの表に対応）:
/// - root が存在するか
/// - children / child の参照先が全て定義済みか
/// - コンポーネント型がカタログに含まれるか
/// - レイアウトの構造（Column/Row は children、Card は child を持つ）
class A2uiValidator {
  const A2uiValidator({this.catalog = supportCatalogComponents});

  final Set<String> catalog;

  List<ValidationError> validate(Surface s) {
    final errors = <ValidationError>[];
    final sid = s.surfaceId;

    // 1) root の存在
    if (!s.components.containsKey('root')) {
      errors.add(ValidationError(
        code: 'MISSING_ROOT',
        surfaceId: sid,
        path: '/components',
        message: 'id が "root" のコンポーネントが1つ必要です',
      ));
    }

    for (final c in s.components.values) {
      final path = '/components/${c.id}';

      // 2) カタログ外の型
      if (!catalog.contains(c.type)) {
        errors.add(ValidationError(
          code: 'UNKNOWN_COMPONENT',
          surfaceId: sid,
          path: path,
          message: '"${c.type}" はカタログ外のコンポーネントです（使用不可）',
        ));
      }

      // 3) 構造（レイアウトの必須フィールド）
      switch (c.type) {
        case 'Column' || 'Row':
          if (c.props['children'] is! List) {
            errors.add(ValidationError(
              code: 'INVALID_STRUCTURE',
              surfaceId: sid,
              path: '$path/children',
              message: '${c.type} には children（配列）が必要です',
            ));
          }
        case 'Card':
          if (c.childId == null) {
            errors.add(ValidationError(
              code: 'INVALID_STRUCTURE',
              surfaceId: sid,
              path: '$path/child',
              message: 'Card には child（id）が必要です',
            ));
          }
      }

      // 4) 参照先が定義済みか（child / children）
      for (final ref in [if (c.childId != null) c.childId!, ...c.childIds]) {
        if (!s.components.containsKey(ref)) {
          errors.add(ValidationError(
            code: 'UNDEFINED_REF',
            surfaceId: sid,
            path: path,
            message: '参照先 "$ref" が未定義です（children/child の id は必ず定義する）',
          ));
        }
      }
    }

    return errors;
  }
}
