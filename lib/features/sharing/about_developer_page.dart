import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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
                    const SizedBox(height: AppPalette.spaceXs),
                    Text(
                      'Flutter Developer',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppPalette.spaceLg),
                    Text(
                      isEnglish
                          ? 'AZKAR was developed to provide a simple and thoughtful Islamic experience, combining ease of use with modern design.'
                          : 'تم تطوير تطبيق أذكار بهدف تقديم تجربة إسلامية بسيطة ومميزة، تجمع بين سهولة الاستخدام والتصميم العصري.',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
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
