import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/design/azkar_brand.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/widgets/adaptive_layout.dart';
import '../../../core/widgets/state_views.dart';
import '../../memorial/presentation/memorial_identity_card.dart';
import '../data/bismillah_loader.dart';

/// Shows only the signed-in account's own dedications, without memorial content.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountSessionProvider);
    final pages = account == null
        ? null
        : ref.watch(ownedMemorialPagesProvider);
    return SingleChildScrollView(
      child: PageContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HomeHero(),
            const SizedBox(height: AppPalette.spaceLg),
            if (pages != null)
              pages.when(
                loading: () => const LoadingView(),
                error: (error, stackTrace) => ErrorView(
                  error: error,
                  onRetry: () => ref.invalidate(ownedMemorialPagesProvider),
                ),
                data: (items) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final page in items.where(
                      (page) =>
                          page.ownerUserId == account!.id &&
                          (page.deceasedName?.trim().isNotEmpty ?? false),
                    )) ...[
                      MemorialIdentityCard(
                        key: ValueKey('home-dedication-${page.id}'),
                        page: page,
                      ),
                      const SizedBox(height: AppPalette.spaceMd),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppPalette.spaceXl),
          ],
        ),
      ),
    );
  }
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
      ],
    );
  }
}
