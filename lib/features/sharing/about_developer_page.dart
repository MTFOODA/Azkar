import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/design/app_palette.dart';
import '../../core/design/azkar_brand.dart';
import 'sharing_service.dart';

class AboutDeveloperPage extends StatelessWidget {
  const AboutDeveloperPage({super.key});

  static const linkedInUrl =
      'https://www.linkedin.com/in/mohamed-fooda-08b00132a';
  static const githubUrl = 'https://github.com/MTFOODA';

  @override
  Widget build(BuildContext context) {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppPalette.spaceMd),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppPalette.spaceLg),
              child: Directionality(
                textDirection: isEnglish
                    ? TextDirection.ltr
                    : TextDirection.rtl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AzkarBrandLockup(markSize: 64)),
                    const SizedBox(height: AppPalette.spaceLg),
                    Text(
                      isEnglish ? 'About the Developer' : 'عن المطوّر',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppPalette.spaceMd),
                    Text(
                      'Mohamed Fooda',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppPalette.spaceLg),
                    Text(
                      isEnglish
                          ? 'AZKAR is an ongoing charity. We ask Allah to accept it and reward everyone who reads, shares, and contributes to spreading good.'
                          : 'هذا التطبيق صدقة جارية، نسأل الله أن يتقبله وأن يجعل أجره لكل من قرأ وشارك وساهم في نشر الخير.',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppPalette.spaceLg),
                    FilledButton.icon(
                      key: const ValueKey('android-apk-download'),
                      onPressed: () =>
                          _downloadAndroid(context, isEnglish: isEnglish),
                      icon: const Icon(Icons.android),
                      label: Text(
                        isEnglish
                            ? 'Download Android app'
                            : 'تحميل نسخة أندرويد',
                      ),
                    ),
                    if (_androidVersion != null) ...[
                      const SizedBox(height: AppPalette.spaceSm),
                      Text(
                        isEnglish
                            ? 'Android version $_androidVersion'
                            : 'إصدار أندرويد $_androidVersion',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: AppPalette.spaceLg),
                    OutlinedButton.icon(
                      onPressed: () => _openProfile(
                        context,
                        linkedInUrl,
                        isEnglish: isEnglish,
                      ),
                      icon: const FaIcon(
                        FontAwesomeIcons.linkedinIn,
                        size: 20,
                        semanticLabel: 'LinkedIn',
                      ),
                      label: const Text('LinkedIn'),
                    ),
                    const SizedBox(height: AppPalette.spaceSm),
                    OutlinedButton.icon(
                      onPressed: () => _openProfile(
                        context,
                        githubUrl,
                        isEnglish: isEnglish,
                      ),
                      icon: const FaIcon(
                        FontAwesomeIcons.github,
                        size: 20,
                        semanticLabel: 'GitHub',
                      ),
                      label: const Text('GitHub'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? get _androidVersion {
    for (final segment
        in AppConfig.androidApkDownloadUri?.pathSegments ?? <String>[]) {
      final match = RegExp(r'^v(\d+\.\d+\.\d+(?:[-+][\w.-]+)?)$')
          .firstMatch(segment);
      if (match != null) return match.group(1);
    }
    return null;
  }

  Future<void> _downloadAndroid(
    BuildContext context, {
    required bool isEnglish,
  }) async {
    final uri = AppConfig.androidApkDownloadUri;
    final opened =
        uri != null && await SharingService.openExternal(uri.toString());
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uri == null
                ? (isEnglish
                      ? 'The Android download is not available yet.'
                      : 'رابط تحميل نسخة أندرويد غير متاح حالياً.')
                : (isEnglish
                      ? 'Unable to open the Android download.'
                      : 'تعذّر فتح رابط تحميل أندرويد.'),
          ),
        ),
      );
    }
  }

  Future<void> _openProfile(
    BuildContext context,
    String url, {
    required bool isEnglish,
  }) async {
    final opened = await SharingService.openExternal(url);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEnglish
                ? 'Unable to open the profile link.'
                : 'تعذّر فتح رابط الملف الشخصي.',
          ),
        ),
      );
    }
  }
}
