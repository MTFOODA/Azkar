import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/design/azkar_brand.dart';
import '../../../core/widgets/adaptive_layout.dart';
import '../../../core/widgets/state_views.dart';
import '../../content/providers/content_providers.dart';
import '../../content/widgets/content_card.dart';
import '../../sharing/public_scaffold.dart';
import '../../sharing/share_widgets.dart';
import '../data/bismillah_loader.dart';

/// The public homepage: hero, dynamically ordered cards and website sharing.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(homeLayoutProvider);
    return layout.when(
      loading: () => const LoadingView(message: 'جارٍ تحميل أذكار…'),
      error: (error, stackTrace) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(homeLayoutProvider),
      ),
      data: (cards) {
        return SingleChildScrollView(
          child: PageContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const HomeHero(),
                const SizedBox(height: AppPalette.spaceXl),
                if (cards.isEmpty)
                  const EmptyView(
                    title: 'لم تُضف بطاقات للرئيسية بعد',
                    message: 'يمكن للمشرف إضافة المحتوى وترتيبه من إدارة الصفحة الرئيسية.',
                  )
                else
                  AdaptiveCardGrid(
                    children: [
                      for (final card in cards)
                        homeCardWidget(card, key: ValueKey(card.key)),
                    ],
                  ),
                const SizedBox(height: AppPalette.spaceXxl),
                const HomeShareSection(),
              ],
            ),
          ),
        );
      },
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
        const SizedBox(height: AppPalette.spaceXl),
        const PublicQuickNav(),
      ],
    );
  }
}

class HomeShareSection extends StatelessWidget {
  const HomeShareSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppPalette.spaceXl),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppPalette.radiusLg),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Text(
            'شارك الأجر مع من تحب',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppPalette.spaceMd),
          const ShareWebsiteButton(),
        ],
      ),
    );
  }
}
