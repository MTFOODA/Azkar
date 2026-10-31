import '../../core/design/card_shape.dart';
import '../../features/content/domain/card_style.dart';
import '../../features/content/domain/content_item.dart';
import '../../features/content/domain/content_type.dart';

/// Development-only sample records for the offline demo backend.
///
/// Deliberately contains **no Quran verses and no Hadith**: sacred content is
/// never invented for a demo. The short dhikr phrases below are taken from the
/// requested feature examples and are visibly labelled as sample data in the UI.
class DemoSeed {
  const DemoSeed._();

  static List<ContentItem> content() {
    final now = DateTime.now().toUtc();
    const azkarStyle = CardStyle(
      fontSize: 32,
      fontWeight: 500,
      lineHeight: 2.1,
      shape: CardShapeId.primary,
    );
    const dedicationStyle = CardStyle(
      fontFamily: 'aref_ruqaa',
      fontSize: 30,
      shape: CardShapeId.secondary,
    );

    return <ContentItem>[
      ContentItem(
        id: 'demo-azkar-001',
        type: ContentType.azkar,
        title: 'عينة — ذكر',
        arabicText: 'سبحان الله وبحمده، سبحان الله العظيم',
        description: 'نص تجريبي لعرض تصميم بطاقة الذكر.',
        style: azkarStyle,
        displayOrder: 0,
        isPublished: true,
        createdAt: now,
        updatedAt: now,
      ),
      ContentItem(
        id: 'demo-dua-001',
        type: ContentType.dua,
        title: 'عينة — دعاء',
        arabicText: 'اللهم اغفر لي وارحمني وارزقني من فضلك',
        description: 'نص تجريبي لعرض بطاقة الدعاء.',
        style: azkarStyle.copyWith(fontFamily: 'scheherazade_new'),
        displayOrder: 0,
        isPublished: true,
        createdAt: now,
        updatedAt: now,
      ),
      for (var i = 0; i < _tasbeehTexts.length; i++)
        ContentItem(
          id: 'demo-tasbeeh-${(i + 1).toString().padLeft(3, '0')}',
          type: ContentType.tasbeeh,
          title: 'عينة — تسبيح',
          arabicText: _tasbeehTexts[i],
          style: azkarStyle.copyWith(fontSize: 30),
          displayOrder: i,
          isPublished: true,
          createdAt: now,
          updatedAt: now,
        ),
      ContentItem(
        id: 'demo-dedication-001',
        type: ContentType.dedication,
        title: 'عينة — صدقة جارية',
        personName: 'اسم الشخص',
        dedicationMessage: 'صدقة جارية على روح',
        arabicText: 'اللهم اغفر له وارحمه\nوأسكنه فسيح جناتك',
        recipient: DedicationRecipient.male,
        style: dedicationStyle,
        displayOrder: 0,
        isPublished: true,
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  static const List<String> _tasbeehTexts = <String>[
    'سبحان الله',
    'الحمد لله',
    'الله أكبر',
    'لا إله إلا الله',
    'أستغفر الله',
    'اللهم صلِّ على محمد',
  ];
}
