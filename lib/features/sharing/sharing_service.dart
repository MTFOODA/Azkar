import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/app_logger.dart';
import '../memorial/domain/memorial_page.dart';

/// A share destination that works without a third-party sharing plugin.
enum ShareTarget { system, whatsapp, telegram, facebook, copy }

extension ShareTargetX on ShareTarget {
  String get labelAr => switch (this) {
    ShareTarget.system => 'مشاركة عبر التطبيقات',
    ShareTarget.whatsapp => 'واتساب',
    ShareTarget.telegram => 'تيليجرام',
    ShareTarget.facebook => 'فيسبوك',
    ShareTarget.copy => 'نسخ الرابط',
  };
}

/// Sharing helpers for the website and for individual content cards.
///
/// URL-based destinations open the installed app on Android/iOS and the web app
/// in a browser. Copy is always available as a fallback, including on browsers
/// that do not expose a native share sheet.
class SharingService {
  const SharingService._();

  static String get websiteText =>
      '${AppConfig.siteTitle}\n${AppConfig.siteDescription}\n${AppConfig.siteBaseUrl}';

  static String websiteLink() => AppConfig.siteBaseUrl;

  static String contentLink({required String type, required String id}) =>
      AppConfig.contentLink(type: type, id: id);

  static String memorialText(MemorialPage page) {
    final deceasedName = page.deceasedName?.trim() ?? '';
    final dedication = page.dedicationMessage?.trim() ?? '';
    final memorialPhrase = switch (page.deceasedGender) {
      'female' =>
        deceasedName.isEmpty
            ? 'صدقة جارية على روح عزيزةٍ رحلت'
            : 'صدقة جارية على روح عزيزةٍ رحلت: $deceasedName',
      _ =>
        deceasedName.isEmpty
            ? 'صدقة جارية على روح عزيزٍ رحل'
            : 'صدقة جارية على روح عزيزٍ رحل: $deceasedName',
    };
    return [
      memorialPhrase,
      if (dedication.isNotEmpty) dedication,
      switch (page.deceasedGender) {
        'male' => 'نسألكم الدعاء له بالرحمة والمغفرة.',
        'female' => 'نسألكم الدعاء لها بالرحمة والمغفرة.',
        _ => 'نسألكم الدعاء بالرحمة والمغفرة.',
      },
    ].join('\n\n');
  }

  static String memorialLink(MemorialPage page) =>
      AppConfig.memorialPageLink(page.slug);

  static Future<bool> copyText(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (error, stackTrace) {
      AppLogger.warning('Clipboard copy failed', error, stackTrace);
      return false;
    }
  }

  static Future<bool> share(
    ShareTarget target, {
    required String text,
    required String link,
  }) async {
    switch (target) {
      case ShareTarget.system:
        return _systemShare(text, link);
      case ShareTarget.copy:
        return copyText('$text\n$link');
      case ShareTarget.whatsapp:
        return _open(
          Uri.https('wa.me', '/', <String, String>{'text': '$text\n$link'}),
        );
      case ShareTarget.telegram:
        return _open(
          Uri.https('t.me', '/share/url', <String, String>{
            'url': link,
            'text': text,
          }),
        );
      case ShareTarget.facebook:
        return _open(
          Uri.https('www.facebook.com', '/sharer/sharer.php', <String, String>{
            'u': link,
          }),
        );
    }
  }

  static Future<bool> _systemShare(String text, String link) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(title: text, text: '$text\n$link'),
      );
      return result.status == ShareResultStatus.success;
    } catch (error, stackTrace) {
      AppLogger.warning('System share sheet failed', error, stackTrace);
      return false;
    }
  }

  static Future<bool> openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    return _open(uri);
  }

  static Future<bool> _open(Uri uri) async {
    try {
      if (uri.isAbsolute && (uri.scheme == 'https' || uri.scheme == 'http')) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank',
        );
        if (!launched) {
          // Some browsers reject externalApplication; platformDefault is a safe
          // second attempt and still stays on the same validated URI.
          final launched2 = await launchUrl(
            uri,
            mode: LaunchMode.platformDefault,
            webOnlyWindowName: '_blank',
          );
          return launched2;
        }
        return launched;
      }
      return false;
    } catch (error, stackTrace) {
      AppLogger.warning('External link launch failed', error, stackTrace);
      return false;
    }
  }
}
