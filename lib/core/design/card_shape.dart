/// The card silhouettes the administrator can choose from.
///
/// [primary] and [secondary] reproduce the CSS geometry
/// ```
/// /* primary   */ border-radius: 50% 10% 50% 10% / 10% 50% 10% 50%;
/// /* secondary */ border-radius: 10% 50% 10% 50% / 50% 10% 50% 10%;
/// ```
/// i.e. per-corner elliptical radii with horizontal percentages
/// `TL 50%, TR 10%, BR 50%, BL 10%` and vertical percentages
/// `TL 10%, TR 50%, BR 10%, BL 50%`.
///
/// [rounded] and [rectangle] are calm fallbacks for dense or very long content.
enum CardShapeId { primary, secondary, rounded, rectangle }

extension CardShapeIdX on CardShapeId {
  String get id => switch (this) {
    CardShapeId.primary => 'primary',
    CardShapeId.secondary => 'secondary',
    CardShapeId.rounded => 'rounded',
    CardShapeId.rectangle => 'rectangle',
  };

  String get labelAr => switch (this) {
    CardShapeId.primary => 'شكل أساسي (قوس)',
    CardShapeId.secondary => 'شكل معاكس (إهداء)',
    CardShapeId.rounded => 'زوايا ناعمة',
    CardShapeId.rectangle => 'مستطيل',
  };

  static CardShapeId fromId(String? value) {
    return switch (value) {
      'secondary' => CardShapeId.secondary,
      'rounded' => CardShapeId.rounded,
      'rectangle' => CardShapeId.rectangle,
      _ => CardShapeId.primary,
    };
  }
}
