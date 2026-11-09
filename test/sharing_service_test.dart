import 'package:azkar/core/config/app_config.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:azkar/features/sharing/sharing_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('male memorial share uses the configured identity and wording', () {
    const page = MemorialPage(
      id: 'page-id',
      ownerUserId: 'private-owner@example.test',
      slug: 'member-page',
      title: 'Owner Account Name',
      deceasedGender: 'male',
      deceasedName: 'أحمد محمد',
      dedicationMessage: 'صدقة جارية عن روحه.',
    );

    final message = SharingService.memorialText(page);

    expect(
      message,
      'صدقة جارية على روح عزيزٍ رحل: أحمد محمد\n\n'
      'صدقة جارية عن روحه.\n\n'
      'نسألكم الدعاء له بالرحمة والمغفرة.',
    );
    expect(message, isNot(contains(page.ownerUserId)));
    expect(message, isNot(contains(page.title)));
  });

  test(
    'memorial share handles missing optional details and encodes the slug',
    () {
      const page = MemorialPage(
        id: 'page-id',
        ownerUserId: 'private-owner-id',
        slug: 'memorial page',
        title: 'Private account title',
      );

      expect(
        SharingService.memorialText(page),
        'صدقة جارية على روح عزيزٍ رحل\n\n'
        'نسألكم الدعاء بالرحمة والمغفرة.',
      );
      expect(
        SharingService.memorialLink(page),
        '${AppConfig.siteBaseUrl}/m/memorial%20page',
      );
    },
  );

  test('female memorial share uses the selected page identity and link', () {
    const page = MemorialPage(
      id: 'page-id',
      ownerUserId: 'private-owner@example.test',
      slug: 'fatemah-memorial',
      title: 'Private account name',
      deceasedGender: 'female',
      deceasedName: 'فاطمة',
      dedicationMessage: 'دعاء لها.',
    );

    final message = SharingService.memorialText(page);

    expect(message, contains('صدقة جارية على روح عزيزةٍ رحلت: فاطمة'));
    expect(message, isNot(contains('اللهم اغفر لها وارحمها')));
    expect(message, contains('نسألكم الدعاء لها بالرحمة والمغفرة.'));
    expect(message, isNot(contains('له/لها')));
    expect(message, contains(page.dedicationMessage!));
    expect(message, isNot(contains(page.ownerUserId)));
    expect(message, isNot(contains(page.title)));
    expect(SharingService.memorialLink(page), endsWith('/m/fatemah-memorial'));
  });

  test(
    'the user-written prayer is shared once without an automatic duplicate',
    () {
      const prayer = 'اللهم اغفر له وارحمه وأسكنه الفردوس الأعلى';
      const page = MemorialPage(
        id: 'page',
        ownerUserId: 'owner',
        slug: 'example',
        title: 'Example',
        deceasedName: 'أحمد',
        deceasedGender: 'male',
        dedicationMessage: prayer,
      );
      final message = SharingService.memorialText(page);
      expect(message, contains(prayer));
      expect(message.split('اللهم اغفر له وارحمه').length - 1, 1);
    },
  );
}
