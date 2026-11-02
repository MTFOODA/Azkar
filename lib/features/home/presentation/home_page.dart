import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/design/azkar_brand.dart';
import '../../../core/widgets/adaptive_layout.dart';
import '../data/bismillah_loader.dart';

/// The general homepage keeps the AZKAR identity without memorial content.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    child: PageContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeHero(),
          SizedBox(height: AppPalette.spaceXl),
        ],
      ),
    ),
  );
}

class HomeHero extends StatelessWidget {
  const HomeHero({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: AppPalette.spaceLg),
        const AzkarBrandLockup(markSize: 88),
        const SizedBox(height: AppPalette.spaceSm),
        Text(
          'أذكار • أدعية • قرآن • أحاديث',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppPalette.spaceXl),
        FutureBuilder<String>(
          future: BismillahLoader.load(),
          builder: (context, snapshot) {
            final bismillah = snapshot.data ?? '';
            return Column(
              children: [
                if (bismillah.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppPalette.spaceMd),
                    child: Text(
                      bismillah,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        height: 2,
                        color: theme.colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                Text(
                  'صدقة جارية نسأل الله قبولها',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppPalette.spaceLg),
        FilledButton.icon(
          onPressed: () => context.push('/worship'),
          icon: const Icon(Icons.mosque_outlined),
          label: const Text('مواقيت الصلاة والعبادة'),
        ),
      ],
    );
  }
}
